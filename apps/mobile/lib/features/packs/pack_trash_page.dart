import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';
import '../../ui/media_layout.dart';
import '../../ui/trash_layout.dart';
import 'pack_file_action.dart';
import 'pack_trash_session.dart';
import 'pack_purge_review.dart';
import 'pack_purge_result.dart';
import 'pack_purge_selection_page.dart';
import '../settings/maintenance_task_detail.dart';

class PackTrashPage extends StatefulWidget {
  const PackTrashPage({
    super.key,
    required this.repository,
    required this.active,
  });
  final LibraryRepository repository;
  final bool active;
  @override
  State<PackTrashPage> createState() => _PackTrashPageState();
}

class _PackTrashPageState extends State<PackTrashPage> {
  PackTrashSession? _session;
  PackTrashSession get session => _session!;
  String initializationError = '';
  final search = TextEditingController();
  bool checking = false;
  final scroll = ScrollController();
  final statusAnchor = GlobalKey();
  String lastError = '';
  String lastMessage = '';

  void revealStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      scroll.jumpTo(0);
      revealFormError(statusAnchor);
    });
  }

  Future<void> page(int start) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await session.load(start: start);
    if (mounted && session.error.isEmpty && scroll.hasClients) {
      scroll.jumpTo(0);
    }
  }

  @override
  void initState() {
    super.initState();
    open();
  }

  void open() {
    try {
      _session = PackTrashSession(widget.repository)..addListener(changed);
      session.setActive(widget.active);
      if (widget.active) unawaited(session.load());
      initializationError = '';
    } catch (failure) {
      initializationError = packFileFailureMessage(failure);
    }
    if (mounted) setState(() {});
  }

  void changed() {
    if (mounted) {
      setState(() {});
      final failure = '${session.error}|${session.selection.error}';
      if (failure != lastError && failure != '|') revealStatus();
      if (session.message.isNotEmpty && session.message != lastMessage) {
        revealStatus();
      }
      lastError = failure;
      lastMessage = session.message;
    }
  }

  @override
  void didUpdateWidget(PackTrashPage old) {
    super.didUpdateWidget(old);
    if (_session == null) {
      if (widget.active) open();
      return;
    }
    if (old.active != widget.active) {
      session.setActive(widget.active);
      if (widget.active) unawaited(session.load());
    }
  }

  Future<void> check(PackFileCommand command, {bool readOnly = true}) async {
    if (checking || session.restoring || !session.live) return;
    setState(() => checking = true);
    try {
      final outcome = await showPackFileAction(
        context,
        files: session.files,
        command: command,
        title: '核对图包操作',
        description: command.label,
        confirm: false,
        readOnly: readOnly,
      );
      if (outcome == null || !mounted || !session.live) return;
      await session.accept(outcome.command, outcome.task);
      await session.load();
      if (mounted && outcome.task.kind == 'pack_permanent') {
        // The result sheet can request an explicit retry after it closes.
        final retry = await showPackPurgeResult(
          context,
          widget.repository,
          session.files,
          outcome.task,
        );
        if (mounted && retry != null) {
          setState(() => checking = false);
          await retryPermanent(retry);
        }
      }
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(
            context: context,
            content: Text(packFileFailureMessage(failure)),
          ),
        );
      }
    } finally {
      if (mounted && session.live) {
        try {
          await session.loadPending();
        } catch (failure) {
          session.error = packFileFailureMessage(failure);
        }
      }
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> checkPending() async {
    if (session.pending.isEmpty || checking || session.restoring) return;
    var command = session.pending.first;
    if (session.pending.length > 1) {
      final selected = await paperSheet<PackFileCommand>(
        context,
        SheetFrame(
          title: '待核对的图包操作',
          children: [
            for (final value in session.pending)
              ListTile(
                title: Text(value.label ?? '图包操作'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      command = selected;
    }
    await check(command);
  }

  Future<void> retryFailed() async {
    final task = session.lastResult;
    if (task == null || task.result!.failed == 0) return;
    if (task.kind == 'pack_permanent') {
      await retryPermanent(task);
      return;
    }
    await check(
      PackFileCommand.retry(packFileRequestId(), task.id),
      readOnly: false,
    );
  }

  Future<void> retryPermanent(PackFileTask task) async {
    if (!mounted || !session.live || task.result == null) return;
    final approved = await paperSheet<bool>(
      context,
      SheetFrame(
        title: '重试原任务',
        children: [
          Text(
            '只重试原清单中未完成的内容，已经删除的图片不会重复处理。图片永久删除后不能恢复。',
            style: TextStyle(
              fontSize: 13,
              height: 1.7,
              color: Paper.of(context).catalogMeta,
            ),
          ),
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
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Paper.of(context).danger,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('确认重试原任务'),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || approved != true || !session.live) return;
    await check(
      PackFileCommand.retry(
        packFileRequestId(),
        task.id,
        targets: task.result!.items.map((v) => v.trashId),
        expectedTaskKind: 'pack_permanent',
        label: '重试原永久删除任务',
      ),
      readOnly: false,
    );
  }

  Future<void> permanent() async {
    if (checking ||
        session.restoring ||
        !session.live ||
        session.selection.ids.isEmpty) {
      return;
    }
    setState(() => checking = true);
    PackFileCommand? command;
    try {
      session.selection.cancel();
      final ids = session.selection.ids.toList()..sort();
      await session.loadPending();
      if (!mounted || !session.live) return;
      final resources = ids.take(1000).map((id) => 'trash:$id').toSet();
      if (session.pending.any(
        (c) => c.resources.intersection(resources).isNotEmpty,
      )) {
        throw const LibraryFailure('所选图包有待核对操作，请先查询原结果');
      }
      final saved = await PackPurgeSelections(session.files).save(ids);
      if (!mounted || !session.live) return;
      command = await showPackPurgeReview(
        context,
        widget.repository,
        saved.remaining,
        selectionId: saved.id,
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(
            context: context,
            content: Text(packFileFailureMessage(failure)),
          ),
        );
      }
    } finally {
      if (mounted && session.live) {
        try {
          await session.loadPending();
        } catch (failure) {
          session.error = packFileFailureMessage(failure);
        }
      }
      if (mounted) setState(() => checking = false);
    }
    if (mounted && command != null && session.live) {
      await check(command, readOnly: false);
    }
  }

  Future<void> originalResult(String identity) async {
    if (checking || session.restoring || !session.live) return;
    setState(() => checking = true);
    PackFileTask? retry;
    try {
      final task = await session.files.task(identity);
      if (!mounted || !session.live) return;
      if (task.kind != 'pack_permanent') {
        throw const LibraryFailure('原图包任务类型不一致');
      }
      if (task.settled && !task.result!.needsAttention) {
        await session.files.acknowledgeTask(task);
      }
      if (!mounted) return;
      retry = await showPackPurgeResult(
        context,
        widget.repository,
        session.files,
        task,
      );
      await session.load();
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(
            context: context,
            content: Text(packFileFailureMessage(failure)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
    if (mounted && retry != null) await retryPermanent(retry);
  }

  Future<void> savedSelection() async {
    if (checking || session.restoring || !session.live) return;
    final values = session.purgeSelections;
    if (values.isEmpty) return;
    var value = values.first;
    if (values.length > 1) {
      final picked = await paperSheet<PackPurgeSelection>(
        context,
        SheetFrame(
          title: '保存的删除选择',
          children: [
            for (final row in values)
              ListTile(
                title: Text(
                  '${row.remaining.length} 个未提交 · 原选择 ${row.ids.length} 个',
                ),
                subtitle: row.historical ? const Text('历史选择，不能继续执行') : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, row),
              ),
          ],
        ),
      );
      if (picked == null || !mounted || !session.live) return;
      value = picked;
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await Navigator.of(context).push<void>(
      PaperPageRoute(
        builder: (_) => PackPurgeSelectionPage(
          repository: widget.repository,
          selectionId: value.id,
        ),
      ),
    );
    if (mounted && session.live) await session.load();
  }

  Future<void> restore({String? id}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ids = id == null ? null : {id};
    if (session.plans != null) {
      final count = (ids ?? session.selection.ids).length;
      final approved = await paperSheet<bool>(
        context,
        SheetFrame(
          title: id == null ? '恢复已选 $count 个图包' : '恢复 1 个图包',
          footer: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('pack-restore-plan-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认整份恢复'),
              ),
            ],
          ),
          children: [
            Text(
              id == null
                  ? '将分批恢复所选图包，保留标签和阅读进度。受理后可离开，在操作任务查看进度或停止后续批次。'
                  : '恢复此图包，保留标签和阅读进度。受理后可离开，在操作任务查看进度。',
              style: TextStyle(height: 1.7),
            ),
          ],
        ),
      );
      if (!mounted || approved != true || !session.live) return;
    }
    await session.restoreSelected(only: ids);
    if (mounted && session.message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        PaperSnackBar(context: context, content: Text(session.message)),
      );
    }
  }

  Future<void> restorePlan({bool pending = false}) async {
    if (checking || !session.live || session.plans == null) return;
    RestorePlanCommand? command;
    if (pending) {
      final entries = session.pendingPlans;
      if (entries.isEmpty) return;
      if (entries.length == 1) {
        command = entries.single.command;
      } else {
        command = await paperSheet<RestorePlanCommand>(
          context,
          SheetFrame(
            title: '恢复计划与停止请求',
            children: [
              for (final entry in entries)
                ListTile(
                  title: Text(entry.command.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, entry.command),
                ),
            ],
          ),
        );
        if (command == null || !mounted || !session.live) return;
      }
    }
    setState(() => checking = true);
    MaintenanceTaskCatalog? catalog;
    try {
      final plan = command != null
          ? await session.plans!.receipt(command)
          : await session.plans!.task(session.lastPlan!.id);
      if (!mounted || !session.live) return;
      if (plan == null) throw const LibraryFailure('原请求尚未确认，记录已保留；未重复提交');
      session.lastPlan = plan;
      if (command != null) {
        // Match direct acceptance: only the original, verified members leave
        // selection. Other choices made while the receipt was unknown remain.
        session.selection.ids.removeAll(command.ids);
        for (final id in command.ids) {
          session.failures.remove(id);
        }
      }
      catalog = widget.repository.createMaintenanceTasks();
      final summary = await catalog.task(plan.id);
      if (!mounted || !session.live) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await Navigator.of(context).push(
        PaperPageRoute(
          builder: (_) => MaintenanceTaskDetail(
            repository: widget.repository,
            catalog: catalog!,
            initial: summary,
          ),
        ),
      );
      if (mounted && session.live) await session.load();
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(
            context: context,
            content: Text(packFileFailureMessage(failure)),
          ),
        );
      }
    } finally {
      catalog?.dispose();
      if (mounted) {
        if (session.live) {
          try {
            await session.loadPending();
          } catch (failure) {
            session.error = packFileFailureMessage(failure);
          }
        }
        if (mounted) setState(() => checking = false);
      }
    }
  }

  Widget retryRead(bool locked) => TextButton(
    key: const Key('pack-trash-retry'),
    onPressed: locked || session.loading || !session.live
        ? null
        : () => session.load(),
    child: const Text('重新读取'),
  );

  Widget notices(bool locked, {bool inList = false}) {
    final p = Paper.of(context);
    return Column(
      key: statusAnchor,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.message.isNotEmpty)
          Text(
            session.message,
            style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
          ),
        if (session.error.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inList ? 0 : 16),
            child: MediaLayout.largeText(context)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(session.error, style: TextStyle(color: p.danger)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: retryRead(locked),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.error,
                          style: TextStyle(color: p.danger),
                        ),
                      ),
                      retryRead(locked),
                    ],
                  ),
          ),
        if (session.selection.error.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inList ? 0 : 16),
            child: Text(
              session.selection.error,
              style: TextStyle(color: p.danger),
            ),
          ),
        if (session.pending.isNotEmpty)
          TextButton(
            key: const Key('pack-trash-pending'),
            onPressed: locked ? null : checkPending,
            child: Text('${session.pending.length} 项图包操作待核对'),
          ),
        if (session.pendingPlans.isNotEmpty)
          TextButton(
            key: const Key('pack-trash-plans-pending'),
            onPressed: locked ? null : () => restorePlan(pending: true),
            child: Text('${session.pendingPlans.length} 项恢复或停止请求待核对'),
          ),
        if (session.purgeSelections.isNotEmpty)
          TextButton(
            key: const Key('pack-trash-saved-purge'),
            onPressed: locked ? null : savedSelection,
            child: Text('${session.purgeSelections.length} 份保存的删除选择'),
          ),
        if (session.lastPlan != null)
          TextButton(
            key: const Key('pack-trash-plan-result'),
            onPressed: locked ? null : restorePlan,
            child: const Text('查看恢复计划'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(initializationError),
              TextButton(onPressed: open, child: const Text('重新读取')),
            ],
          ),
        ),
      );
    }
    final p = Paper.of(context), locked = session.restoring || checking;
    final selected = session.selection.ids;
    final unavailable = locked || session.selection.loading || !session.live;
    final pendingIds = {
      for (final pending in session.pendingPlans)
        if (pending.command.kind == 'restore') ...pending.command.ids,
    };
    final uncertain = selected.intersection(pendingIds).length;
    return TrashLayout(
      listKey: const Key('pack-trash-list'),
      controller: scroll,
      loading:
          session.loading || session.restoring || session.selection.loading,
      onRefresh: () => session.load(),
      actions: TrashActions(
        count: selected.length,
        selectionLabel: uncertain > 0 ? '保留选择 ${selected.length}' : null,
        restoreKey: const Key('pack-trash-restore'),
        permanentKey: const Key('pack-trash-permanent'),
        onRestore: unavailable || selected.isEmpty || uncertain > 0
            ? null
            : () => restore(),
        onPermanent: unavailable || selected.isEmpty || uncertain > 0
            ? null
            : permanent,
        showPermanent:
            widget.repository.capabilities.packPermanentDelete &&
            widget.repository.capabilities.packPurgePreview,
        restoring: session.restoring,
        children: [
          if (uncertain > 0)
            Text(
              '$uncertain 个图包恢复结果待核对，请先查询原请求。',
              style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
            ),
          if (selected.length > 1000)
            Text(
              '已选 ${selected.length} 个。恢复每批最多1000个；永久删除每批单独核对确认，其余保持选择。',
              style: TextStyle(fontSize: 12, height: 1.7, color: p.catalogMeta),
            ),
          if (session.lastResult?.result?.failed case final int failed
              when failed > 0)
            TextButton(
              onPressed: locked ? null : retryFailed,
              child: Text('重试 $failed 个未完成项'),
            ),
        ],
      ),
      children: [
        Text(
          '普通移除保留源文件，永久删除不能恢复。恢复图包时保留剩余图片、整包标签和阅读进度。',
          style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('pack-trash-search'),
          controller: search,
          style: const TextStyle(fontSize: 16),
          enabled: !locked,
          decoration: InputDecoration(
            hintText: '搜索名称或目录',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      search.clear();
                      unawaited(session.load(query: ''));
                    },
                  ),
          ),
          onChanged: (value) {
            if (scroll.hasClients) scroll.jumpTo(0);
            unawaited(session.load(query: value));
          },
        ),
        const SizedBox(height: 8),
        notices(locked, inList: true),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              session.hasLoaded ? '共 ${session.total} 个图包' : '图包回收站',
              key: const Key('pack-trash-count'),
              style: TextStyle(fontSize: 12, color: p.catalogMeta),
            ),
            TextButton(
              key: const Key('pack-trash-refresh'),
              onPressed: locked || session.loading
                  ? null
                  : () => session.load(),
              child: const Text('刷新'),
            ),
            TextButton(
              key: const Key('pack-trash-select-all'),
              onPressed: unavailable || session.loading
                  ? null
                  : () => session.selectAll(),
              child: Text(session.selection.loading ? '正在全选…' : '全选'),
            ),
            if (session.selection.loading)
              TextButton(
                onPressed: () => session.selection.cancel(),
                child: const Text('取消'),
              ),
            if (selected.isNotEmpty && !session.selection.loading)
              TextButton(
                onPressed: locked ? null : session.clearSelection,
                child: const Text('取消选择'),
              ),
          ],
        ),
        if (session.hasLoaded &&
            !session.loading &&
            session.items.isEmpty &&
            session.error.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              session.search.isEmpty ? '图包回收站是空的' : '没有匹配的图包',
              textAlign: TextAlign.center,
            ),
          ),
        for (final item in session.items)
          TrashEntryRow(
            key: Key('pack-trash-item-${item.id}'),
            title: item.pack.displayTitle,
            path: item.originalPath,
            selected: selected.contains(item.id),
            onToggle: locked ? null : () => session.toggle(item.id),
            restoreKey: Key('pack-trash-row-restore-${item.id}'),
            onRestore: unavailable || pendingIds.contains(item.id)
                ? null
                : () => restore(id: item.id),
            details: [
              Text(
                '${item.pageCount} 张 · ${switch (item.pack.readState) {
                  PackReadState.reading => '在读',
                  PackReadState.completed => '已读',
                  _ => '未读',
                }}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: p.catalogMeta,
                ),
              ),
              if (item.purgedPages > 0)
                Text(
                  '已有 ${item.purgedPages} 张永久删除，恢复仅限剩余 ${item.pageCount} 张',
                  style: TextStyle(fontSize: 12, height: 1.7, color: p.danger),
                ),
              if (item.permanentOperationId != null)
                TextButton(
                  onPressed: locked
                      ? null
                      : () => originalResult(item.permanentOperationId!),
                  child: const Text('查看原永久删除结果'),
                ),
              if (session.failures[item.id] case final String failure)
                Text(
                  failure,
                  style: TextStyle(fontSize: 12, height: 1.7, color: p.danger),
                ),
            ],
          ),
        if (session.canPrevious || session.canNext)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  key: const Key('pack-trash-previous'),
                  onPressed: !locked && !session.loading && session.canPrevious
                      ? () => page(session.offset - PackTrashSession.pageSize)
                      : null,
                  child: const Text('上一页'),
                ),
                Text(
                  '${session.offset ~/ PackTrashSession.pageSize + 1} / ${(session.total / PackTrashSession.pageSize).ceil()}',
                  style: TextStyle(fontSize: 12, color: p.catalogMeta),
                ),
                TextButton(
                  key: const Key('pack-trash-next'),
                  onPressed: !locked && !session.loading && session.canNext
                      ? () => page(session.offset + PackTrashSession.pageSize)
                      : null,
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
    _session?.removeListener(changed);
    _session?.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }
}
