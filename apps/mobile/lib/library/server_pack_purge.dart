part of 'server_repository.dart';

class _ServerPackPurge implements PackPurgeGateway {
  _ServerPackPurge(this.owner, this.target, this.generation, this.epoch);
  final ServerLibraryRepository owner;
  final ServerApi target;
  final int generation, epoch;
  final scope = RequestScope();
  bool disposed = false;
  @override
  bool get isCurrent =>
      !disposed &&
      !owner._disposed &&
      generation == owner._generation &&
      epoch == owner._readerEpoch &&
      identical(target, owner.connectionIdentity);
  void check() {
    if (!isCurrent) throw const RequestCancelled();
    owner.ensureNotRestoring();
  }

  Future<Json> read(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
  }) async {
    check();
    final result = await owner.call(
      method,
      path,
      body: body,
      query: query,
      using: target,
      cancel: scope,
    );
    check();
    return result;
  }

  String encoded(String value) {
    if (value.isEmpty || value.length > 128) {
      throw const LibraryFailure('图包清单标识不完整');
    }
    return Uri.encodeComponent(value);
  }

  PackPurgePlan parse(Json raw) {
    try {
      return PackPurgePlan(raw);
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('永久删除清单不完整，请重新读取');
    }
  }

  @override
  Future<PackPurgePlan> prepare(String requestId, List<String> trashIds) async {
    encoded(requestId);
    if (trashIds.isEmpty ||
        trashIds.length > 1000 ||
        trashIds.toSet().length != trashIds.length) {
      throw const LibraryFailure('每次请核对1至1000个图包');
    }
    for (final id in trashIds) {
      encoded(id);
    }
    final plan = parse(
      await read(
        'POST',
        '/api/v1/pack-purge-plans',
        body: {'request_id': requestId, 'trash_ids': trashIds},
      ),
    );
    plan.bind(trashIds);
    return plan;
  }

  @override
  Future<PackPurgePlan?> receipt(String requestId) async {
    try {
      return parse(
        await read('GET', '/api/v1/pack-purge-requests/${encoded(requestId)}'),
      );
    } on ApiFailure catch (error) {
      check();
      if (error.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<PackPurgePlan> plan(String id) async {
    final result = parse(
      await read('GET', '/api/v1/pack-purge-plans/${encoded(id)}'),
    );
    if (result.id != id) throw const LibraryFailure('图片清单身份已变化');
    return result;
  }

  CatalogPage<T> page<T>(
    Json raw,
    int offset,
    int limit,
    T Function(Json) parse,
    String Function(T) id,
  ) {
    try {
      final total = raw['total'];
      final items = rows(raw).map(parse).toList();
      if (total is! int ||
          total < 0 ||
          raw['offset'] != offset ||
          raw['limit'] != limit ||
          items.length != min(limit, max(0, total - offset)) ||
          items.map(id).toSet().length != items.length) {
        throw const FormatException();
      }
      return CatalogPage(
        items: items,
        total: total,
        offset: offset,
        limit: limit,
      );
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('图片清单分页不完整，请重新读取');
    }
  }

  void bounds(int offset, int limit) {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw const LibraryFailure('图片清单分页范围无效');
    }
  }

  @override
  Future<CatalogPage<PackPurgeImage>> images(
    PackPurgePlan plan,
    PackPurgeMember member, {
    int offset = 0,
    int limit = 100,
  }) async {
    bounds(offset, limit);
    if (!plan.members.contains(member)) {
      throw const LibraryFailure('图包不在本次确认清单内');
    }
    final result = page(
      await read(
        'GET',
        '/api/v1/pack-purge-plans/${encoded(plan.id)}/files',
        query: {
          'trash_id': member.trashId,
          'offset': '$offset',
          'limit': '$limit',
        },
      ),
      offset,
      limit,
      (raw) => PackPurgeImage(raw, member),
      (value) => value.id,
    );
    if (result.total != member.imageCount) {
      throw const LibraryFailure('图片数量与确认清单不同');
    }
    return result;
  }

  @override
  Future<CatalogPage<PackPurgeStep>> steps(
    String operationId, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  }) async {
    bounds(offset, limit);
    return page(
      await read(
        'GET',
        '/api/v1/pack-operations/${encoded(operationId)}/pages',
        query: {
          'offset': '$offset',
          'limit': '$limit',
          'outcome': unfinished ? 'unfinished' : 'all',
        },
      ),
      offset,
      limit,
      PackPurgeStep.new,
      (value) => value.id,
    );
  }

  @override
  void dispose() {
    disposed = true;
    scope.cancel();
    owner._purgeReaders.remove(this);
  }
}
