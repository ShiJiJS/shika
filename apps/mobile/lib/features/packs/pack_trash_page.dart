import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';
import '../../ui/media_layout.dart';
import 'pack_file_action.dart';
import 'pack_trash_session.dart';
import 'pack_purge_review.dart';
import 'pack_purge_result.dart';

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
    if (mounted) setState(() {});
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
          SnackBar(content: Text(packFileFailureMessage(failure))),
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
          const Text('只重试原清单中未完成的内容，已经删除的图片不会重复处理。图片永久删除后不能恢复。'),
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
      command = await showPackPurgeReview(context, widget.repository, ids);
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(packFileFailureMessage(failure))),
        );
      }
    } finally {
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
          SnackBar(content: Text(packFileFailureMessage(failure))),
        );
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
    if (mounted && retry != null) await retryPermanent(retry);
  }

  Future<void> restore() async {
    await session.restoreSelected();
    if (mounted && session.message.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(session.message)));
    }
  }

  Widget retryRead(bool locked) => TextButton(
    key: const Key('pack-trash-retry'),
    onPressed: locked || session.loading || !session.live
        ? null
        : () => session.load(),
    child: const Text('重新读取'),
  );

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            key: const Key('pack-trash-search'),
            controller: search,
            style: const TextStyle(fontSize: 14),
            enabled: !locked,
            decoration: const InputDecoration(
              hintText: '搜索名称或目录',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => unawaited(session.load(query: value)),
          ),
        ),
        if (session.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
        MediaCatalogToolbar(
          children: [
            Text(
              session.hasLoaded ? '共 ${session.total} 个图包' : '图包回收站',
              key: const Key('pack-trash-count'),
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
            TextButton(
              key: const Key('pack-trash-select-all'),
              onPressed: locked || session.selection.loading || session.loading
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
        if (session.loading || session.restoring || session.selection.loading)
          const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => session.load(),
            child: ListView(
              key: const Key('pack-trash-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Text(
                  '普通移除保留源文件，永久删除不能恢复。恢复图包时保留剩余图片、整包标签和阅读进度。',
                  style: TextStyle(fontSize: 13, color: p.muted),
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
                  CheckboxListTile(
                    key: Key('pack-trash-item-${item.id}'),
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(item.id),
                    onChanged: locked ? null : (_) => session.toggle(item.id),
                    title: Text(item.pack.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.pageCount} 张 · ${switch (item.pack.readState) {
                            PackReadState.reading => '在读',
                            PackReadState.completed => '已读',
                            _ => '未读',
                          }}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          item.originalPath,
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (item.purgedPages > 0)
                          Text(
                            '已有 ${item.purgedPages} 张永久删除，恢复仅限剩余 ${item.pageCount} 张',
                            style: TextStyle(fontSize: 12, color: p.danger),
                          ),
                        if (item.permanentOperationId != null)
                          TextButton(
                            onPressed: locked
                                ? null
                                : () => originalResult(
                                    item.permanentOperationId!,
                                  ),
                            child: const Text('查看原永久删除结果'),
                          ),
                        if (session.failures[item.id] case final String failure)
                          Text(
                            failure,
                            style: TextStyle(fontSize: 12, color: p.danger),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (session.canPrevious || session.canNext)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  key: const Key('pack-trash-previous'),
                  onPressed: !locked && !session.loading && session.canPrevious
                      ? () => session.load(
                          start: session.offset - PackTrashSession.pageSize,
                        )
                      : null,
                  child: const Text('上一页'),
                ),
                Text(
                  '${session.offset ~/ PackTrashSession.pageSize + 1} / ${(session.total / PackTrashSession.pageSize).ceil()}',
                  style: const TextStyle(fontSize: 12),
                ),
                TextButton(
                  key: const Key('pack-trash-next'),
                  onPressed: !locked && !session.loading && session.canNext
                      ? () => session.load(
                          start: session.offset + PackTrashSession.pageSize,
                        )
                      : null,
                  child: const Text('下一页'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected.length > 1000)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '已选 ${selected.length} 个。恢复每批最多1000个；永久删除每批单独核对确认，其余保持选择。',
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                ),
              if (MediaLayout.largeText(context)) Text('已选 ${selected.length}'),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!MediaLayout.largeText(context))
                    Text('已选 ${selected.length}'),
                  if (widget.repository.capabilities.packPermanentDelete &&
                      widget.repository.capabilities.packPurgePreview)
                    TextButton(
                      key: const Key('pack-trash-permanent'),
                      style: TextButton.styleFrom(foregroundColor: p.danger),
                      onPressed:
                          locked ||
                              selected.isEmpty ||
                              session.selection.loading
                          ? null
                          : permanent,
                      child: const Text('永久删除'),
                    ),
                  FilledButton(
                    key: const Key('pack-trash-restore'),
                    onPressed:
                        locked || selected.isEmpty || session.selection.loading
                        ? null
                        : restore,
                    child: Text(session.restoring ? '恢复中…' : '恢复'),
                  ),
                ],
              ),
              if (session.lastResult?.result?.failed case final int failed
                  when failed > 0)
                TextButton(
                  onPressed: locked ? null : retryFailed,
                  child: Text('重试 $failed 个未完成项'),
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
    super.dispose();
  }
}
