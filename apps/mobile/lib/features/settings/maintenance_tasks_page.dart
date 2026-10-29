import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/backup_file_picker.dart';
import '../../ui/paper.dart';
import '../../ui/paper_management.dart';
import 'maintenance_task_session.dart';
import 'maintenance_task_detail.dart';
import '../packs/pack_purge_selection_page.dart';

class MaintenanceTasksPage extends StatefulWidget {
  const MaintenanceTasksPage({
    super.key,
    required this.repository,
    this.saveBackup,
    this.onOpenBackup,
    this.archiveFiles = const NativeBackupArchiveFiles(),
  });
  final LibraryRepository repository;
  final Future<bool> Function(String)? saveBackup;
  final VoidCallback? onOpenBackup;
  final BackupArchiveFiles archiveFiles;
  @override
  State<MaintenanceTasksPage> createState() => _MaintenanceTasksPageState();
}

class _MaintenanceTasksPageState extends State<MaintenanceTasksPage> {
  MaintenanceTaskSession? session;
  String error = '';
  final scroll = ScrollController();
  String shownError = '';
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
    if (!mounted) return;
    setState(() {});
    final next = '${session?.error}|${session?.pendingError}';
    if (next != shownError && next != '|') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.jumpTo(0);
      });
    }
    shownError = next;
  }

  Future<void> turn({int? start, String? kind, String? state}) async {
    final s = session!;
    await s.load(start: start, kind: kind, state: state);
    if (mounted && s.live && s.error.isEmpty && scroll.hasClients) {
      scroll.jumpTo(0);
    }
  }

  Future<void> detail(MaintenanceTask task) async {
    final s = session!;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final Object source = s.catalog;
    final detailCatalog = source is GraphTaskCatalog
        ? source.forTask(task)
        : task.historical
        ? HistoricalTaskCatalog(s.catalog)
        : s.catalog;
    final result = await Navigator.of(context).push<String>(
      PaperPageRoute(
        builder: (_) => MaintenanceTaskDetail(
          repository: widget.repository,
          catalog: detailCatalog,
          initial: task,
          saveBackup: widget.saveBackup,
          archiveFiles: widget.archiveFiles,
          canOpenBackup: widget.onOpenBackup != null,
        ),
      ),
    );
    if (!identical(detailCatalog, s.catalog)) detailCatalog.dispose();
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
        PaperPageRoute(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(PaperSnackBar(context: context, content: Text(s.message)));
      await s.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = session, p = Paper.of(context);
    if (s == null || !s.live) {
      return Center(
        child: SingleChildScrollView(
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
    Text meta(String text, {bool danger = false}) => Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.7,
        color: danger ? p.danger : p.catalogMeta,
      ),
    );
    return Column(
      children: [
        if (s.loading || s.querying != null) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => s.load(),
            child: ListView.builder(
              key: const PageStorageKey('maintenance-task-list'),
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              itemCount: receipts.length + visible.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5, bottom: 20),
                        child: meta('请求超时不代表操作失败。查询已有任务结果，不重复提交删除或恢复。'),
                      ),
                      if (s.error.isNotEmpty || s.pendingError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: meta(
                            [
                              s.error,
                              s.pendingError,
                            ].where((v) => v.isNotEmpty).join('\n'),
                            danger: true,
                          ),
                        ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<String>(
                            key: const Key('task-family'),
                            value: s.family,
                            style: TextStyle(fontSize: 13, color: p.ink),
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
                                : (value) => turn(start: 0, kind: value),
                          ),
                          TextButton(
                            key: const Key('tasks-refresh'),
                            onPressed: s.loading ? null : () => s.load(),
                            child: const Text('重新读取'),
                          ),
                        ],
                      ),
                      Wrap(
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
                            PaperChoiceChip(
                              key: Key('task-filter-${value.key}'),
                              label: Text(value.value),
                              labelStyle: TextStyle(fontSize: 13, color: p.ink),
                              selectedColor: p.soft,
                              backgroundColor: p.background,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                              side: BorderSide(color: p.line),
                              selected: s.filter == value.key,
                              onSelected: s.loading
                                  ? null
                                  : (_) => turn(start: 0, state: value.key),
                            ),
                        ],
                      ),
                      if (receipts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: meta(
                            receipts.every((v) => v.historical)
                                ? '本机 ${receipts.length} 项历史记录'
                                : '本机 ${receipts.length} 项待处理记录',
                            danger: !receipts.every((v) => v.historical),
                          ),
                        ),
                    ],
                  );
                }
                if (index <= receipts.length) {
                  final receipt = receipts[index - 1];
                  return PaperActionRow(
                    key: Key('task-receipt-${receipt.id}'),
                    title: receipt.title,
                    details: [
                      meta(
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
                    ],
                    trailing: const Icon(Icons.chevron_right, size: 19),
                    onTap: s.querying != null ? null : () => pending(receipt),
                  );
                }
                final at = index - receipts.length - 1;
                if (at < visible.length) {
                  final task = visible[at];
                  return PaperActionRow(
                    key: Key('maintenance-task-${task.id}'),
                    title: task.title,
                    details: [
                      meta(
                        task.stateLabel,
                        danger: [
                          'attention',
                          'failed',
                          'partial',
                          'interrupted',
                        ].contains(task.state),
                      ),
                      if (task.progressLabel.isNotEmpty)
                        meta(task.progressLabel),
                      Text(
                        _date(task.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.7,
                          color: p.catalogMeta,
                        ),
                      ),
                    ],
                    trailing: const Icon(Icons.chevron_right, size: 19),
                    onTap: () => detail(task),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
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
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: p.catalogMeta,
                        ),
                      ),
                    ),
                    if (s.canPrevious || s.canNext)
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            key: const Key('tasks-previous'),
                            onPressed: s.loading || !s.canPrevious
                                ? null
                                : () => turn(
                                    start:
                                        s.offset -
                                        MaintenanceTaskSession.pageSize,
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
                                : () => turn(
                                    start:
                                        s.offset +
                                        MaintenanceTaskSession.pageSize,
                                  ),
                            child: const Text('下一页'),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    session?.removeListener(changed);
    session?.dispose();
    scroll.dispose();
    super.dispose();
  }
}

String _date(double seconds) {
  final date = DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round())
      .toLocal();
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
