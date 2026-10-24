import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../ui/paper.dart';

Future<PackFileTask?> showPackPurgeResult(
  BuildContext context,
  LibraryRepository repository,
  PackFiles files,
  PackFileTask task,
) => paperSheet<PackFileTask>(
  context,
  PackPurgeResult(repository: repository, files: files, initial: task),
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
  bool busy = true, unfinished = true;
  String error = '';
  @override
  void initState() {
    super.initState();
    try {
      gateway = widget.repository.createPackPurge();
      unawaited(load(0));
    } catch (failure) {
      busy = false;
      error = packFileFailureMessage(failure);
    }
  }

  Future<void> load(int offset, {bool refreshTask = false}) async {
    if (gateway == null) return;
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
        if (!mounted) return;
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
      if (mounted) setState(() => page = result);
    } catch (failure) {
      if (mounted) setState(() => error = packFileFailureMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = task.result, p = Paper.of(context);
    final current = widget.files.isCurrent() && gateway?.isCurrent == true;
    return SheetFrame(
      title: '永久删除结果',
      children: [
        if (result != null) ...[
          Text(
            '已确认删除 ${result.pagesDeleted}/${result.pagesTotal} 张',
            key: const Key('pack-purge-result-count'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text('${result.succeeded} 个图包完成 · ${result.failed} 个未完成'),
          if (result.needsAttention)
            Text(
              '${result.pagesPending > 0 ? '还有 ${result.pagesPending} 张图片待核对' : '仍有目录或文件状态待核对'}。请保留原操作，查询或重试原任务以核对结果。',
              style: TextStyle(color: p.danger),
            ),
          if (result.failed > 0)
            const Text('已删除的图片不能恢复。恢复图包只保留尚存图片；重试仅处理原清单未完成的内容。'),
        ] else
          const Text('原操作尚未确认结束，请稍后查询。'),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('未完成'),
              selected: unfinished,
              onSelected: busy || !current
                  ? null
                  : (_) {
                      setState(() {
                        unfinished = true;
                        page = null;
                      });
                      unawaited(load(0));
                    },
            ),
            ChoiceChip(
              label: const Text('全部'),
              selected: !unfinished,
              onSelected: busy || !current
                  ? null
                  : (_) {
                      setState(() {
                        unfinished = false;
                        page = null;
                      });
                      unawaited(load(0));
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
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error, style: TextStyle(color: p.danger)),
        if (!current)
          Text('连接或管理数据已变化，请关闭后重新打开。', style: TextStyle(color: p.danger)),
        if (page?.items.isEmpty == true)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              unfinished ? '没有未完成的图片或目录' : '没有图片或目录记录',
              textAlign: TextAlign.center,
            ),
          )
        else
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .32,
            child: ListView.builder(
              itemCount: page?.items.length ?? 0,
              itemBuilder: (_, index) {
                final row = page!.items[index];
                final label = row.outcome == 'succeeded'
                    ? '已删除'
                    : row.outcome == 'retained'
                    ? '已保留'
                    : row.phase == 'needs_attention' || row.phase == 'purging'
                    ? '待核对'
                    : row.outcome == 'failed'
                    ? '未完成，检查目录后可重试'
                    : '等待处理';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row.packName} · ${row.relativePath}'),
                  subtitle: Text(
                    '${row.kind == 'image' ? '图片' : '目录'} · $label',
                  ),
                );
              },
            ),
          ),
        if (page != null)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: busy || !current || page!.offset == 0
                    ? null
                    : () => load(page!.offset - 24),
                child: const Text('上一页'),
              ),
              Text('共 ${page!.total} 项'),
              TextButton(
                onPressed:
                    busy ||
                        !current ||
                        page!.offset + page!.items.length >= page!.total
                    ? null
                    : () => load(page!.offset + 24),
                child: const Text('下一页'),
              ),
            ],
          ),
        Wrap(
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
        ),
      ],
    );
  }

  @override
  void dispose() {
    gateway?.dispose();
    super.dispose();
  }
}
