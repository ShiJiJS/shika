import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../ui/paper.dart';
import 'maintenance_task_session.dart';
import 'maintenance_task_detail.dart';
import '../packs/pack_purge_selection_page.dart';

class MaintenanceTasksPage extends StatefulWidget {
  const MaintenanceTasksPage({
    super.key,
    required this.repository,
    this.saveBackup,
    this.onOpenBackup,
  });
  final LibraryRepository repository;
  final Future<bool> Function(String)? saveBackup;
  final VoidCallback? onOpenBackup;
  @override
  State<MaintenanceTasksPage> createState() => _MaintenanceTasksPageState();
}

class _MaintenanceTasksPageState extends State<MaintenanceTasksPage> {
  MaintenanceTaskSession? session;
  String error = '';
  @override
  void initState() {
    super.initState();
    open();
  }

  void open() {
    session?.removeListener(changed);
    session?.dispose();
    session = null;
    try {
      session = MaintenanceTaskSession(widget.repository)..addListener(changed);
      error = '';
      unawaited(session!.load());
    } catch (failure) {
      error = packFileFailureMessage(failure);
    }
    if (mounted) setState(() {});
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> detail(MaintenanceTask task) async {
    final s = session!;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MaintenanceTaskDetail(
          repository: widget.repository,
          catalog: task.historical
              ? HistoricalTaskCatalog(s.catalog)
              : s.catalog,
          initial: task,
          saveBackup: widget.saveBackup,
          canOpenBackup: widget.onOpenBackup != null,
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'backup') {
      widget.onOpenBackup?.call();
    } else if (s.live) {
      await s.load();
    }
  }

  Future<void> pending(MaintenanceReceipt receipt) async {
    if (receipt.source == MaintenanceReceiptSource.purgeSelection) {
      final s = session!;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PackPurgeSelectionPage(
            repository: widget.repository,
            selectionId: receipt.purgeSelectionId!,
            files: receipt.historyFiles,
          ),
        ),
      );
      if (mounted && s.live) await s.load();
      return;
    }
    final s = session!, task = await session!.query(receipt);
    if (!mounted || !s.live) return;
    if (task != null) {
      await detail(task);
    } else if (s.message.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.message)));
      await s.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = session, p = Paper.of(context);
    if (s == null || !s.live) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s?.error ?? error),
              TextButton(onPressed: open, child: const Text('重新打开')),
            ],
          ),
        ),
      );
    }
    final receipts = s.pending
        .where(
          (v) =>
              (s.family == 'all' || s.family == v.family) &&
              (s.filter == 'all' ||
                  s.filter == (v.historical ? 'historical' : 'attention')),
        )
        .toList();
    final known = receipts.map((v) => v.taskId).whereType<String>().toSet();
    final visible = s.items.where((v) => !known.contains(v.id)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            '请求超时不代表操作失败。查询已有任务结果，不重复提交删除或恢复。',
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                key: const Key('task-family'),
                value: s.family,
                items:
                    const {
                          'all': '全部类型',
                          'scan': '同步',
                          'video': '视频',
                          'pack': '图包',
                          'backup': '备份',
                        }.entries
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.key,
                            child: Text(v.value),
                          ),
                        )
                        .toList(),
                onChanged: s.loading
                    ? null
                    : (value) => s.load(start: 0, kind: value),
              ),
              TextButton(
                key: const Key('tasks-refresh'),
                onPressed: s.loading ? null : () => s.load(),
                child: const Text('重新读取'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in const {
                'all': '全部',
                'processing': '进行中',
                'attention': '待处理',
                'completed': '已完成',
                'historical': '历史',
              }.entries)
                ChoiceChip(
                  key: Key('task-filter-${value.key}'),
                  label: Text(value.value),
                  selected: s.filter == value.key,
                  onSelected: s.loading
                      ? null
                      : (_) => s.load(start: 0, state: value.key),
                ),
            ],
          ),
        ),
        if (s.loading || s.querying != null) const LinearProgressIndicator(),
        if (s.error.isNotEmpty || s.pendingError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              [s.error, s.pendingError].where((v) => v.isNotEmpty).join('\n'),
              style: TextStyle(color: p.danger),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => s.load(),
            child: ListView.builder(
              key: const PageStorageKey('maintenance-task-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: receipts.length + visible.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return receipts.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            receipts.every((v) => v.historical)
                                ? '本机 ${receipts.length} 项历史记录'
                                : '本机 ${receipts.length} 项待处理记录',
                            style: TextStyle(color: p.danger),
                          ),
                        );
                }
                if (index <= receipts.length) {
                  final receipt = receipts[index - 1];
                  return ListTile(
                    key: Key('task-receipt-${receipt.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(receipt.title),
                    subtitle: Text(
                      s.querying == receipt.id
                          ? '正在查询原请求…'
                          : receipt.source ==
                                MaintenanceReceiptSource.purgeSelection
                          ? receipt.historical
                                ? '历史选择 · 只读查看'
                                : '保存的选择 · 每批仍需核对确认'
                          : receipt.historical
                          ? '历史记录 · 只读查询原结果'
                          : '本机结果待核对 · 只查询原请求',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: s.querying != null ? null : () => pending(receipt),
                  );
                }
                final at = index - receipts.length - 1;
                if (at < visible.length) {
                  final task = visible[at];
                  return ListTile(
                    key: Key('maintenance-task-${task.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(task.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.stateLabel,
                          style: TextStyle(
                            color:
                                [
                                  'attention',
                                  'failed',
                                  'partial',
                                  'interrupted',
                                ].contains(task.state)
                                ? p.danger
                                : p.muted,
                          ),
                        ),
                        if (task.progressLabel.isNotEmpty)
                          Text(task.progressLabel),
                        Text(
                          _date(task.createdAt),
                          style: TextStyle(fontSize: 12, color: p.muted),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => detail(task),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    s.hasLoaded &&
                            s.total == 0 &&
                            s.pending.isEmpty &&
                            s.error.isEmpty &&
                            s.pendingError.isEmpty
                        ? s.filter == 'all' && s.family == 'all'
                              ? '暂无操作任务'
                              : '没有符合条件的任务'
                        : s.hasLoaded
                        ? '服务端共 ${s.total} 条任务记录'
                        : '',
                    textAlign: TextAlign.center,
                    key: const Key('tasks-count'),
                  ),
                );
              },
            ),
          ),
        ),
        if (s.canPrevious || s.canNext)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  key: const Key('tasks-previous'),
                  onPressed: s.loading || !s.canPrevious
                      ? null
                      : () => s.load(
                          start: s.offset - MaintenanceTaskSession.pageSize,
                        ),
                  child: const Text('上一页'),
                ),
                Text(
                  '${s.offset ~/ MaintenanceTaskSession.pageSize + 1} / ${(s.total / MaintenanceTaskSession.pageSize).ceil()}',
                ),
                TextButton(
                  key: const Key('tasks-next'),
                  onPressed: s.loading || !s.canNext
                      ? null
                      : () => s.load(
                          start: s.offset + MaintenanceTaskSession.pageSize,
                        ),
                  child: const Text('下一页'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    session?.removeListener(changed);
    session?.dispose();
    super.dispose();
  }
}

String _date(double seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round())
      .toLocal();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
