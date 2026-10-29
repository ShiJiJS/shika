import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../ui/paper.dart';

/// A history reader has no current command gateway or acknowledgment callback.
class PurgeHistoryPage extends StatefulWidget {
  const PurgeHistoryPage({
    super.key,
    required this.repository,
    required this.details,
    required this.task,
    this.results = false,
  }) : member = null,
       ownsDetails = true;
  const PurgeHistoryPage._files({
    required this.repository,
    required this.details,
    required this.task,
    required this.member,
  }) : results = false,
       ownsDetails = false;
  final LibraryRepository repository;
  final PurgeHistoryDetails details;
  final MaintenanceTask task;
  final PackPurgeMember? member;
  final bool results, ownsDetails;
  @override
  State<PurgeHistoryPage> createState() => _PurgeHistoryPageState();
}

class _PurgeHistoryPageState extends State<PurgeHistoryPage> {
  late bool results = widget.results;
  bool busy = true, unfinished = true;
  String kind = 'all', error = '';
  PurgeHistoryReview? review;
  CatalogPage<PackPurgeStep>? steps;
  CatalogPage<PackPurgeImage>? images;
  int serial = 0;
  bool get current => widget.details.isCurrent;
  bool get files => widget.member != null;
  int get offset => files
      ? images?.offset ?? 0
      : results
      ? steps?.offset ?? 0
      : review?.members.offset ?? 0;
  int get total => files
      ? images?.total ?? 0
      : results
      ? steps?.total ?? 0
      : review?.members.total ?? 0;
  int get length => files
      ? images?.items.length ?? 0
      : results
      ? steps?.items.length ?? 0
      : review?.members.items.length ?? 0;
  int get limit => files ? 100 : 24;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(ownerChanged);
    unawaited(load(0));
  }

  void ownerChanged() {
    if (mounted && !current) setState(() {});
  }

  Future<void> load(int at) async {
    if (!current) return;
    final token = ++serial;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      if (files) {
        final value = await widget.details.images(widget.member!, offset: at);
        if (!mounted || !current || token != serial) return;
        setState(() => images = value);
      } else if (results) {
        final summary = review ?? await widget.details.review();
        final value = await widget.details.steps(
          offset: at,
          unfinished: unfinished,
          kind: kind,
        );
        if (!mounted || !current || token != serial) return;
        setState(() {
          review = summary;
          steps = value;
        });
      } else {
        final value = await widget.details.review(offset: at);
        if (!mounted || !current || token != serial) return;
        setState(() => review = value);
      }
    } catch (failure) {
      if (mounted && current && token == serial) {
        setState(() => error = packFileFailureMessage(failure));
      }
    } finally {
      if (mounted && token == serial) setState(() => busy = false);
    }
  }

  Widget header(BuildContext context) {
    final p = Paper.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          files ? widget.member!.name : widget.task.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (files) ...[
          Text(widget.member!.path),
          Text('原清单 ${widget.member!.imageCount} 张图片'),
        ] else ...[
          if (review != null)
            Text('${review!.members.total} 个图包 · ${review!.imageCount} 张图片'),
          if (widget.task.kind == 'pack_permanent')
            Text(
              '已删除 ${widget.task.pagesDeleted ?? 0}/${widget.task.pagesTotal ?? 0} 张${(widget.task.pagesPending ?? 0) > 0 ? ' · ${widget.task.pagesPending} 张待核对' : ''}',
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              PaperChoiceChip(
                key: const Key('purge-history-review'),
                label: const Text('原精确清单'),
                selected: !results,
                onSelected: busy || !current
                    ? null
                    : (_) {
                        setState(() {
                          results = false;
                          review = null;
                        });
                        unawaited(load(0));
                      },
              ),
              if (widget.task.kind == 'pack_permanent')
                PaperChoiceChip(
                  key: const Key('purge-history-results'),
                  label: const Text('逐项结果'),
                  selected: results,
                  onSelected: busy || !current
                      ? null
                      : (_) {
                          setState(() {
                            results = true;
                            steps = null;
                          });
                          unawaited(load(0));
                        },
                ),
            ],
          ),
          if (results) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final flag in [true, false])
                  PaperChoiceChip(
                    key: Key('purge-history-outcome-$flag'),
                    label: Text(flag ? '未完成' : '全部'),
                    selected: unfinished == flag,
                    onSelected: busy || !current
                        ? null
                        : (_) {
                            setState(() {
                              unfinished = flag;
                              steps = null;
                            });
                            unawaited(load(0));
                          },
                  ),
                DropdownButton<String>(
                  key: const Key('purge-history-kind'),
                  value: kind,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('图片和目录')),
                    DropdownMenuItem(value: 'image', child: Text('只看图片')),
                    DropdownMenuItem(value: 'directory', child: Text('只看目录')),
                  ],
                  onChanged: busy || !current
                      ? null
                      : (value) {
                          setState(() {
                            kind = value!;
                            steps = null;
                          });
                          unawaited(load(0));
                        },
                ),
              ],
            ),
          ],
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('历史记录仅供查看，不会继续执行删除。', style: TextStyle(color: p.olive)),
        ),
      ],
    );
  }

  Widget row(BuildContext context, int index) {
    final p = Paper.of(context);
    if (files) {
      final image = images!.items[index];
      return ListTile(
        key: Key('purge-history-file-${image.id}'),
        contentPadding: EdgeInsets.zero,
        title: Text('${offset + index + 1} · ${image.relativePath}'),
        subtitle: Text('${image.size} 字节'),
      );
    }
    if (results) {
      final step = steps!.items[index];
      final label = step.outcome == 'succeeded'
          ? '已删除'
          : step.outcome == 'retained'
          ? '已保留'
          : step.outcome == 'failed'
          ? '未完成'
          : '尚未完成';
      return ListTile(
        key: Key('purge-history-step-${step.id}'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          '${step.packName} · ${step.kind == 'directory' && step.relativePath == '.' ? '图包根目录' : step.relativePath}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${step.kind == 'image' ? '图片' : '目录'} · $label'),
            if (step.error != null)
              Text(_errorLabel(step.error!), style: TextStyle(color: p.danger)),
          ],
        ),
      );
    }
    final member = review!.members.items[index];
    return ListTile(
      key: Key('purge-history-pack-${member.trashId}'),
      contentPadding: EdgeInsets.zero,
      title: Text(member.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${member.imageCount} 张 · ${member.imageBytes} 字节'),
          Text(member.path),
          if (member.error != null)
            Text(_errorLabel(member.error!), style: TextStyle(color: p.danger)),
        ],
      ),
      trailing: member.digest == null ? null : const Icon(Icons.chevron_right),
      onTap: busy || !current || member.digest == null
          ? null
          : () => Navigator.of(context).push<void>(
              PaperPageRoute(
                builder: (_) => PurgeHistoryPage._files(
                  repository: widget.repository,
                  details: widget.details,
                  task: widget.task,
                  member: member,
                ),
              ),
            ),
    );
  }

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
                    files ? '返回历史清单' : '返回任务详情',
                    Icons.arrow_back,
                    () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(files ? '原图片清单' : '历史明细', style: p.title),
                  ),
                  iconAction(
                    '查询原历史记录',
                    Icons.refresh,
                    busy || !current ? null : () => load(offset),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error.isNotEmpty && current)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  error,
                  key: const Key('purge-history-error'),
                  style: TextStyle(color: p.danger),
                ),
              ),
            Expanded(
              child: !current
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('服务连接或管理数据已变化，请返回后重新打开原任务'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => load(offset),
                      child: ListView.builder(
                        key: PageStorageKey(
                          'purge-history-${widget.task.id}-${widget.member?.trashId ?? 'summary'}',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: length + 2,
                        itemBuilder: (context, index) {
                          if (index == 0) return header(context);
                          if (index <= length) return row(context, index - 1);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (length == 0 && !busy && error.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Text(
                                    results && unfinished
                                        ? '没有未完成的图片或目录'
                                        : '没有原清单记录',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  TextButton(
                                    key: const Key('purge-history-previous'),
                                    onPressed: busy || offset == 0
                                        ? null
                                        : () => load(offset - limit),
                                    child: const Text('上一页'),
                                  ),
                                  Text(
                                    '共 $total 项',
                                    key: const Key('purge-history-total'),
                                  ),
                                  TextButton(
                                    key: const Key('purge-history-next'),
                                    onPressed: busy || offset + length >= total
                                        ? null
                                        : () => load(offset + limit),
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
        ),
      ),
    );
  }

  @override
  void dispose() {
    serial++;
    widget.repository.removeListener(ownerChanged);
    if (widget.ownsDetails) widget.details.dispose();
    super.dispose();
  }
}

String _errorLabel(String code) =>
    const {
      'permission_denied': '当时没有读取或删除权限',
      'read_only_media': '当时的存储为只读',
      'insufficient_space': '当时的存储空间不足',
      'source_missing': '当时未找到原文件',
      'source_replaced': '原文件在核对后被替换',
      'pack_changed': '图包在核对后发生变化',
      'root_unavailable': '当时的媒体目录不可用',
      'root_changed': '当时的目录授权发生变化',
      'path_unsafe': '原路径无法安全访问',
      'file_io_failed': '当时读取或删除文件失败',
      'operation_recovery_required': '当时的操作结果仍待核对',
    }[code] ??
    '原记录错误：$code';
