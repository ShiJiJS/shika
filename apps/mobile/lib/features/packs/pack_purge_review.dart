import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../ui/paper.dart';
import '../../ui/paper_management.dart';
import 'pack_purge_review_session.dart';

Future<PackFileCommand?> showPackPurgeReview(
  BuildContext context,
  LibraryRepository repository,
  Iterable<String> ids, {
  String? selectionId,
}) => paperSheet<PackFileCommand>(
  context,
  PackPurgeReview(
    repository: repository,
    ids: List.of(ids),
    selectionId: selectionId,
  ),
);

class PackPurgeReview extends StatefulWidget {
  const PackPurgeReview({
    super.key,
    required this.repository,
    required this.ids,
    this.selectionId,
  });
  final LibraryRepository repository;
  final List<String> ids;
  final String? selectionId;
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
      final selections = widget.selectionId == null
          ? null
          : PackPurgeSelections(widget.repository.createPackFiles());
      session = PackPurgeReviewSession(
        widget.repository.createPackPurge(),
        widget.ids,
        selectionId: widget.selectionId,
        requestIdentity: selections == null
            ? null
            : (replace) => selections.reviewRequest(
                widget.selectionId!,
                widget.ids,
                replace: replace,
              ),
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
    await Navigator.of(context).push<void>(
      PaperPageRoute(
        builder: (context) => AnimatedBuilder(
          animation: widget.repository,
          builder: (context, _) => Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  PaperManagementHeader(
                    title: '核对图包清单',
                    closeLabel: '返回删除复核',
                    onClose: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: ListView.builder(
                      key: const PageStorageKey('purge-members'),
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                      itemCount: plan.members.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Text(
                              '${plan.members.length} 个图包 · ${plan.imageCount} 张图片',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.7,
                                color: Paper.of(context).ink,
                              ),
                            ),
                          );
                        }
                        final member = plan.members[index - 1];
                        return PaperActionRow(
                          title: member.name,
                          details: [
                            _note(
                              context,
                              '${member.imageCount} 张图片 · 保留 ${member.retainedEntries} 项其他内容',
                            ),
                            Text(
                              member.path,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.7,
                                color: Paper.of(context).catalogMeta,
                              ),
                            ),
                            if (member.error != null)
                              Text(
                                member.error!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.7,
                                  color: Paper.of(context).danger,
                                ),
                              ),
                          ],
                          trailing: member.digest == null
                              ? null
                              : const Icon(Icons.chevron_right, size: 19),
                          onTap: member.digest == null || !s.live
                              ? null
                              : () => Navigator.of(context).push<void>(
                                  PaperPageRoute(
                                    builder: (_) => _PurgeImages(
                                      gateway: s.gateway,
                                      repository: widget.repository,
                                      plan: plan,
                                      member: member,
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
      footer: Wrap(
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
          if (s?.canRenew == true)
            TextButton(
              onPressed: () => s!.load(renew: true),
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
                      setState(() => s.error = packFileFailureMessage(failure));
                    }
                  }
                : null,
            child: const Text('确认永久删除'),
          ),
        ],
      ),
      children: [
        Text(
          '永久删除 ${plan?.members.length ?? widget.ids.length.clamp(0, 1000)} 个图包中的图片？',
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: Paper.of(context).ink,
          ),
        ),
        const SizedBox(height: 12),
        _note(context, '只删除本次核对清单中的图片，其他附件保留。永久删除不可撤销，管理备份也不能找回图片。'),
        const SizedBox(height: 12),
        if (widget.ids.length > 1000)
          _note(
            context,
            '剩余 ${widget.ids.length} 个，本批核对1000个。其余选择已保存，后续批次仍需逐批核对确认。',
          ),
        if (s?.busy == true)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PaperLinearProgressIndicator(
                  value: s!.preparing ? s.processed / s.ids.length : null,
                ),
                const SizedBox(height: 10),
                Text(
                  s.preparing
                      ? '${plan!.status == 'queued' ? '等待服务器核对' : '正在核对图片'} · 已核对 ${s.processed} / ${s.ids.length} 个图包'
                      : '正在准备图片清单…',
                  key: const Key('pack-purge-preparing'),
                ),
                const SizedBox(height: 6),
                _note(context, '数量较多时可能需要较长时间。关闭后可从已保存的删除选择继续核对，不会自动删除。'),
                if (s.waitingMessage.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _note(context, s.waitingMessage),
                ],
              ],
            ),
          ),
        if (plan != null) ...[
          Text(
            s!.preparing
                ? '已核对 ${plan.imageCount} 张图片'
                : '${plan.members.length} 个图包 · ${plan.imageCount} 张图片',
            key: const Key('pack-purge-summary'),
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: Paper.of(context).ink,
            ),
          ),
          _note(
            context,
            '${s.preparing ? '已核对图片' : '图片共'} ${_bytes(plan.imageBytes)}，保留 ${plan.members.fold<int>(0, (n, m) => n + m.retainedEntries)} 项其他内容',
          ),
          PaperActionRow(
            title: '查看图包和图片清单',
            onTap: s.busy || !s.live ? null : members,
            trailing: const Icon(Icons.chevron_right, size: 19),
          ),
          if (plan.operationId != null)
            const Text('此清单已用于原操作，请关闭后在回收站查询原结果。')
          else if (expired)
            Text(
              '清单已过期或失效，请重新准备并确认。',
              style: TextStyle(fontSize: 13, height: 1.7, color: p.danger),
            )
          else if (plan.status == 'failed' || plan.status == 'interrupted')
            Text(
              '清单未能核对完成，请检查目录状态后重新准备。',
              style: TextStyle(fontSize: 13, height: 1.7, color: p.danger),
            )
          else if (!plan.ready && !s.busy)
            const Text('清单仍在准备，可稍后查询原清单。'),
        ],
        if (s != null && !s.live)
          Text(
            '连接或管理数据已变化，请关闭后重新打开。',
            style: TextStyle(fontSize: 13, height: 1.7, color: p.danger),
          ),
        if ((s?.error ?? error).isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              s?.error ?? error,
              style: TextStyle(fontSize: 13, height: 1.7, color: p.danger),
            ),
          ),
        PaperCheckboxListTile(
          key: const Key('pack-purge-confirmation'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          value: s?.checked ?? false,
          onChanged: s?.canConfirm == true
              ? (value) => s!.check(value ?? false)
              : null,
          title: const Text(
            '我确认永久删除本批清单中的图片，无法恢复。',
            style: TextStyle(fontSize: 13, height: 1.8),
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

String _bytes(int count) => count >= 1024 * 1024
    ? '${(count / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(count / 1024).toStringAsFixed(1)} KB';

class _PurgeImages extends StatefulWidget {
  const _PurgeImages({
    required this.gateway,
    required this.repository,
    required this.plan,
    required this.member,
  });
  final PackPurgeGateway gateway;
  final LibraryRepository repository;
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
    widget.repository.addListener(changed);
    unawaited(load(0));
  }

  void changed() {
    if (mounted) setState(() {});
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
      if (mounted && widget.gateway.isCurrent) setState(() => page = value);
    } catch (failure) {
      if (mounted) {
        setState(() => error = packFileFailureMessage(failure));
        if (scroll.hasClients) scroll.jumpTo(0);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  final scroll = ScrollController();

  Future<void> turn(int offset) async {
    await load(offset);
    if (mounted && error.isEmpty && scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context), current = widget.gateway.isCurrent;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PaperManagementHeader(
              title: '核对图片清单',
              closeLabel: '返回图包清单',
              onClose: () => Navigator.pop(context),
            ),
            if (busy) const PaperLinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                itemCount: (page?.items.length ?? 0) + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.member.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontFamily: 'PaperSerif',
                            height: 1.6,
                            color: Paper.of(context).ink,
                          ),
                        ),
                        _note(context, widget.member.path),
                        const SizedBox(height: 12),
                        if (error.isNotEmpty) ...[
                          Text(
                            error,
                            key: const Key('purge-images-error'),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.7,
                              color: p.danger,
                            ),
                          ),
                          TextButton(
                            onPressed: busy || !current
                                ? null
                                : () => load(page?.offset ?? 0),
                            child: const Text('重新读取'),
                          ),
                        ],
                        if (!current)
                          Text(
                            '连接或管理数据已变化，请返回后重新打开。',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.7,
                              color: p.danger,
                            ),
                          ),
                      ],
                    );
                  }
                  if (index == (page?.items.length ?? 0) + 1) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed:
                                busy || !current || (page?.offset ?? 0) == 0
                                ? null
                                : () => turn(page!.offset - 100),
                            child: const Text('上一页'),
                          ),
                          _note(
                            context,
                            '共 ${page?.total ?? widget.member.imageCount} 张',
                          ),
                          TextButton(
                            onPressed:
                                busy ||
                                    !current ||
                                    page == null ||
                                    page!.offset + page!.items.length >=
                                        page!.total
                                ? null
                                : () => turn(page!.offset + 100),
                            child: const Text('下一页'),
                          ),
                        ],
                      ),
                    );
                  }
                  final image = page!.items[index - 1];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: p.line)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          image.relativePath,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: Paper.of(context).ink,
                          ),
                        ),
                        _note(context, _bytes(image.size)),
                      ],
                    ),
                  );
                },
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
    super.dispose();
  }
}

Widget _note(BuildContext context, String text) => Text(
  text,
  style: TextStyle(
    fontSize: 13,
    height: 1.7,
    color: Paper.of(context).catalogMeta,
  ),
);
