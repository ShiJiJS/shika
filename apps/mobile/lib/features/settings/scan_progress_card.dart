import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../ui/paper.dart';

String scanActivityLabel(
  LibraryPreparation state,
  List<MediaRoot> roots, {
  bool precise = false,
}) {
  if (state.syncError != null) return state.syncError!;
  if (state.scanning) {
    final kinds = [
      for (final kind in MediaKind.values)
        if (roots.any(
          (r) =>
              r.kind == kind &&
              r.enabled &&
              (state.rootProgress(r.id).active ||
                  state.rootProgress(r.id).queued),
        ))
          kind == MediaKind.pack ? '图包' : '视频',
    ];
    return kinds.isEmpty ? state.label : '${kinds.join('、')}目录扫描中';
  }
  if ((!precise && state.legacyNeedsAttention) ||
      roots.any((r) => r.enabled && state.rootProgress(r.id).needsAttention)) {
    return '有目录需要检查';
  }
  if (roots.any((r) => r.enabled && !state.rootProgress(r.id).known)) {
    return '部分目录暂无扫描明细';
  }
  return '目录扫描记录';
}

/// The existing scan surface, grouped by configured source rather than images.
class ScanProgressCard extends StatelessWidget {
  const ScanProgressCard({
    super.key,
    required this.state,
    required this.roots,
    required this.precise,
    required this.scoped,
    required this.busy,
    required this.onScanAll,
    required this.onScanRoot,
    this.showAll = true,
  });
  final LibraryPreparation state;
  final List<MediaRoot> roots;
  final bool precise, scoped, busy, showAll;
  final VoidCallback onScanAll;
  final ValueChanged<String> onScanRoot;

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.soft.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('扫描进度', style: p.title.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          Text(
            scanActivityLabel(state, roots, precise: precise),
            key: const Key('preparation-progress'),
            style: TextStyle(fontSize: 13, color: p.olive),
          ),
          if (state.syncError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '下方保留上次同步的记录。',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ),
          for (final kind in MediaKind.values) ...[
            const SizedBox(height: 18),
            Text(
              kind == MediaKind.pack ? '图包目录' : '视频目录',
              key: Key('scan-group-${kind.name}'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
            if (!roots.any((r) => r.kind == kind))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '尚未接入${kind == MediaKind.pack ? '图包' : '视频'}目录',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ),
            if (!precise &&
                kind == MediaKind.video &&
                roots.any((r) => r.kind == kind))
              ..._legacyVideoSummary(context),
            if (!precise &&
                kind == MediaKind.pack &&
                roots.any((r) => r.kind == kind))
              ..._legacyPackSummary(context),
            for (final root in roots.where((r) => r.kind == kind))
              _root(context, root),
          ],
          const SizedBox(height: 16),
          Text(
            '扫描会在后台继续，离开此页也不会停止。',
            style: TextStyle(fontSize: 12, height: 1.6, color: p.muted),
          ),
          const SizedBox(height: 8),
          if (showAll)
            OutlinedButton(
              key: const Key('scan-all'),
              onPressed:
                  busy || state.syncError != null || (!scoped && state.scanning)
                  ? null
                  : onScanAll,
              child: const Text('全部扫描'),
            ),
        ],
      ),
    );
  }

  List<Widget> _legacyPackSummary(BuildContext context) {
    final counts = state.mediaProgress(MediaKind.pack)['counts'];
    final progress = counts is Map ? counts['progress'] : null;
    final images = progress is Map ? progress['processed'] : null;
    final packs = progress is Map ? progress['packs_processed'] : null;
    int count(String key) {
      final value = counts is Map ? counts[key] : null;
      return value is num && value.isFinite && value > 0 ? value.toInt() : 0;
    }

    return [
      if (images is num &&
          packs is num &&
          images.isFinite &&
          packs.isFinite &&
          images >= 0 &&
          packs >= 0)
        _overviewLine(
          context,
          '本轮共核对 ${images.toInt()} 张图片 · 处理 ${packs.toInt()} 个图包',
        ),
      if (count('failed_pages') > 0)
        _overviewLine(
          context,
          '本轮 ${count('failed_pages')} 张图片无法读取',
          problem: true,
        ),
      if (count('failed_packs') > 0)
        _overviewLine(
          context,
          '本轮 ${count('failed_packs')} 个图包无法读取',
          problem: true,
        ),
      if (count('deferred') > 0)
        _overviewLine(context, '本轮 ${count('deferred')} 个图包的文件仍在变化'),
      if (count('thumbnail_failed') > 0)
        _overviewLine(
          context,
          '本轮 ${count('thumbnail_failed')} 个缩略图待补充（不影响入库）',
        ),
    ];
  }

  List<Widget> _legacyVideoSummary(BuildContext context) => [
    if (state.failed > 0)
      _overviewLine(context, '本轮 ${state.failed} 个视频信息读取失败', problem: true),
    if (state.failureDetail.isNotEmpty)
      _overviewLine(context, state.failureDetail, problem: true),
    if (state.thumbnailFailed > 0)
      _overviewLine(context, '本轮 ${state.thumbnailFailed} 个缩略图待补充（不影响入库）'),
    if (state.deferred > 0)
      _overviewLine(context, '本轮 ${state.deferred} 个视频的文件仍在变化'),
  ];

  Widget _overviewLine(
    BuildContext context,
    String text, {
    bool problem = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.6,
        color: problem ? Paper.of(context).danger : Paper.of(context).muted,
      ),
    ),
  );

  Widget _root(BuildContext context, MediaRoot root) {
    final p = Paper.of(context), facts = state.rootProgress(root.id);
    final duplicateName = roots.where((r) => r.name == root.name).length > 1;
    final problem =
        root.enabled &&
        const {
          'partial',
          'unavailable',
          'failed',
          'interrupted',
        }.contains(facts.status);
    final lines = _numbers(root, facts);
    final errors = [
      if (root.kind == MediaKind.video && facts.count('failed') > 0)
        '${facts.count('failed')} 个视频信息读取失败',
      if (root.kind == MediaKind.pack && facts.pageErrors > 0)
        '${facts.pageErrors} 张图片无法读取',
      if (root.kind == MediaKind.pack && facts.count('failed_packs') > 0)
        '${facts.count('failed_packs')} 个图包无法读取',
      if (root.kind == MediaKind.pack && facts.unreadablePacks > 0)
        '${facts.unreadablePacks} 个图包没有可阅读的图片',
    ];
    final notes = [
      if (facts.count('deferred') > 0)
        '${facts.count('deferred')} 个${root.kind == MediaKind.pack ? '图包' : '视频'}的文件仍在变化',
      if (facts.count('protected_packs') > 0)
        '跳过 ${facts.count('protected_packs')} 个图包',
      if (facts.count('thumbnail_failed') > 0)
        '${facts.count('thumbnail_failed')} 个缩略图待补充（不影响入库）',
    ];
    final completed = facts.lastCompletedAt;
    final finished = facts.finishedAt;
    final owners = roots.where((r) => r.id == facts.scan['owner_root_id']);
    return Container(
      key: Key('scan-root-${root.id}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(root.name, style: p.title.copyWith(fontSize: 15, height: 1.6)),
          if (duplicateName)
            Text(
              root.path,
              style: TextStyle(fontSize: 12, height: 1.6, color: p.muted),
            ),
          Text(
            facts.status == 'covered' && owners.isNotEmpty
                ? '随“${owners.first.name}”扫描'
                : scanRootLabel(root, facts),
            key: Key('scan-root-phase-${root.id}'),
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: problem ? p.danger : p.olive,
            ),
          ),
          for (final line in lines)
            Text(
              line,
              style: TextStyle(fontSize: 12, height: 1.7, color: p.muted),
            ),
          if (facts.active &&
              facts.status != 'queued' &&
              state.syncError == null &&
              !MediaQuery.disableAnimationsOf(context))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const PaperLinearProgressIndicator(minHeight: 3),
            ),
          if (facts.queued && facts.known)
            Text(
              '下一次扫描已排队',
              style: TextStyle(fontSize: 12, height: 1.7, color: p.olive),
            ),
          if (errors.isNotEmpty)
            Text(
              errors.join('\n'),
              style: TextStyle(fontSize: 12, height: 1.7, color: p.danger),
            ),
          if (notes.isNotEmpty)
            Text(
              notes.join('\n'),
              style: TextStyle(fontSize: 12, height: 1.7, color: p.muted),
            ),
          if (facts.error != null)
            Text(
              _reason(facts.error!),
              style: TextStyle(fontSize: 12, height: 1.7, color: p.muted),
            ),
          if (completed != null)
            Text(
              '上次完成 ${_date(completed)}',
              style: TextStyle(fontSize: 12, height: 1.7, color: p.muted),
            )
          else if (finished != null)
            Text(
              '记录于 ${_date(finished)}',
              style: TextStyle(fontSize: 12, height: 1.7, color: p.muted),
            ),
          if (scoped && root.enabled && facts.status != 'covered')
            TextButton(
              key: Key('scan-root-action-${root.id}'),
              onPressed:
                  busy ||
                      state.syncError != null ||
                      facts.active ||
                      facts.queued
                  ? null
                  : () => onScanRoot(root.id),
              child: Text(
                facts.queued || facts.status == 'queued'
                    ? '已排队'
                    : facts.active
                    ? '正在扫描'
                    : '扫描此目录',
              ),
            ),
        ],
      ),
    );
  }

  List<String> _numbers(MediaRoot root, RootScanProgress facts) {
    if (!root.enabled ||
        !facts.known ||
        const {'queued', 'disabled', 'covered'}.contains(facts.status)) {
      return const [];
    }
    if (facts.status == 'unavailable' &&
        (facts.processed ?? facts.legacyProcessed ?? 0) == 0 &&
        (facts.packsProcessed ?? 0) == 0) {
      return const [];
    }
    if (root.kind == MediaKind.video) {
      final found = facts.discovered ?? facts.legacyDiscovered;
      final checked = facts.processed ?? facts.legacyProcessed;
      if (facts.status == 'discovering') {
        return [if (found != null) '已发现 $found 个视频'];
      }
      if (checked == null) return const ['视频数量未提供'];
      final known =
          facts.totalKnown || (!precise && facts.status == 'completed');
      if (known && found == 0 && checked == 0) return const ['未发现视频'];
      return [
        known && found != null && found >= checked
            ? '已核对 $checked / $found 个视频'
            : '已核对 $checked 个视频',
        if (!known && found != null && found >= checked) '已发现 $found 个视频',
      ];
    }
    final found = facts.packsDiscovered ?? facts.legacyDiscovered;
    final checked = facts.packsProcessed ?? facts.legacyProcessed;
    final known =
        facts.packTotalKnown || (!precise && facts.status == 'completed');
    if (known && found == 0 && checked == 0) return const ['未发现图包'];
    if (facts.status == 'discovering' && checked == 0) {
      return [if (found != null && (precise || found > 0)) '已发现 $found 个图包'];
    }
    return [
      if (checked != null)
        known && found != null && found >= checked
            ? '已处理 $checked / $found 个图包'
            : '已处理 $checked 个图包',
      if (precise && facts.processed != null)
        facts.processed == 0 && facts.discovered == 0
            ? facts.totalKnown
                  ? '未发现可检查的图片'
                  : '图片数量暂未统计'
            : facts.totalKnown &&
                  facts.discovered != null &&
                  facts.discovered! >= facts.processed!
            ? '已核对 ${facts.processed} / ${facts.discovered} 张图片'
            : '已核对 ${facts.processed} 张图片${facts.discovered == null ? '' : ' · 已发现 ${facts.discovered} 张'}'
      else
        '此服务未提供该目录的图片进度',
    ];
  }
}

