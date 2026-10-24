import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../ui/paper.dart';
import 'pack_purge_review_session.dart';

Future<PackFileCommand?> showPackPurgeReview(
  BuildContext context,
  LibraryRepository repository,
  Iterable<String> ids,
) => paperSheet<PackFileCommand>(
  context,
  PackPurgeReview(repository: repository, ids: List.of(ids)),
);

class PackPurgeReview extends StatefulWidget {
  const PackPurgeReview({
    super.key,
    required this.repository,
    required this.ids,
  });
  final LibraryRepository repository;
  final List<String> ids;
  @override
  State<PackPurgeReview> createState() => _PackPurgeReviewState();
}

class _PackPurgeReviewState extends State<PackPurgeReview> {
  PackPurgeReviewSession? session;
  String error = '';
  @override
  void initState() {
    super.initState();
    try {
      session = PackPurgeReviewSession(
        widget.repository.createPackPurge(),
        widget.ids,
      )..addListener(changed);
      unawaited(session!.load(submit: true));
    } catch (failure) {
      error = packFileFailureMessage(failure);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> members() async {
    final s = session!, plan = session!.plan!;
    await paperSheet<void>(
      context,
      SheetFrame(
        title: '核对图包清单',
        children: [
          Text('${plan.members.length} 个图包 · ${plan.imageCount} 张图片'),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .46,
            child: ListView.builder(
              itemCount: plan.members.length,
              itemBuilder: (context, index) {
                final member = plan.members[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(member.name),
                  subtitle: Text('${member.imageCount} 张 · ${member.path}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: member.digest == null
                      ? null
                      : () => paperSheet<void>(
                          context,
                          _PurgeImages(
                            gateway: s.gateway,
                            plan: plan,
                            member: member,
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = session, plan = s?.plan, p = Paper.of(context);
    final expired =
        plan != null && !plan.canConfirm && plan.status == 'completed';
    return SheetFrame(
      title: '永久删除图包',
      children: [
        const Text('只删除本次核对清单中的图片，其他附件保留。永久删除不可撤销，管理备份也不能找回图片。'),
        const SizedBox(height: 12),
        if (widget.ids.length > 1000)
          Text('共选 ${widget.ids.length} 个，本批核对1000个。其余图包保持选择，完成后可继续下一批。'),
        if (s?.busy == true)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (plan != null) ...[
          Text(
            '${plan.members.length} 个图包 · ${plan.imageCount} 张图片',
            key: const Key('pack-purge-summary'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            '图片共 ${_bytes(plan.imageBytes)}，保留 ${plan.members.fold<int>(0, (n, m) => n + m.retainedEntries)} 项其他内容',
          ),
          TextButton(
            onPressed: s!.busy || !s.live ? null : members,
            child: const Text('查看图包和图片清单'),
          ),
          if (plan.operationId != null)
            const Text('此清单已用于原操作，请关闭后在回收站查询原结果。')
          else if (expired)
            Text('清单已过期或失效，请重新准备并确认。', style: TextStyle(color: p.danger))
          else if (plan.status == 'failed' || plan.status == 'interrupted')
            Text('清单未能核对完成，请检查目录状态后重新准备。', style: TextStyle(color: p.danger))
          else if (!plan.ready && !s.busy)
            const Text('清单仍在准备，可稍后查询原清单。'),
        ],
        if (s != null && !s.live)
          Text('连接或管理数据已变化，请关闭后重新打开。', style: TextStyle(color: p.danger)),
        if ((s?.error ?? error).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(s?.error ?? error, style: TextStyle(color: p.danger)),
          ),
        CheckboxListTile(
          key: const Key('pack-purge-confirmation'),
          contentPadding: EdgeInsets.zero,
          value: s?.checked ?? false,
          onChanged: s?.canConfirm == true
              ? (value) => s!.check(value ?? false)
              : null,
          title: const Text('我确认永久删除本批清单中的图片，无法恢复。'),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            if (s != null && !s.busy && s.live && !s.canConfirm)
              TextButton(onPressed: () => s.load(), child: const Text('查询原清单')),
            if (s != null && !s.busy && s.live && !s.canConfirm)
              TextButton(
                onPressed: () => s.load(renew: true),
                child: const Text('重新准备'),
              ),
            FilledButton(
              key: const Key('pack-purge-submit'),
              style: FilledButton.styleFrom(
                backgroundColor: p.danger,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: s?.canConfirm == true && s!.checked
                  ? () {
                      try {
                        Navigator.pop(context, s.authorize());
                      } catch (failure) {
                        setState(
                          () => s.error = packFileFailureMessage(failure),
                        );
                      }
                    }
                  : null,
              child: const Text('确认永久删除'),
            ),
          ],
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

String _bytes(int count) => count >= 1024 * 1024
    ? '${(count / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(count / 1024).toStringAsFixed(1)} KB';

class _PurgeImages extends StatefulWidget {
  const _PurgeImages({
    required this.gateway,
    required this.plan,
    required this.member,
  });
  final PackPurgeGateway gateway;
  final PackPurgePlan plan;
  final PackPurgeMember member;
  @override
  State<_PurgeImages> createState() => _PurgeImagesState();
}

class _PurgeImagesState extends State<_PurgeImages> {
  CatalogPage<PackPurgeImage>? page;
  bool busy = true;
  String error = '';
  @override
  void initState() {
    super.initState();
    unawaited(load(0));
  }

  Future<void> load(int offset) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final value = await widget.gateway.images(
        widget.plan,
        widget.member,
        offset: offset,
      );
      if (mounted) setState(() => page = value);
    } catch (failure) {
      if (mounted) setState(() => error = packFileFailureMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: '核对图片清单',
    children: [
      Text(widget.member.name),
      if (busy) const LinearProgressIndicator(),
      if (error.isNotEmpty) ...[
        Text(error),
        TextButton(
          onPressed: () => load(page?.offset ?? 0),
          child: const Text('重新读取'),
        ),
      ],
      SizedBox(
        height: MediaQuery.sizeOf(context).height * .46,
        child: ListView.builder(
          itemCount: page?.items.length ?? 0,
          itemBuilder: (_, i) {
            final image = page!.items[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(image.relativePath),
              subtitle: Text(_bytes(image.size)),
            );
          },
        ),
      ),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: busy || (page?.offset ?? 0) == 0
                ? null
                : () => load(page!.offset - 100),
            child: const Text('上一页'),
          ),
          Text('共 ${page?.total ?? widget.member.imageCount} 张'),
          TextButton(
            onPressed:
                busy ||
                    page == null ||
                    page!.offset + page!.items.length >= page!.total
                ? null
                : () => load(page!.offset + 100),
            child: const Text('下一页'),
          ),
        ],
      ),
    ],
  );
}
