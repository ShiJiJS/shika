import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';
import 'maintenance_task_detail.dart';

class MissingMediaPage extends StatefulWidget {
  const MissingMediaPage({super.key, required this.repository});
  final LibraryRepository repository;
  @override
  State<MissingMediaPage> createState() => _MissingMediaPageState();
}

class _MissingRow {
  const _MissingRow(this.id, this.name, this.path, this.tags);
  final String id, name, path, tags;
}

class _MissingMediaPageState extends State<MissingMediaPage> {
  late final gateway = widget.repository.createPackMissing();
  late final tasks = widget.repository.createMaintenanceTasks();
  late final connection = widget.repository.connectionIdentity;
  MediaKind kind = MediaKind.video;
  List<_MissingRow> rows = [];
  List<MissingCleanupReceipt> pending = [];
  MaintenanceTask? task;
  int total = 0, offset = 0, generation = 0;
  static const limit = 24;
  bool loading = true, acting = false;
  String error = '', journalError = '';
  bool get current =>
      identical(connection, widget.repository.connectionIdentity) &&
      gateway.isCurrent &&
      tasks.isCurrent;
  bool get blocked =>
      !current || loading || acting || widget.repository.backupRestorePending;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(ownerChanged);
    unawaited(load());
  }

  void ownerChanged() {
    if (mounted && !current) setState(() => error = '服务连接或管理数据已变化，请返回后重新打开');
  }

  Future<void> load({int at = 0}) async {
    if (!current) return;
    final token = ++generation, selected = kind;
    gateway.cancelPages();
    widget.repository.cancelMissingRead();
    setState(() {
      loading = true;
      error = '';
    });
    try {
      late List<_MissingRow> found;
      late int count;
      if (selected == MediaKind.pack) {
        final data = await gateway.page(offset: at, limit: limit);
        count = data.total;
        found = data.items
            .map(
              (p) => _MissingRow(
                p.id,
                p.name,
                p.path,
                p.tagNames.values.join(' · '),
              ),
            )
            .toList();
      } else {
        final data = await widget.repository.loadMissing(
          offset: at,
          limit: limit,
        );
        count = data.total;
        found = data.items
            .map(
              (v) => _MissingRow(
                v.id,
                v.name,
                v.path,
                v.tags.map(widget.repository.tagName).join(' · '),
              ),
            )
            .toList();
      }
      if (!mounted || !current || token != generation) return;
      setState(() {
        rows = found;
        total = count;
        offset = at;
      });
      await readPending();
      if (task != null) {
        final value = await tasks.task(task!.id);
        if (mounted && current && token == generation) {
          setState(() => task = value);
        }
      }
    } on RequestCancelled {
      // A newer page or connection owns the visible state.
    } catch (e) {
      if (mounted && current && token == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  Future<void> readPending() async {
    try {
      final value = await gateway.pending();
      if (mounted && current) {
        setState(() {
          pending = value;
          journalError = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => journalError = e.toString());
    }
  }

  Future<bool> confirm(String title, String message, String action) async =>
      await paperSheet<bool>(
        context,
        SheetFrame(
          title: title,
          children: [
            Text(message),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const Key('missing-confirm'),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action),
                ),
              ],
            ),
          ],
        ),
      ) ==
      true;
  Future<void> cleanup() async {
    if (blocked || total == 0) return;
    final selected = kind;
    if (!await confirm(
      selected == MediaKind.pack ? '清除失效图包记录？' : '清除失效视频记录？',
      selected == MediaKind.pack
          ? '核对当前全部 $total 个缺失图包。只清除确认仍缺失的管理记录、标签关联、阅读进度、偏好及最近记录，不删除任何源文件。离线、停用、重新出现或有其它操作的内容会保留。清理在后台继续，之后找回会作为新图包入库。'
          : '只清除扫描已确认缺失的视频记录及标签关联，不删除任何源文件。离线或停用目录不会清理；找回后不继承旧标签。',
      '确认清除记录',
    )) {
      return;
    }
    if (!mounted || blocked || selected != kind) return;
    setState(() {
      acting = true;
      error = '';
    });
    try {
      if (selected == MediaKind.pack) {
        final value = await gateway.submit(packFileRequestId());
        if (mounted && current) setState(() => task = value);
      } else {
        await widget.repository.forgetMissingVideos();
      }
      if (mounted && current) await load();
    } catch (e) {
      if (mounted && current) setState(() => error = '清理结果未确认：$e');
      await readPending();
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> query(MissingCleanupReceipt receipt) async {
    if (blocked) return;
    setState(() {
      acting = true;
      error = '';
    });
    try {
      final value = await gateway.query(receipt.requestId);
      if (!mounted || !current) return;
      if (value == null) {
        setState(() => error = '尚未查到原清理请求，未重新提交。可以稍后继续查询或从操作任务核对。');
      } else {
        setState(() => task = value);
        await load();
      }
      await readPending();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> remove(MissingCleanupReceipt receipt) async {
    if (blocked ||
        !await confirm(
          '移除本机待核对入口？',
          '只移除此设备的记录，不会停止已经受理的后台清理。原任务仍可在操作任务中查询；新的清理仍须重新确认。',
          '移除本机入口',
        )) {
      return;
    }
    if (!mounted || !current) return;
    setState(() => acting = true);
    try {
      await gateway.removeLocalReceipt(receipt.requestId);
      await readPending();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> detail() async {
    if (blocked || task == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MaintenanceTaskDetail(
          repository: widget.repository,
          catalog: tasks,
          initial: task!,
        ),
      ),
    );
    if (mounted && current) await load();
  }

  @override
  void dispose() {
    generation++;
    widget.repository.removeListener(ownerChanged);
    widget.repository.cancelMissingRead();
    gateway.dispose();
    tasks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  iconAction(
                    '返回媒体目录',
                    Icons.arrow_back,
                    () => Navigator.pop(context),
                  ),
                  Expanded(child: Text('缺失内容', style: p.title)),
                  iconAction(
                    '刷新缺失内容',
                    Icons.refresh,
                    acting || !current ? null : () => load(at: offset),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in MediaKind.values)
                    ChoiceChip(
                      key: Key('missing-kind-${value.name}'),
                      label: Text(value == MediaKind.video ? '视频' : '图包'),
                      selected: kind == value,
                      onSelected: acting || !current
                          ? null
                          : (_) {
                              setState(() {
                                kind = value;
                                rows = [];
                                total = 0;
                              });
                              unawaited(load());
                            },
                    ),
                ],
              ),
            ),
            if (loading || acting) const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => load(at: offset),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('缺失记录保留原标签和阅读状态。外部内容重新出现后，请先同步目录。'),
                    const SizedBox(height: 12),
                    Text(
                      '共 $total 个缺失${kind == MediaKind.video ? '视频' : '图包'}',
                    ),
                    if (error.isNotEmpty || journalError.isNotEmpty)
                      Text(
                        [
                          error,
                          journalError,
                        ].where((s) => s.isNotEmpty).join('\n'),
                        style: TextStyle(color: p.danger),
                      ),
                    if (error.isNotEmpty)
                      TextButton(
                        onPressed: blocked ? null : () => load(at: offset),
                        child: const Text('重试读取缺失内容'),
                      ),
                    if (kind == MediaKind.pack) ...[
                      for (final receipt in pending) ...[
                        Text(
                          receipt.historical
                              ? '旧管理数据的清理请求 · 只读核对'
                              : '本机清理结果待核对',
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: blocked ? null : () => query(receipt),
                              child: const Text('查询原清理请求'),
                            ),
                            TextButton(
                              onPressed: blocked ? null : () => remove(receipt),
                              child: const Text('移除本机入口'),
                            ),
                          ],
                        ),
                      ],
                      if (task != null)
                        ListTile(
                          key: const Key('missing-cleanup-task'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(task!.title),
                          subtitle: Text(
                            '${task!.stateLabel}\n${task!.progressLabel}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: blocked ? null : detail,
                        ),
                    ],
                    TextButton(
                      key: const Key('clear-missing-kind'),
                      onPressed:
                          blocked ||
                              error.isNotEmpty ||
                              total == 0 ||
                              widget
                                  .repository
                                  .libraryPreparation
                                  .value
                                  .scanning ||
                              (kind == MediaKind.pack &&
                                  (journalError.isNotEmpty ||
                                      pending.any((r) => !r.historical)))
                          ? null
                          : cleanup,
                      child: Text(
                        '清除失效${kind == MediaKind.video ? '视频' : '图包'}记录',
                      ),
                    ),
                    for (final row in rows)
                      ListTile(
                        key: Key('missing-row-${row.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(row.name),
                        subtitle: Text(
                          '${row.path}${row.tags.isEmpty ? '' : '\n${row.tags}'}',
                        ),
                        trailing: const Text('缺失'),
                      ),
                    if (!loading && total == 0 && error.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('暂无缺失内容'),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: blocked || offset == 0
                              ? null
                              : () =>
                                    load(at: (offset - limit).clamp(0, offset)),
                          child: const Text('上一页'),
                        ),
                        Text(
                          total == 0
                              ? '共 0 项'
                              : '${offset + 1}–${offset + rows.length} / $total',
                        ),
                        TextButton(
                          onPressed: blocked || offset + rows.length >= total
                              ? null
                              : () => load(at: offset + limit),
                          child: const Text('下一页'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
