part of 'server_repository.dart';

class _ServerPackMissing implements PackMissingCatalog {
  _ServerPackMissing(
    this.owner,
    this.target,
    this.generation,
    this.epoch,
    this.fileScope,
  );
  final ServerLibraryRepository owner;
  final ServerApi target;
  final int generation, epoch;
  final String fileScope;
  RequestScope pages = RequestScope();
  final lifetime = RequestScope();
  final sending = <String, Future<MaintenanceTask>>{};
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

  Future<Json> call(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    RequestScope? cancel,
  }) async {
    check();
    final data = await owner.call(
      method,
      path,
      body: body,
      query: query,
      using: target,
      cancel: cancel ?? lifetime,
    );
    check();
    return data;
  }

  @override
  Future<CatalogPage<LibraryPack>> page({
    int offset = 0,
    int limit = 24,
  }) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw const LibraryFailure('缺失图包分页范围不正确');
    }
    cancelPages();
    final work = pages = RequestScope();
    final data = await call(
      'GET',
      '/api/v1/packs',
      query: {'status': 'missing', 'offset': '$offset', 'limit': '$limit'},
      cancel: work,
    );
    if (work.cancelled) throw const RequestCancelled();
    final total = data['total'];
    final found = rows(data).map((v) => owner._pack(v, target)).toList();
    if (total is! int ||
        total < 0 ||
        data['offset'] != offset ||
        data['limit'] != limit ||
        found.length != min(limit, max(0, total - offset)) ||
        found.any((p) => p.status != 'missing') ||
        found.map((p) => p.id).toSet().length != found.length) {
      throw const LibraryFailure('缺失图包清单不完整，请重新读取');
    }
    return CatalogPage(
      items: found,
      total: total,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<List<MissingCleanupReceipt>> pending() async {
    check();
    final value = await owner.packFileJournal.missingPending(fileScope);
    check();
    return value;
  }

  Future<MaintenanceTask> accepted(Json data, String requestId) async {
    final id = data['id'];
    if (id is! String ||
        id.isEmpty ||
        data['kind'] != 'pack_forget_missing' ||
        data['request_id'] != requestId) {
      throw const LibraryFailure('原清理任务身份不完整，请查询原请求');
    }
    final summary = MaintenanceTask(
      await call('GET', '/api/v1/maintenance-tasks/${Uri.encodeComponent(id)}'),
    );
    if (summary.id != id || summary.kind != 'pack_forget_missing') {
      throw const LibraryFailure('原清理任务身份不一致');
    }
    return summary;
  }

  @override
  Future<MaintenanceTask> submit(
    String requestId,
  ) => sending.putIfAbsent(requestId, () async {
    check();
    final fresh = await owner.packFileJournal.rememberMissing(
      fileScope,
      requestId,
    );
    check();
    if (!fresh) throw const LibraryFailure('原清理结果尚未核对，只能查询原请求');
    var acceptedPost = false;
    try {
      final data = await call(
        'POST',
        '/api/v1/packs/forget-missing',
        body: {'request_id': requestId, 'confirmed': true},
      );
      acceptedPost = true;
      final task = await accepted(data, requestId);
      await owner.packFileJournal.forgetMissingReceipt(fileScope, requestId);
      check();
      owner.publish();
      return task;
    } on ApiFailure catch (error) {
      if (!acceptedPost &&
          error.status != null &&
          error.status! >= 400 &&
          error.status! < 500 &&
          error.status != 408 &&
          error.status != 429) {
        await owner.packFileJournal.forgetMissingReceipt(fileScope, requestId);
      }
      rethrow;
    }
  });
  @override
  Future<MaintenanceTask?> query(String requestId) async {
    check();
    final pending = await this.pending();
    if (!pending.any((p) => p.requestId == requestId)) {
      throw const LibraryFailure('本机原清理请求已变化，请重新读取');
    }
    Json data;
    try {
      data = await call(
        'GET',
        '/api/v1/pack-missing-requests/${Uri.encodeComponent(requestId)}',
      );
    } on ApiFailure catch (error) {
      if (error.status == 404 && error.code == 'cleanup_request_not_found') {
        return null;
      }
      rethrow;
    }
    final task = await accepted(data, requestId);
    await owner.packFileJournal.forgetMissingReceipt(fileScope, requestId);
    check();
    owner.publish();
    return task;
  }

  @override
  Future<void> removeLocalReceipt(String requestId) async {
    check();
    await owner.packFileJournal.forgetMissingReceipt(fileScope, requestId);
    check();
    owner.publish();
  }

  @override
  void cancelPages() => pages.cancel();
  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    pages.cancel();
    lifetime.cancel();
    owner._missingReaders.remove(this);
  }
}
