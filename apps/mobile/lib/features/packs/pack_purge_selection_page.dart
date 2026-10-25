import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../ui/paper.dart';
import 'pack_file_action.dart';
import 'pack_purge_review.dart';
import '../settings/maintenance_task_detail.dart';

/// The saved choice has its own home; opening it never prepares or deletes files.
class PackPurgeSelectionPage extends StatefulWidget {
  const PackPurgeSelectionPage({
    super.key,
    required this.repository,
    required this.selectionId,
  });
  final LibraryRepository repository;
  final String selectionId;
  @override
  State<PackPurgeSelectionPage> createState() => _PackPurgeSelectionPageState();
}

class _PackPurgeSelectionPageState extends State<PackPurgeSelectionPage> {
  PackPurgeSelections? selections;
  PackPurgeSelection? selection;
  bool busy = false, loading = false;
  String error = '';
  bool get current => selections?.isCurrent == true;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(changed);
    try {
      selections = PackPurgeSelections(widget.repository.createPackFiles());
      unawaited(load());
    } catch (failure) {
      error = packFileFailureMessage(failure);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    if (!current) return;
    setState(() {
      busy = true;
      loading = true;
      error = '';
    });
    try {
      final result = await selections!.read(widget.selectionId);
      if (mounted && current) setState(() => selection = result);
    } catch (failure) {
      if (mounted && current) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          loading = false;
        });
      }
    }
  }

  Future<void> nextBatch() async {
    if (busy || !current || selection == null || selection!.historical) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final latest = await selections!.read(widget.selectionId);
      if (!mounted || !current) return;
      if (latest.historical || latest.remaining.isEmpty) {
        throw const LibraryFailure('没有可继续核对的选择，请重新读取');
      }
      final command = await showPackPurgeReview(
        context,
        widget.repository,
        latest.remaining,
        selectionId: latest.id,
      );
      if (!mounted || !current || command == null) return;
      final outcome = await showPackFileAction(
        context,
        files: selections!.files,
        command: command,
        title: '永久删除本批图片',
        description: command.label,
        confirm: false,
      );
      if (!mounted || !current) return;
      if (outcome != null) await showResult(outcome.task);
    } catch (failure) {
      if (mounted && current) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted && current) {
        final message = error;
        await load();
        if (mounted && message.isNotEmpty) setState(() => error = message);
      } else if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> showResult(PackFileTask task) async {
    if (task.kind != 'pack_permanent') throw const LibraryFailure('原删除任务类型不一致');
    if (task.settled && !task.result!.needsAttention) {
      await selections!.files.acknowledgeTask(task);
      widget.repository.packFilesChanged();
    }
    if (!mounted || !current) return;
    if (widget.repository.capabilities.maintenanceTasks) {
      final catalog = widget.repository.createMaintenanceTasks();
      try {
        final summary = await catalog.task(task.id);
        if (!mounted || !current) return;
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => MaintenanceTaskDetail(
              repository: widget.repository,
              catalog: catalog,
              initial: summary,
            ),
          ),
        );
      } finally {
        catalog.dispose();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            task.result == null
                ? '请在原操作查询结果'
                : '已确认删除 ${task.result!.pagesDeleted}/${task.result!.pagesTotal} 张图片，${task.result!.failed} 个图包未完成',
          ),
        ),
      );
    }
  }

  Future<void> batch(PackPurgeBatch batch) async {
    if (busy || !current || batch.rejected) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (batch.taskId != null) {
        final task = await selections!.files.task(batch.taskId!);
        if (!mounted || !current) return;
        if (task.result != null &&
            (task.result!.total != batch.command.targets.length ||
                task.result!.pagesTotal != batch.command.expectedImages ||
                task.result!.items.any(
                  (v) => !batch.command.targets.contains(v.requestedId),
                ))) {
          throw const LibraryFailure('原批次结果与确认范围不一致');
        }
        await showResult(task);
      } else {
        final result = await showPackFileAction(
          context,
          files: selections!.files,
          command: batch.command,
          title: '查询原删除批次',
          confirm: false,
          readOnly: true,
        );
        if (mounted && current && result != null) await showResult(result.task);
      }
    } catch (failure) {
      if (mounted && current) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted && current) {
        final message = error;
        await load();
        if (mounted && message.isNotEmpty) setState(() => error = message);
      } else if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> discard() async {
    final expected = selection;
    if (busy || !current || expected == null) return;
    final confirmed = await paperSheet<bool>(
      context,
      SheetFrame(
        title: '移除保存的选择',
        children: [
          const Text('只移除本机保存的这份选择。不会删除图片，也不会停止或移除已经提交的任务；原请求仍可在操作任务查询。'),
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
                key: const Key('purge-selection-discard-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移除选择'),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || !current || confirmed != true) return;
    setState(() => busy = true);
    try {
      await selections!.discard(expected);
      if (mounted && current) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = packFileFailureMessage(failure);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = selection, p = Paper.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('保存的删除选择')),
      body: SafeArea(
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!current)
                    Text(
                      '连接或管理数据已变化，请返回后重新打开。',
                      style: TextStyle(color: p.danger),
                    ),
                  if (error.isNotEmpty)
                    Text(
                      error,
                      key: const Key('purge-selection-error'),
                      style: TextStyle(color: p.danger),
                    ),
                  if (value != null && current) ...[
                    Text(
                      '原选择 ${value.ids.length} 个图包',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${value.remaining.length} 个未提交',
                      key: const Key('purge-selection-remaining'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '选择会保存在本机。每批最多1000个，重新核对图片清单并明确确认后才会永久删除；打开或离开此页不会自动执行。',
                    ),
                    if (value.historical)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('历史选择：管理数据已恢复，不能继续执行。请回到回收站重新选择。'),
                      ),
                    const SizedBox(height: 16),
                    if (value.batches.isNotEmpty)
                      const Text(
                        '已确认的批次',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    for (final (index, b) in value.batches.indexed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        key: Key('purge-selection-batch-$index'),
                        title: Text(
                          '第 ${index + 1} 批 · ${b.command.targets.length} 个图包',
                        ),
                        subtitle: Text(
                          b.rejected
                              ? '未受理，选择保留；下一次需重新核对'
                              : b.taskId == null
                              ? '原结果待核对 · 只查询原请求'
                              : '查看原操作的真实结果',
                        ),
                        trailing: b.rejected
                            ? null
                            : const Icon(Icons.chevron_right),
                        onTap: busy || b.rejected ? null : () => batch(b),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!value.historical && value.remaining.isNotEmpty)
                          FilledButton(
                            key: const Key('purge-selection-next'),
                            onPressed: busy ? null : nextBatch,
                            child: Text(
                              '核对下一批 ${value.remaining.length.clamp(0, 1000)} 个',
                            ),
                          ),
                        TextButton(
                          onPressed: busy ? null : load,
                          child: const Text('重新读取'),
                        ),
                        TextButton(
                          key: const Key('purge-selection-discard'),
                          onPressed: busy ? null : discard,
                          child: const Text('移除保存的选择'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.repository.removeListener(changed);
    super.dispose();
  }
}
