import 'dart:async';

import 'package:shika/library/repository.dart';
import 'package:shika/library/models.dart';

import 'maintenance_fixture.dart';

const purgeHistoryGraph = '11111111-1111-4111-8111-111111111111';
const purgeHistoryOtherGraph = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> historyTaskJson({String kind = 'pack_permanent'}) => {
  ...taskSummary(
    kind == 'pack_permanent' ? 'purge-old' : 'preview-old',
    kind: kind,
    state: 'historical',
  ),
  'graph_id': purgeHistoryGraph,
  'status': kind == 'pack_permanent' ? 'failed' : 'completed',
  'total': 27,
  'processed': 27,
  'succeeded': 26,
  'failed': 1,
  'pages_total': kind == 'pack_permanent' ? 153 : null,
  'pages_deleted': kind == 'pack_permanent' ? 152 : null,
  'pages_pending': kind == 'pack_permanent' ? 1 : null,
};
Map<String, dynamic> historyBinding(String id) => {
  'historical': true,
  'graph_id': purgeHistoryGraph,
  'task_id': id,
  'task_kind': id == 'purge-old' ? 'pack_permanent' : 'pack_purge_preview',
  'plan_id': 'preview-old',
};
Map<String, dynamic> historyMember(int i) => {
  'trash_id': 'trash-$i',
  'pack_id': 'pack-$i',
  'name': '原图包 ${i.toString().padLeft(2, '0')}',
  'path': '/media/packs/原图包$i',
  'digest': 'a' * 64,
  'error': null,
  'image_count': i == 0 ? 127 : 1,
  'image_bytes': (i == 0 ? 127 : 1) * 100,
  'retained_entries': 1,
};
Map<String, dynamic> historyReviewJson(
  String id, {
  int offset = 0,
  int limit = 24,
}) => {
  ...historyBinding(id),
  'ready': false,
  'operation_id': 'purge-old',
  'status': 'completed',
  'digest': 'b' * 64,
  'expires_at': 1792887000.0,
  'image_count': 153,
  'image_bytes': 15300,
  'retained_entries': 27,
  'total': 27,
  'offset': offset,
  'limit': limit,
  'items': [
    for (var i = offset; i < 27 && i < offset + limit; i++) historyMember(i),
  ],
};
Map<String, dynamic> historyImagesJson(
  String id,
  PackPurgeMember member, {
  int offset = 0,
  int limit = 100,
}) => {
  ...historyBinding(id),
  'trash_id': member.trashId,
  'pack_id': member.packId,
  'total': member.imageCount,
  'offset': offset,
  'limit': limit,
  'items': [
    for (var i = offset; i < member.imageCount && i < offset + limit; i++)
      {
        'id': '${member.packId}-image-$i',
        'relative_path': '${(i + 1).toString().padLeft(4, '0')}.png',
        'path': '${member.path}/${(i + 1).toString().padLeft(4, '0')}.png',
        'size': 100,
        'sha256': 'c' * 64,
        'signature': [1, 2, 100, 4, 5],
      },
  ],
};
Map<String, dynamic> historyStepsJson(
  String id, {
  int offset = 0,
  int limit = 24,
  bool unfinished = true,
  String kind = 'all',
}) {
  final items =
      [
            for (var i = 0; i < 180; i++)
              {
                'id': 'step-$i',
                'parent_id':
                    'parent-${i < 127
                        ? 0
                        : i < 153
                        ? i - 126
                        : i - 153}',
                'pack_id':
                    'pack-${i < 127
                        ? 0
                        : i < 153
                        ? i - 126
                        : i - 153}',
                'pack_name':
                    '原图包 ${i < 127
                        ? 0
                        : i < 153
                        ? i - 126
                        : i - 153}',
                'kind': i < 153 ? 'image' : 'directory',
                'page_id': i < 153 ? 'image-$i' : null,
                'relative_path': i < 153
                    ? '${(i + 1).toString().padLeft(4, '0')}.png'
                    : '.',
                'phase': i == 100
                    ? 'prepared'
                    : i < 153
                    ? 'committed'
                    : 'retained',
                'outcome': i == 100
                    ? 'failed'
                    : i < 153
                    ? 'succeeded'
                    : 'retained',
                'error': i == 100 ? 'permission_denied' : null,
              },
          ]
          .where(
            (v) =>
                (kind == 'all' || v['kind'] == kind) &&
                (!unfinished || v['outcome'] == 'failed'),
          )
          .toList();
  return {
    ...historyBinding(id),
    'items': items.skip(offset).take(limit).toList(),
    'total': items.length,
    'offset': offset,
    'limit': limit,
  };
}

class FakePurgeHistory implements PurgeHistoryDetails {
  FakePurgeHistory(this.repo, this.task);
  final TasksLibrary repo;
  final MaintenanceTask task;
  final owner = Object();
  bool disposed = false, active = true, fail = false;
  Completer<void>? gate;
  final requests = <String>[];
  @override
  bool get isCurrent => active && !disposed;
  @override
  Future<PurgeHistoryReview> review({int offset = 0, int limit = 24}) async {
    requests.add('review:$offset');
    if (gate != null) await gate!.future;
    if (fail) throw const LibraryFailure('原清单暂时无法读取');
    final raw = historyReviewJson(task.id, offset: offset, limit: limit);
    return PurgeHistoryReview(
      raw,
      CatalogPage(
        items: (raw['items'] as List).map(
          (v) => PackPurgeMember(Map<String, dynamic>.from(v)),
        ),
        total: 27,
        offset: offset,
        limit: limit,
      ),
    );
  }

  @override
  Future<CatalogPage<PackPurgeImage>> images(
    PackPurgeMember member, {
    int offset = 0,
    int limit = 100,
  }) async {
    requests.add('images:${member.trashId}:$offset');
    if (fail) throw const LibraryFailure('原图片暂时无法读取');
    final raw = historyImagesJson(
      task.id,
      member,
      offset: offset,
      limit: limit,
    );
    return CatalogPage(
      items: (raw['items'] as List).map(
        (v) => PackPurgeImage(Map<String, dynamic>.from(v), member),
      ),
      total: member.imageCount,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<CatalogPage<PackPurgeStep>> steps({
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
    String kind = 'all',
  }) async {
    requests.add('steps:$offset:$unfinished:$kind');
    if (fail) throw const LibraryFailure('原结果暂时无法读取');
    final raw = historyStepsJson(
      task.id,
      offset: offset,
      limit: limit,
      unfinished: unfinished,
      kind: kind,
    );
    return CatalogPage(
      items: (raw['items'] as List).map(
        (v) => PackPurgeStep(Map<String, dynamic>.from(v)),
      ),
      total: raw['total'] as int,
      offset: offset,
      limit: limit,
    );
  }

  @override
  void dispose() => disposed = true;
}
