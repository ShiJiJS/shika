import 'dart:async';

import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';

import 'pack_trash_fixture.dart';

typedef Json = Map<String, dynamic>;
String get purgeHash => 'a' * 64;
Json purgePlanJson(
  List<String> ids, {
  String id = 'plan',
  bool expired = false,
}) => {
  'id': id,
  'kind': 'pack_purge_preview',
  'status': 'completed',
  'phase': 'ready',
  'error': null,
  'digest': purgeHash,
  'historical': false,
  'operation_id': null,
  'server_time': 1000.0,
  'expires_at': expired ? 999.0 : 1900.0,
  'ready': !expired,
  'result': {
    'total': ids.length,
    'processed': ids.length,
    'succeeded': ids.length,
    'failed': 0,
    'image_count': ids.length * 3,
    'image_bytes': ids.length * 300,
  },
  'items': [
    for (final id in ids)
      {
        'trash_id': id,
        'pack_id': 'pack-$id',
        'name': '海边散步图包 $id',
        'path': '/packs/$id',
        'digest': purgeHash,
        'error': null,
        'image_count': 3,
        'image_bytes': 300,
        'retained_entries': 1,
      },
  ],
};
Json purgeTaskJson(
  List<String> ids, {
  String id = 'purge-op',
  bool attention = false,
  bool failed = false,
}) => {
  'id': id,
  'kind': 'pack_permanent',
  'status': failed || attention ? 'failed' : 'completed',
  'error': failed || attention ? 'fixture_failure' : null,
  'result': {
    'operation_id': id,
    'total': ids.length,
    'processed': ids.length,
    'succeeded': failed || attention ? 0 : ids.length,
    'failed': failed || attention ? ids.length : 0,
    'partial': failed || attention,
    'pages_total': ids.length * 3,
    'pages_deleted': (failed || attention ? 1 : 3) * ids.length,
    'pages_pending_reconciliation': attention ? ids.length : 0,
    'needs_attention': attention,
    'items': [
      for (final id in ids)
        {
          'requested_id': id,
          'trash_id': id,
          'pack_id': 'pack-$id',
          'outcome': failed || attention ? 'failed' : 'succeeded',
          'phase': attention
              ? 'needs_attention'
              : failed
              ? 'prepared'
              : 'committed',
          'error': failed || attention ? 'fixture_failure' : null,
          'pages_total': 3,
          'pages_deleted': failed || attention ? 1 : 3,
        },
    ],
    'reading_transition': null,
    'reading_restored': false,
    'undo_expires_at': null,
  },
};

class PurgeLibrary extends TrashLibrary {
  PurgeLibrary({super.count});
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    'pack_purge_preview',
    'pack_permanent_delete',
  ]);
  final preparations = <List<String>>[];
  final physicalPosts = <Json>[];
  final prepared = <String, PackPurgePlan>{};
  bool expired = false, losePreparation = false;
  Completer<void>? preparationGate;
  @override
  PackPurgeGateway createPackPurge() => PurgeGateway(this);
  @override
  PackFiles createPackFiles() {
    final identity = owner, fallback = super.createPackFiles();
    return PackFiles(
      journal: journal,
      scope: 'trash-fixture',
      isCurrent: () => identical(identity, owner),
      call: (method, path, {body}) async {
        if (method == 'GET' && receipts.containsKey(path.split('/').last)) {
          return receipts[path.split('/').last]!;
        }
        if (method != 'POST' || !path.endsWith('/permanent')) {
          return fallback.call(method, path, body: body);
        }
        physicalPosts.add(body!);
        final ids = preparations.last;
        final value = purgeTaskJson(ids);
        for (final id in ids) {
          records.remove(id);
        }
        receipts[body['request_id']] = value;
        receipts['purge-op'] = value;
        if (loseAfter) {
          loseAfter = false;
          throw const ApiFailure('响应丢失', code: 'reply_lost', status: 503);
        }
        return value;
      },
    );
  }
}

class PurgeGateway implements PackPurgeGateway {
  PurgeGateway(this.repo) : owner = repo.owner;
  final PurgeLibrary repo;
  final Object owner;
  bool disposed = false;
  int receiptReads = 0;
  @override
  bool get isCurrent => !disposed && identical(owner, repo.owner);
  @override
  Future<PackPurgePlan> prepare(String requestId, List<String> trashIds) async {
    repo.preparations.add(List.of(trashIds));
    if (repo.preparationGate != null) await repo.preparationGate!.future;
    final value = PackPurgePlan(purgePlanJson(trashIds, expired: repo.expired));
    repo.prepared[requestId] = value;
    if (repo.losePreparation) {
      repo.losePreparation = false;
      throw const ApiFailure('响应丢失', code: 'reply_lost', status: 503);
    }
    return value;
  }

  @override
  Future<PackPurgePlan?> receipt(String requestId) async {
    receiptReads++;
    return repo.prepared[requestId];
  }

  @override
  Future<PackPurgePlan> plan(String id) async =>
      repo.prepared.values.firstWhere((p) => p.id == id);
  @override
  Future<CatalogPage<PackPurgeImage>> images(
    PackPurgePlan plan,
    PackPurgeMember member, {
    int offset = 0,
    int limit = 100,
  }) async => CatalogPage(
    items: [
      for (var i = offset; i < 3 && i < offset + limit; i++)
        PackPurgeImage({
          'id': 'page-$i',
          'path': '${member.path}/$i.jpg',
          'relative_path': '$i.jpg',
          'size': 100,
          'sha256': purgeHash,
          'signature': [
            '37',
            '33837',
            100,
            '1792884555250765506',
            '1792884555250765506',
          ],
        }, member),
    ],
    total: 3,
    offset: offset,
    limit: limit,
  );
  @override
  Future<CatalogPage<PackPurgeStep>> steps(
    String operationId, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  }) async =>
      CatalogPage(items: const [], total: 0, offset: offset, limit: limit);
  @override
  void dispose() {
    disposed = true;
  }
}
