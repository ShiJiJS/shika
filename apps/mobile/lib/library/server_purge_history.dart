part of 'server_repository.dart';

class _ServerPurgeHistory implements PurgeHistoryDetails {
  _ServerPurgeHistory(this.catalog, this.task);
  final _ServerMaintenanceTasks catalog;
  final MaintenanceTask task;
  String? planId;
  final members = <PackPurgeMember>{};
  @override
  bool get isCurrent => catalog.isCurrent;

  Future<Json> read(String suffix, Map<String, String> query) async {
    final raw = await catalog.get(
      '${catalog.route(task.id)}/$suffix',
      query: query,
    );
    final plan = catalog.id(raw['plan_id']);
    if (raw['historical'] != true ||
        raw['graph_id'] != task.graphId ||
        raw['task_id'] != task.id ||
        raw['task_kind'] != task.kind ||
        planId != null && plan != planId ||
        task.kind == 'pack_purge_preview' && plan != task.id) {
      throw const LibraryFailure('原历史清单的任务或历史图不一致，请重新打开');
    }
    planId = plan;
    return raw;
  }

  @override
  Future<PurgeHistoryReview> review({int offset = 0, int limit = 24}) async {
    catalog.bounds(offset, limit);
    final raw = await read('purge-review', {
      'offset': '$offset',
      'limit': '$limit',
    });
    if (task.kind == 'pack_permanent' && raw['operation_id'] != task.id) {
      throw const LibraryFailure('原永久删除任务与清单不一致');
    }
    final page = catalog.pageData(
      raw,
      offset,
      limit,
      PackPurgeMember.new,
      (v) => v.trashId,
    );
    if (task.total != null && page.total != task.total) {
      throw const LibraryFailure('原历史图包数量与任务不一致');
    }
    final value = catalog.parse(() => PurgeHistoryReview(raw, page));
    members
      ..clear()
      ..addAll(page.items);
    return value;
  }

  @override
  Future<CatalogPage<PackPurgeImage>> images(
    PackPurgeMember member, {
    int offset = 0,
    int limit = 100,
  }) async {
    catalog.bounds(offset, limit);
    if (!members.contains(member)) throw const LibraryFailure('图包不在已读取的原历史清单内');
    final raw = await read('purge-review/files', {
      'trash_id': member.trashId,
      'offset': '$offset',
      'limit': '$limit',
    });
    if (raw['trash_id'] != member.trashId || raw['pack_id'] != member.packId) {
      throw const LibraryFailure('原历史图片清单的图包不一致');
    }
    final page = catalog.pageData(
      raw,
      offset,
      limit,
      (v) => PackPurgeImage(v, member),
      (v) => v.id,
    );
    if (page.total != member.imageCount) {
      throw const LibraryFailure('原历史图片数量与清单不一致');
    }
    return page;
  }

  @override
  Future<CatalogPage<PackPurgeStep>> steps({
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
    String kind = 'all',
  }) async {
    catalog.bounds(offset, limit);
    if (task.kind != 'pack_permanent' ||
        !['all', 'image', 'directory'].contains(kind)) {
      throw const LibraryFailure('原任务未提供该图片结果范围');
    }
    final raw = await read('purge-pages', {
      'offset': '$offset',
      'limit': '$limit',
      'kind': kind,
      'outcome': unfinished ? 'unfinished' : 'all',
    });
    return catalog.pageData(raw, offset, limit, PackPurgeStep.new, (v) => v.id);
  }

  @override
  void dispose() => catalog.dispose();
}
