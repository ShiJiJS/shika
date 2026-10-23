part of 'server_repository.dart';

/// Pack requests have independent lifetimes from video catalog/playback reads.
/// The connection owner still controls authentication, restore gates and expiry.
mixin _ServerPackCatalog on LibraryRepository {
  ServerApi get api;
  int get _generation;
  bool get _disposed;
  String get _session;
  void ensureNotRestoring();
  void publish();
  Future<Json> call(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    RequestScope? cancel,
    ServerApi? using,
  });

  RequestScope _packRead = RequestScope(),
      _packTagRead = RequestScope(),
      _packDirectoryRead = RequestScope();
  Future<void> _packWrites = Future.value();
  final Map<String, String> _packWriteKeys = {};
  ServerApi? _packWriteOwner;

  void _resetPackConnection() {
    cancelPackRead();
    cancelPackTagRead();
    cancelPackDirectoryRead();
    _packWriteOwner = null;
    _packWriteKeys.clear();
  }

  void _packSupported({bool tagsOnly = false}) {
    if (!(tagsOnly ? capabilities.packTags : capabilities.imagePacks)) {
      throw const LibraryFailure('当前服务尚不支持图包，请升级服务端');
    }
  }

  void _packCurrent(ServerApi target, int generation, [RequestScope? scope]) {
    if (_disposed ||
        generation != _generation ||
        !identical(target, connectionIdentity) ||
        scope?.cancelled == true) {
      throw const RequestCancelled();
    }
  }

  Future<String> _packDirectoryId(
    String path,
    ServerApi target,
    RequestScope scope,
  ) async {
    final directory = await call(
      'GET',
      '/api/v1/directories/resolve',
      using: target,
      cancel: scope,
      query: {'kind': 'pack', 'path': path},
    );
    if (directory['available'] != true) {
      throw const LibraryFailure('图包目录暂不可用，请检查挂载或目录启停状态');
    }
    return directory['id'] as String;
  }

  LibraryPack _pack(Json data, ServerApi target) {
    final progress = data['progress'] == null ? null : object(data['progress']);
    final cover = data['cover_url'] as String?;
    final url = cover == null ? null : target.resolve(cover);
    return LibraryPack(
      id: data['id'],
      rootId: data['root_id'],
      path: data['path'],
      name: data['name'],
      pageCount: data['page_count'],
      readableCount: data['readable_count'],
      contentVersion: data['content_version'],
      status: data['status'],
      error: data['error'],
      createdAt: (data['created_at'] as num?)?.toDouble() ?? 0,
      tags: List<String>.from(data['tag_ids']),
      cover: url == null
          ? null
          : MediaSource(
              url
                  .replace(
                    queryParameters: {
                      ...url.queryParameters,
                      'session': _session,
                    },
                  )
                  .toString(),
              asset: false,
              headers: target.authorization,
            ),
      progress: progress == null
          ? null
          : PackProgress(
              pageId: progress['page_id'],
              offsetRatio: (progress['offset_ratio'] as num).toDouble(),
              completed: progress['completed'],
              revision: progress['revision'],
              updatedAt: (progress['updated_at'] as num).toDouble(),
            ),
    );
  }

  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) async {
    _packSupported();
    cancelPackRead();
    final scope = _packRead = RequestScope();
    final target = api, generation = _generation;
    final directory = query.folder.isEmpty
        ? null
        : await _packDirectoryId(query.folder, target, scope);
    _packCurrent(target, generation, scope);
    final page = await call(
      'GET',
      '/api/v1/packs',
      using: target,
      cancel: scope,
      query: {
        'offset': '$offset',
        'limit': '$limit',
        'search': query.search,
        'read_state': query.readState.name,
        'sort': query.sort.name,
        'directory_id': ?directory,
        if (query.tags.isNotEmpty) 'tag_ids': query.tags.toList()..sort(),
      },
    );
    _packCurrent(target, generation, scope);
    return CatalogPage(
      items: rows(page).map((item) => _pack(item, target)),
      total: page['total'],
      offset: page['offset'],
      limit: page['limit'],
    );
  }

  @override
  Future<CatalogPage<PackTag>> loadPackTags({
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    _packSupported(tagsOnly: true);
    cancelPackTagRead();
    final scope = _packTagRead = RequestScope();
    final target = api, generation = _generation;
    final page = await call(
      'GET',
      '/api/v1/pack-tags',
      using: target,
      cancel: scope,
      query: {'search': search, 'offset': '$offset', 'limit': '$limit'},
    );
    _packCurrent(target, generation, scope);
    return CatalogPage(
      items: rows(page)
          .map((tag) => PackTag(tag['id'], tag['name'], tag['pack_count'])),
      total: page['total'],
      offset: page['offset'],
      limit: page['limit'],
    );
  }

  @override
  Future<CatalogPage<FolderEntry>> loadPackDirectories(
    String parent, {
    int offset = 0,
    int limit = 50,
  }) async {
    _packSupported();
    cancelPackDirectoryRead();
    final scope = _packDirectoryRead = RequestScope();
    final target = api, generation = _generation;
    final id = parent.isEmpty
        ? null
        : await _packDirectoryId(parent, target, scope);
    _packCurrent(target, generation, scope);
    final page = await call(
      'GET',
      '/api/v1/directories',
      using: target,
      cancel: scope,
      query: {
        'kind': 'pack',
        'offset': '$offset',
        'limit': '$limit',
        'parent_id': ?id,
      },
    );
    _packCurrent(target, generation, scope);
    return CatalogPage(
      items: rows(page).map(
        (row) => FolderEntry(
          row['name'],
          row['path'],
          id: row['id'],
          available: row['available'],
        ),
      ),
      total: page['total'],
      offset: page['offset'],
      limit: page['limit'],
    );
  }

  @override
  Future<void> editPackTag({
    String? original,
    String? name,
    bool delete = false,
  }) => _writePackTags(
    delete
        ? 'DELETE'
        : original == null
        ? 'POST'
        : 'PATCH',
    '/api/v1/pack-tags${original == null ? '' : '/${Uri.encodeComponent(original)}'}',
    {if (!delete) 'name': name?.trim()},
  ).then((_) {});

  @override
  Future<PackTag> createPackTag(String name) async {
    final result = await _writePackTags('POST', '/api/v1/pack-tags', {
      'name': name.trim(),
    });
    return PackTag(
      result['id'],
      result['name'],
      result['pack_count'] as int? ?? 0,
    );
  }

  @override
  Future<void> setPackTags(
    Set<String> ids,
    Set<String> tags, {
    bool replace = false,
  }) => _writePackTags('PATCH', '/api/v1/pack-tag-links', {
    'pack_ids': ids.toList()..sort(),
    'tag_ids': tags.toList()..sort(),
    'mode': replace ? 'replace' : 'add',
  }).then((_) {});

  Future<Json> _writePackTags(String method, String path, Json payload) {
    _packSupported(tagsOnly: true);
    ensureNotRestoring();
    final target = api, generation = _generation;
    if (!identical(target, _packWriteOwner)) {
      _packWriteOwner = target;
      _packWriteKeys.clear();
    }
    final signature = jsonEncode([method, path, payload]);
    final result = _packWrites.then((_) async {
      _packCurrent(target, generation);
      ensureNotRestoring();
      final key = _packWriteKeys.putIfAbsent(signature, requestId);
      try {
        final response = await call(
          method,
          path,
          using: target,
          body: {'request_id': key, ...payload},
        );
        _packCurrent(target, generation);
        _packWriteKeys.remove(signature);
        publish();
        return response;
      } on ApiFailure catch (error) {
        final status = error.status;
        if (status != null &&
            status >= 400 &&
            status < 500 &&
            status != 408 &&
            status != 429) {
          _packWriteKeys.remove(signature);
        }
        rethrow;
      }
    });
    _packWrites = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  void cancelPackRead() => _packRead.cancel();
  @override
  void cancelPackTagRead() => _packTagRead.cancel();
  @override
  void cancelPackDirectoryRead() => _packDirectoryRead.cancel();
}