String scanRootLabel(MediaRoot root, RootScanProgress facts) {
  if (!root.enabled) return '已停用';
  if (!facts.known) {
    if (facts.queued) return '排队中';
    if ((facts.available ?? root.available) == false &&
        (facts.error != null ||
            root.error != null ||
            facts.lastCompletedAt != null)) {
      return '目录暂不可用';
    }
    return '暂无扫描进度记录';
  }
  if (facts.status == 'discovering' &&
      root.kind == MediaKind.pack &&
      !facts.hasImageProgress &&
      (facts.legacyProcessed ?? 0) > 0) {
    return '正在读取图包';
  }
  return switch (facts.status) {
    'queued' => '排队中',
    'discovering' => root.kind == MediaKind.pack ? '正在查找图包' : '正在查找视频',
    'processing_media' => root.kind == MediaKind.pack ? '正在读取图片' : '正在读取视频信息',
    'waiting_for_stable_files' => '等待文件写入完成',
    'reconciling' => '核对已有记录',
    'completed' => '扫描完成',
    'partial' => '部分内容未能读取',
    'deferred' => '部分文件仍在变化',
    'unavailable' => '目录暂不可用',
    'disabled' => '已停用',
    'covered' => '由外层目录扫描',
    'interrupted' => '扫描已中断',
    'failed' => '扫描失败',
    _ => '进度信息暂不可用',
  };
}

String _date(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _reason(String code) => switch (code) {
  'root_unmapped' => '此目录未连接，请检查媒体目录设置。',
  'root_unavailable' => '目录无法访问，请检查挂载或连接。',
  'pack_scan_incomplete' => '部分图包读取失败，原有记录保留。',
  'files_changing' => '文件仍在变化，稍后可重新扫描。',
  'service_restarted' || 'scan_interrupted' => '扫描中断，可重新扫描此目录。',
  'scan_failed' => '未完成本次扫描，可以重试。',
  _ => '目录读取遇到问题，请检查连接后重试。',
};
