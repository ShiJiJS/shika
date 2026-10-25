import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../library/backup_file_picker.dart';
import '../../library/request_scope.dart';
import '../../ui/paper.dart';
import '../packs/pack_file_action.dart';
import '../packs/pack_purge_result.dart';
import 'purge_history_page.dart';

class MaintenanceTaskDetail extends StatefulWidget {
  const MaintenanceTaskDetail({
    super.key,
    required this.repository,
    required this.catalog,
    required this.initial,
    this.saveBackup,
    this.canOpenBackup = false,
    this.archiveFiles = const NativeBackupArchiveFiles(),
  });
  final LibraryRepository repository;
  final MaintenanceTaskCatalog catalog;
  final MaintenanceTask initial;
  final Future<bool> Function(String)? saveBackup;
  final bool canOpenBackup;
  final BackupArchiveFiles archiveFiles;
  @override
  State<MaintenanceTaskDetail> createState() => _MaintenanceTaskDetailState();
}

class _MaintenanceTaskDetailState extends State<MaintenanceTaskDetail> {
  late MaintenanceTask task = widget.initial;
  CatalogPage<MaintenanceItem>? page;
  bool busy = true, unfinished = true, acting = false;
  String error = '';
  String? snapshot;
  final fileScope = RequestScope();
  int _read = 0;
  PackRestorePlans? plans;
  RestorePlan? restorePlan;
  bool stopPending = false;
  bool get current => widget.catalog.isCurrent;
  bool get members =>
      task.family == 'video' ||
      task.family == 'pack' && task.kind != 'pack_purge_preview';
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(ownerChanged);
    if (task.kind == 'pack_restore_plan' &&
        !task.historical &&
        widget.repository.capabilities.packRestorePlans) {
      plans = widget.repository.createPackRestorePlans();
    }
    unawaited(load(0));
  }

  void ownerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> load(int offset) async {
    if (!current) return;
    final serial = ++_read;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (plans != null) {
        var missingStop = false;
        for (final entry in await plans!.pending()) {
          if (entry.command.kind == 'stop' && entry.taskId == task.id) {
            if (await plans!.receipt(entry.command) == null) missingStop = true;
          }
        }
        final plan = await plans!.task(task.id);
        if (!mounted || !current || serial != _read) return;
        setState(() {
          restorePlan = plan;
          stopPending = missingStop;
        });
        if (missingStop) error = '原停止请求尚未确认，记录已保留；查询不会重复提交';
      }
      final value = await widget.catalog.task(task.id);
      if (!mounted || !current || serial != _read) return;
      if (value.kind != task.kind) throw StateError('task kind changed');
      setState(() => task = value);
      final Object source = widget.catalog;
      if (source is ArchiveTaskFiles &&
          ['backup_restore', 'backup_restore_v2'].contains(value.kind)) {
        final point = await source.restoreSnapshot(value.id);
        if (!mounted || !current || serial != _read) return;
        setState(() => snapshot = point);
      }
      if (members) {
        final result = await widget.catalog.items(
          task.id,
          offset: offset,
          unfinished: unfinished,
        );
        if (!unfinished && value.total != null && result.total != value.total) {
          throw const FormatException('task member count changed');
        }
        if (!mounted || !current || serial != _read) return;
        setState(() => page = result);
      }
    } catch (failure) {
      if (mounted && current && serial == _read) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted && serial == _read) setState(() => busy = false);
    }
  }

  Future<void> stopRestoring() async {
    if (plans == null ||
        busy ||
        acting ||
        !current ||
        restorePlan == null ||
        restorePlan!.settled ||
        restorePlan!.historical ||
        stopPending) {
      return;
    }
    final approved = await paperSheet<bool>(
      context,
      SheetFrame(
        title: '停止后续恢复批次',
        children: [
          const Text('当前已受理批次会先核对真实结果，尚未开始的图包才停止。已经恢复的图包不会重新移入回收站。'),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('restore-plan-stop-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认停止后续批次'),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || !current || approved != true) return;
    setState(() {
      acting = true;
      error = '';
    });
    try {
      final result = await plans!.send(
        RestorePlanCommand.stop(packFileRequestId(), task.id),
      );
      if (!mounted || !current) return;
      if (result == null) throw const LibraryFailure('原停止请求尚未确认，已保留记录；未重复提交');
      setState(() => restorePlan = result);
      widget.repository.packFilesChanged();
      await load(0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.stopRequested ? '已受理停止后续批次，请查询实际结果' : '计划已结束，没有后续批次',
            ),
          ),
        );
      }
    } catch (failure) {
      if (mounted && current) {
        var pending = true;
        try {
          pending = (await plans!.pending()).any(
            (e) => e.command.kind == 'stop' && e.taskId == task.id,
          );
        } catch (_) {
          /* keep uncertainty visible */
        }
        if (mounted) {
          setState(() {
            error = packFileFailureMessage(failure);
            stopPending = pending;
          });
        }
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> images() async {
    if (acting || !current) return;
    setState(() {
      acting = true;
      error = '';
    });
    try {
      final summary = await widget.catalog.task(task.id);
      if (!mounted || !current) return;
      if (summary.historical || summary.kind != 'pack_permanent') {
        throw StateError('historical or changed operation');
      }
      final files = widget.repository.createPackFiles();
      var value = await files.task(task.id);
      while (mounted && current) {
        if (value.kind != 'pack_permanent') {
          throw StateError('task kind changed');
        }
        if (value.settled && !value.result!.needsAttention) {
          await files.acknowledgeTask(value);
        }
        if (!mounted || !current) return;
        final retry = await showPackPurgeResult(
          context,
          widget.repository,
          files,
          value,
        );
        if (!mounted || !current || retry == null) break;
        final result = await showPackFileAction(
          context,
          files: files,
          command: PackFileCommand.retry(
            packFileRequestId(),
            retry.id,
            targets: retry.result!.items.map((v) => v.trashId),
            expectedTaskKind: 'pack_permanent',
            label: '重试原永久删除任务',
          ),
          title: '重试原任务',
          description: '只重试原清单中未完成的内容，已经删除的图片不会重复处理。图片永久删除后不能恢复。',
        );
        if (result == null) break;
        value = result.task;
        widget.repository.packFilesChanged();
      }
      if (mounted && current) await load(0);
    } catch (failure) {
      if (mounted && current) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> historyPurge({bool results = false}) async {
    if (acting || !current) return;
    setState(() {
      acting = true;
      error = '';
    });
    PurgeHistoryDetails? details;
    try {
      final Object source = widget.catalog;
      if (source is! HistoricalPurgeCatalog) {
        throw const LibraryFailure('当前服务未提供历史图片明细');
      }
      details = source.purgeHistory(task);
      if (!mounted || !current) {
        details.dispose();
        return;
      }
      final reader = details;
      details = null; // The history route owns and cancels its reader.
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PurgeHistoryPage(
            repository: widget.repository,
            details: reader,
            task: task,
            results: results,
          ),
        ),
      );
    } catch (failure) {
      details?.dispose();
      if (mounted && current) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> download() async {
    if (acting || !current) return;
    setState(() {
      acting = true;
      error = '';
    });
    try {
      final Object source = widget.catalog;
      final useFile =
          task.kind.endsWith('_v2') ||
          task.kind == 'backup_snapshot' ||
          widget.repository.capabilities.backupV2;
      if (useFile && source is ArchiveTaskFiles) {
        final exported = await source.downloadArchiveFile(task.id);
        try {
          if (!mounted || !current) return;
          if (await widget.archiveFiles.save(
            exported.document,
            scope: fileScope,
          )) {
            if (!mounted || !current) return;
            await widget.catalog.backupSaved(task.id);
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('原备份已保存')));
            }
          }
        } finally {
          await exported.document.delete();
        }
      } else if (widget.saveBackup != null) {
        final contents = await widget.catalog.downloadBackup(task.id);
        if (!mounted || !current) return;
        if (await widget.saveBackup!(contents)) {
          if (!mounted || !current) return;
          await widget.catalog.backupSaved(task.id);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('原备份已保存')));
          }
        }
      }
    } catch (failure) {
      if (mounted && current) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> downloadSnapshot() async {
    if (acting || !current || snapshot == null) return;
    final Object source = widget.catalog;
    if (source is! ArchiveTaskFiles) return;
    setState(() {
      acting = true;
      error = '';
    });
    try {
      final exported = await source.downloadArchiveFile(snapshot!);
      try {
        if (!mounted || !current) return;
        final saved = await widget.archiveFiles.save(
          exported.document,
          scope: fileScope,
        );
        if (saved && mounted && current) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('恢复前快照已保存')));
        }
      } finally {
        await exported.document.delete();
      }
    } catch (failure) {
      if (mounted && current) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Widget summary(BuildContext context) {
    final p = Paper.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            task.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            task.stateLabel,
            key: const Key('maintenance-detail-state'),
            style: TextStyle(
              color:
                  [
                    'attention',
                    'failed',
                    'partial',
                    'interrupted',
                  ].contains(task.state)
                  ? p.danger
                  : p.olive,
            ),
          ),
          if (task.progressLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(task.progressLabel),
            ),
          if (task.historical)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('管理恢复保留的历史记录。查询只读，不重新执行原删除或恢复。'),
            ),
          if (task.kind == 'pack_permanent' && (task.pagesDeleted ?? 0) > 0)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('已永久删除的图片不能恢复。恢复图包仅保留剩余图片。'),
            ),
          if (task.needsAttention)
            Text('仍有文件或目录状态待核对，请保留原任务。', style: TextStyle(color: p.danger)),
          if (task.error != null && !task.historical)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                maintenanceErrorLabel(task.error!),
                style: TextStyle(color: p.danger),
              ),
            ),
          if (task.kind == 'pack_purge_preview')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('清单核对完成不代表已删除图片；删除结果以对应的永久删除任务为准。'),
            ),
          if (task.family == 'backup' && task.kind != 'backup_export')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('导入与恢复前需在备份与恢复中核对文件和目录映射，再明确确认。'),
            ),
          const SizedBox(height: 12),
          SelectableText(
            '任务编号：${task.id}',
            style: TextStyle(fontSize: 12, color: p.muted),
          ),
          if (members)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final flag in [true, false])
                    ChoiceChip(
                      label: Text(flag ? '未完成' : '全部'),
                      selected: unfinished == flag,
                      onSelected: busy || acting || !current
                          ? null
                          : (_) {
                              setState(() {
                                unfinished = flag;
                                page = null;
                              });
                              unawaited(load(0));
                            },
                    ),
                ],
              ),
            ),
          if (task.kind == 'pack_permanent' && !task.historical)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('task-image-results'),
                onPressed:
                    busy ||
                        acting ||
                        !current ||
                        widget.repository.backupRestorePending
                    ? null
                    : images,
                child: const Text('查看逐项图片结果'),
              ),
            ),
          if (task.historical &&
              ['pack_permanent', 'pack_purge_preview'].contains(task.kind)) ...[
            if (widget.catalog case final HistoricalPurgeCatalog source
                when source.supportsPurgeHistory && task.graphId != null)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const Key('task-history-purge-review'),
                    onPressed: busy || acting || !current ? null : historyPurge,
                    child: const Text('查看原精确清单'),
                  ),
                  if (task.kind == 'pack_permanent')
                    TextButton(
                      key: const Key('task-history-image-results'),
                      onPressed: busy || acting || !current
                          ? null
                          : () => historyPurge(results: true),
                      child: const Text('查看逐项图片结果'),
                    ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  task.graphId == null
                      ? '这份记录未保留原图片明细，只能查看任务摘要。'
                      : '当前服务尚未提供这份历史图片明细，请升级服务后重新打开。',
                ),
              ),
          ],
          if (task.kind == 'pack_restore_plan' && !task.historical) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('整份计划由服务端推进，可以离开本页。已停止的图包没有执行恢复，仍保留在回收站。'),
            ),
            if (stopPending)
              Text('停止结果待核对，请查询原请求。', style: TextStyle(color: p.danger)),
            if (restorePlan?.stopRequested == true &&
                restorePlan?.settled != true)
              const Text('停止请求已受理，正在核对当前批次。'),
            if (plans != null &&
                restorePlan != null &&
                !restorePlan!.settled &&
                !restorePlan!.stopRequested)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('restore-plan-stop'),
                  onPressed:
                      busy ||
                          acting ||
                          stopPending ||
                          !current ||
                          widget.repository.backupRestorePending
                      ? null
                      : stopRestoring,
                  child: const Text('停止后续批次'),
                ),
              ),
          ],
          if ([
                'backup_export',
                'backup_snapshot',
                'backup_export_v2',
                'backup_snapshot_v2',
              ].contains(task.kind) &&
              task.status == 'completed' &&
              (widget.saveBackup != null || widget.catalog is ArchiveTaskFiles))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('task-download-backup'),
                onPressed: acting || !current ? null : download,
                child: const Text('下载原备份'),
              ),
            ),
          if (snapshot != null && !['queued', 'running'].contains(task.status))
            TextButton(
              key: const Key('task-download-snapshot'),
              onPressed: acting || !current ? null : downloadSnapshot,
              child: const Text('下载恢复前快照'),
            ),
          if (task.family == 'backup' && widget.canOpenBackup)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: acting
                    ? null
                    : () => Navigator.pop(context, 'backup'),
                child: const Text('前往备份与恢复'),
              ),
            ),
        ],
      ),
    );
  }

  Widget pager() => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        key: const Key('task-items-previous'),
        onPressed: busy || acting || page!.offset == 0
            ? null
            : () => load(page!.offset - 24),
        child: const Text('上一页'),
      ),
      Text('共 ${page!.total} 项'),
      TextButton(
        key: const Key('task-items-next'),
        onPressed:
            busy || acting || page!.offset + page!.items.length >= page!.total
            ? null
            : () => load(page!.offset + 24),
        child: const Text('下一页'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  iconAction(
                    '返回操作任务',
                    Icons.arrow_back,
                    () => Navigator.pop(context),
                  ),
                  Expanded(child: Text('任务详情', style: p.title)),
                  iconAction(
                    '查询原结果',
                    Icons.refresh,
                    busy || acting || !current
                        ? null
                        : () => load(page?.offset ?? 0),
                  ),
                ],
              ),
            ),
            if (busy || acting) const LinearProgressIndicator(),
            if (!current)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('服务连接或管理数据已变化，请返回后重新打开操作任务'),
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => load(page?.offset ?? 0),
                  child: ListView.builder(
                    key: const PageStorageKey('maintenance-task-detail'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    itemCount: (page?.items.length ?? 0) + 3,
                    itemBuilder: (context, index) {
                      if (index == 0) return summary(context);
                      if (index == 1) {
                        return error.isNotEmpty
                            ? Text(error, style: TextStyle(color: p.danger))
                            : const SizedBox.shrink();
                      }
                      final at = index - 2;
                      if (at < (page?.items.length ?? 0)) {
                        final item = page!.items[at];
                        return ListTile(
                          key: Key('task-member-${item.id}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.label),
                              if (item.path.isNotEmpty)
                                Text(
                                  item.path,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (item.error != null &&
                                  item.error != 'plan_stopped')
                                Text(
                                  maintenanceErrorLabel(item.error!),
                                  style: TextStyle(color: p.danger),
                                ),
                            ],
                          ),
                        );
                      }
                      if (page == null) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (page!.items.isEmpty && !busy)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                unfinished ? '没有未完成的图包或视频' : '没有图包或视频明细',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          pager(),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _read++;
    fileScope.cancel();
    widget.repository.removeListener(ownerChanged);
    super.dispose();
  }
}

String maintenanceErrorLabel(String code) =>
    const {
      '图包状态已变化，记录保留': '图包状态已变化，记录保留',
      '已有文件操作或回收记录，记录保留': '已有文件操作或回收记录，记录保留',
      '目录正在同步，记录保留': '目录正在同步，记录保留',
      '目录未启用、暂不可用或归属已变化，记录保留': '目录未启用、暂不可用或归属已变化，记录保留',
      '目录与最近成功同步不一致，请重新同步；记录保留': '目录与最近成功同步不一致，请重新同步；记录保留',
      '内容已重新出现，请同步后核对': '内容已重新出现，请同步后核对',
      '目录已变化，记录保留': '目录已变化，记录保留',
      '目录无法可靠核对，记录保留': '目录无法可靠核对，记录保留',
      'root_unavailable': '媒体目录暂不可用，请检查挂载和启用状态后核对。',
      'manifest_changed': '内容在确认后有变化，请重新核对。',
      'pack_changed': '图包目录已变化，请重新核对。',
      'stale_pack_state': '图包状态已变化，请核对当前内容。',
      'operation_busy': '同一内容还有待核对操作，请先查询原结果。',
      'service_stopped': '服务曾中断，请查询原结果。',
      'operation_recovery_required': '文件操作还需要核对，请保留原任务。',
      'plan_stopped': '已按要求停止未开始的批次，已恢复的图包保持不变。',
      'backup_upgrade_required': '当前管理数据需要媒体库备份 v2 支持。',
      'invalid_mapping': '目录映射不正确，请重新核对。',
      'backup_checksum_mismatch': '备份完整性校验失败，请核对原文件。',
    }[code] ??
    '操作未完成，请核对原结果与当前内容。';
