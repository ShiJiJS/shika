import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../ui/paper.dart';
import '../../ui/paper_management.dart';

Future<PackFileTask?> showPackPurgeResult(
  BuildContext context,
  LibraryRepository repository,
  PackFiles files,
  PackFileTask task,
) => Navigator.of(context).push<PackFileTask>(
  MaterialPageRoute(
    builder: (_) =>
        PackPurgeResult(repository: repository, files: files, initial: task),
  ),
);

class PackPurgeResult extends StatefulWidget {
  const PackPurgeResult({
    super.key,
    required this.repository,
    required this.files,
    required this.initial,
  });
  final LibraryRepository repository;
  final PackFiles files;
  final PackFileTask initial;
  @override
  State<PackPurgeResult> createState() => _PackPurgeResultState();
}

class _PackPurgeResultState extends State<PackPurgeResult> {
  late PackFileTask task = widget.initial;
  PackPurgeGateway? gateway;
  CatalogPage<PackPurgeStep>? page;
  final scroll = ScrollController();
  bool busy = true, unfinished = true;
  String error = '';
  bool get current => widget.files.isCurrent() && gateway?.isCurrent == true;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(changed);
    try {
      gateway = widget.repository.createPackPurge();
      unawaited(load(0));
    } catch (failure) {
      busy = false;
      error = packFileFailureMessage(failure);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> load(int offset, {bool refreshTask = false}) async {
    if (gateway == null || !current) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (refreshTask) {
        final latest = await widget.files.task(task.id);
        if (latest.kind != 'pack_permanent') {
          throw const LibraryFailure('原图包任务类型不一致');
        }
        if (!mounted || !current) return;
        setState(() => task = latest);
        if (latest.settled && !latest.result!.needsAttention) {
          await widget.files.acknowledgeTask(latest);
          widget.repository.packFilesChanged();
        }
      }
      final result = await gateway!.steps(
        task.id,
        offset: offset,
        unfinished: unfinished,
      );
      if (mounted && current) setState(() => page = result);
    } catch (failure) {
      if (mounted) {
        setState(() => error = packFileFailureMessage(failure));
        if (scroll.hasClients) scroll.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> turn(int offset) async {
    await load(offset);
    if (mounted && error.isEmpty && scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final result = task.result, p = Paper.of(context);
    Widget note(String text) => Text(
      text,
      style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
    );
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (task.settled && result!.failed > 0)
          FilledButton(
            onPressed: busy || !current
                ? null
                : () => Navigator.pop(context, task),
            child: const Text('重试原任务'),
          ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PaperManagementHeader(
              title: '永久删除结果',
              closeLabel: '关闭删除结果',
              onClose: () => Navigator.pop(context),
            ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: PaperManagementForm(
                controller: scroll,
                footer: actions,
                children: [
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error,
                        key: const Key('purge-result-error'),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: p.danger,
                        ),
                      ),
                    ),
                  if (!current)
                    Text(
                      '连接或管理数据已变化，请关闭后重新打开。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: p.danger,
                      ),
                    ),
                  if (result != null) ...[
                    Text(
                      '已确认删除 ${result.pagesDeleted}/${result.pagesTotal} 张',
                      key: const Key('pack-purge-result-count'),
                      style: TextStyle(
                        fontSize: 18,
                        fontFamily: 'PaperSerif',
                        height: 1.6,
                        color: Paper.of(context).ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    note('${result.succeeded} 个图包完成 · ${result.failed} 个未完成'),
                    if (result.needsAttention)
                      Text(
                        '${result.pagesPending > 0 ? '还有 ${result.pagesPending} 张图片待核对' : '仍有目录或文件状态待核对'}。请保留原操作，查询或重试原任务以核对结果。',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: p.danger,
                        ),
                      ),
                    if (result.failed > 0)
                      note('已删除的图片不能恢复。恢复图包只保留尚存图片；重试仅处理原清单未完成的内容。'),
                  ] else
                    note('原操作尚未确认结束，请稍后查询。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final flag in [true, false])
                        ChoiceChip(
                          label: Text(flag ? '未完成' : '全部'),
                          selected: unfinished == flag,
                          labelStyle: TextStyle(fontSize: 13, color: p.ink),
                          selectedColor: p.soft,
                          backgroundColor: p.background,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                          side: BorderSide(color: p.line),
                          onSelected: busy || !current
                              ? null
                              : (_) {
                                  setState(() {
                                    unfinished = flag;
                                    page = null;
                                  });
                                  unawaited(turn(0));
                                },
                        ),
                      TextButton(
                        onPressed: busy || !current
                            ? null
                            : () => load(0, refreshTask: true),
                        child: const Text('查询原结果'),
                      ),
                    ],
                  ),
                  if (page?.items.isEmpty == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        unfinished ? '没有未完成的图片或目录' : '没有图片或目录记录',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: p.catalogMeta,
                        ),
                      ),
                    ),
                  for (final row in page?.items ?? <PackPurgeStep>[])
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: p.line)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${row.packName} · ${row.relativePath}',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: Paper.of(context).ink,
                            ),
                          ),
                          note(
                            '${row.kind == 'image' ? '图片' : '目录'} · ${row.outcome == 'succeeded'
                                ? '已删除'
                                : row.outcome == 'retained'
                                ? '已保留'
                                : row.phase == 'needs_attention' || row.phase == 'purging'
                                ? '待核对'
                                : row.outcome == 'failed'
                                ? '未完成，检查目录后可重试'
                                : '等待处理'}',
                          ),
                        ],
                      ),
                    ),
                  if (page != null && page!.total > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: busy || !current || page!.offset == 0
                                ? null
                                : () => turn(page!.offset - 24),
                            child: const Text('上一页'),
                          ),
                          note('共 ${page!.total} 项'),
                          TextButton(
                            onPressed:
                                busy ||
                                    !current ||
                                    page!.offset + page!.items.length >=
                                        page!.total
                                ? null
                                : () => turn(page!.offset + 24),
                            child: const Text('下一页'),
                          ),
                        ],
                      ),
                    ),
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
    scroll.dispose();
    gateway?.dispose();
    super.dispose();
  }
}
