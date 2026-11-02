part of 'server_repository.dart';

class _ServerPackReader implements PackReader {
  _ServerPackReader(this.owner, this.target, this.generation, this.epoch);
  final ServerLibraryRepository owner;
  final ServerApi target;
  final int generation, epoch;
  bool disposed = false;
  RequestScope metadata = RequestScope(), manifest = RequestScope();
  final Set<RequestScope> _entryReads = {};
  final RequestScope writes = RequestScope();
  final Map<String, Json> createScopes = {};

  @override
  bool get isCurrent =>
      !disposed &&
      !owner._disposed &&
      owner._generation == generation &&
      owner._readerEpoch == epoch &&
      identical(owner.connectionIdentity, target);

  void current([RequestScope? scope]) {
    if (!isCurrent || scope?.cancelled == true) {
      throw const RequestCancelled();
    }
    owner.ensureNotRestoring();
  }

  Never bad() => throw const LibraryFailure('服务返回的阅读数据不完整，请重新读取');
  Json map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : bad();
  String id(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 128
      ? value
      : bad();
  int integer(Object? value, {int minimum = 0}) =>
      value is int && value >= minimum ? value : bad();
  bool flag(Object? value) => value is bool ? value : bad();
  double ratio(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 1
      ? value.toDouble()
      : bad();
  E enumeration<E extends Enum>(List<E> values, Object? name) =>
      values.where((v) => v.name == name).firstOrNull ?? bad();
  List<Json> items(Json data) =>
      data['items'] is List ? (data['items'] as List).map(map).toList() : bad();
  String segment(String value) => Uri.encodeComponent(id(value));

  Future<Json> call(
    String method,
    String path,
    RequestScope scope, {
    Json? body,
    Json? query,
  }) async {
    current(scope);
    final result = await owner.call(
      method,
      path,
      using: target,
      cancel: scope,
      body: body,
      query: query,
    );
    current(scope);
    return result;
  }

  ReaderPreferences preferences(Json data, {bool defaults = false}) =>
      ReaderPreferences(
        mode: enumeration(ReaderMode.values, data['mode']),
        direction: enumeration(ReaderDirection.values, data['direction']),
        gap: flag(data['gap']),
        fit: enumeration(ReaderFit.values, data['fit']),
        revision: integer(data['revision']),
        overridden: defaults ? false : flag(data['overridden']),
      );

  MediaSource? media(
    Object? location,
    String pageId,
    int version,
    String suffix,
  ) {
    if (location == null) return null;
    if (location is! String) bad();
    final url = target.resolve(location);
    if (url.path != '/api/v1/pages/$pageId/$suffix' ||
        url.queryParameters['v'] != '$version' ||
        url.fragment.isNotEmpty) {
      bad();
    }
    return MediaSource(
      url
          .replace(
            queryParameters: {
              ...url.queryParameters,
              'session': owner._session,
              'reader': '$epoch',
            },
          )
          .toString(),
      asset: false,
      headers: target.authorization,
    );
  }

  ReaderPage page(Json data, String packId, int version) {
    final identity = id(data['id']);
    if (id(data['pack_id']) != packId ||
        integer(data['content_version'], minimum: 1) != version ||
        data['name'] is! String) {
      bad();
    }
    final error = data['error'];
    if (error != null && error is! String) bad();
    final image = media(data['image_url'], identity, version, 'image');
    final thumbnail = media(
      data['thumbnail_url'],
      identity,
      version,
      'thumbnail',
    );
    final width = integer(data['width']), height = integer(data['height']);
    if (error == null && (image == null || width == 0 || height == 0)) bad();
    if (error != null && (image != null || thumbnail != null)) bad();
    return ReaderPage(
      id: identity,
      packId: packId,
      name: data['name'],
      ordinal: integer(data['ordinal']),
      width: width,
      height: height,
      version: version,
      error: error,
      image: image,
      thumbnail: thumbnail,
    );
  }

  LibraryPack pack(Json data) {
    id(data['id']);
    id(data['root_id']);
    final count = integer(data['page_count']),
        readable = integer(data['readable_count']);
    if (readable > count) bad();
    integer(data['content_version']);
    try {
      return owner._pack(data, target);
    } on TypeError {
      bad();
    }
  }

  ReaderState state(
    Json data,
    String packId,
    int version, {
    bool receipt = false,
  }) {
    if (integer(data['content_version'], minimum: 1) != version) bad();
    final image = page(map(data['page']), packId, version);
    if (!image.readable) bad();
    final reason = data['recovery_reason'];
    if (reason != null &&
        !['page_removed', 'page_unreadable'].contains(reason)) {
      bad();
    }
    return ReaderState(
      page: image,
      pageIndex: integer(data['page_index']),
      mark: ReaderMark(
        image.id,
        offsetRatio: ratio(data['offset_ratio']),
        completed: flag(data['completed']),
      ),
      revision: integer(data['revision']),
      version: version,
      preferences: preferences(map(data['preferences'])),
      recoveryReason: reason as String?,
      sessionRevision: receipt ? integer(data['session_revision']) : null,
    );
  }

  ReaderNeighbor? neighbor(
    Object? raw, {
    required int cursor,
    required int total,
    required bool before,
    required String selected,
  }) {
    if (raw == null) return null;
    final data = map(raw), identity = id(data['pack_id']);
    final ordinal = integer(data['ordinal']);
    if (identity == selected ||
        ordinal >= total ||
        (before ? ordinal >= cursor : ordinal <= cursor)) {
      bad();
    }
    return ReaderNeighbor(identity, ordinal);
  }

  PackReadingRange range(Json data, {String? expectedId}) {
    final identity = id(data['id']),
        total = integer(data['candidate_count']),
        available = integer(data['available_count']);
    if (expectedId != null && identity != expectedId) bad();
    final revision = integer(data['revision']),
        finished = flag(data['finished']);
    if (available > total) bad();
    final source = map(data['source']);
    final kind = enumeration(BrowseSource.values, source['kind']);
    if (!['name', 'title', 'newest', 'recent'].contains(source['sort']) ||
        (source['sort'] == 'recent' && kind != BrowseSource.recent)) {
      bad();
    }
    if (!['sequential', 'random'].contains(data['order'])) bad();
    final scope = map(data['scope']);
    if (scope['search'] is! String ||
        ![
          'all',
          'unread',
          'reading',
          'completed',
        ].contains(scope['read_state']) ||
        scope['tag_ids'] is! List) {
      bad();
    }
    final tags = (scope['tag_ids'] as List).map(id).toList();
    if (tags.toSet().length != tags.length) bad();
    if (scope['directory_id'] != null) id(scope['directory_id']);
    LibraryPack? selected;
    ReaderState? resume;
    int? cursor;
    ReaderNeighbor? previous, next;
    if (available == 0) {
      if (data['current'] != null ||
          data['resume'] != null ||
          data['cursor'] != null ||
          data['previous'] != null ||
          data['next'] != null ||
          !finished) {
        bad();
      }
    } else {
      selected = pack(map(data['current']));
      cursor = integer(data['cursor']);
      if (cursor >= total ||
          selected.contentVersion < 1 ||
          selected.readableCount == 0 ||
          selected.status != 'available' ||
          selected.error != null) {
        bad();
      }
      resume = state(map(data['resume']), selected.id, selected.contentVersion);
      if (resume.pageIndex >= selected.pageCount) bad();
      previous = neighbor(
        data['previous'],
        cursor: cursor,
        total: total,
        before: true,
        selected: selected.id,
      );
      next = neighbor(
        data['next'],
        cursor: cursor,
        total: total,
        before: false,
        selected: selected.id,
      );
      if (previous != null && previous.packId == next?.packId) bad();
    }
    return PackReadingRange(
      id: identity,
      revision: revision,
      candidateCount: total,
      availableCount: available,
      cursor: cursor,
      finished: finished,
      pack: selected,
      resume: resume,
      source: kind,
      random: data['order'] == 'random',
      previous: previous,
      next: next,
    );
  }

  T decode<T>(ReaderCommand<T> command, Json data) {
    final Object result;
    switch (command) {
      case final CreatePackReading operation:
        result = range(data);
        final entry = operation.entry, raw = map(data['scope']);
        final expected = createScopes[operation.requestId];
        if ((result as PackReadingRange).source != entry.source ||
            map(data['source'])['sort'] != owner._packSort(entry.query.sort) ||
            result.random != entry.random ||
            raw['search'] != entry.query.search ||
            raw['read_state'] != entry.query.readState.name ||
            (raw['tag_ids'] as List)
                .toSet()
                .difference(entry.query.tags)
                .isNotEmpty ||
            (raw['tag_ids'] as List).length != entry.query.tags.length) {
          bad();
        }
        if (expected != null
            ? raw['directory_id'] != expected['directory_id']
            : (entry.query.folder.isEmpty
                  ? raw['directory_id'] != null
                  : raw['directory_id'] == null)) {
          bad();
        }
        break;
      case final MovePackReading operation:
        final value = range(data, expectedId: operation.sessionId);
        if (value.revision != operation.revision + 1 ||
            value.finished != operation.finish ||
            (!operation.finish && value.pack?.id != operation.packId)) {
          bad();
        }
        result = value;
        break;
      case final OpenPackReading operation:
        final value = state(
          data,
          operation.cursor.packId,
          operation.cursor.version,
          receipt: true,
        );
        if (value.revision != operation.cursor.progressRevision + 1 ||
            value.page.id != operation.pageId ||
            value.sessionRevision! < operation.cursor.sessionRevision ||
            value.sessionRevision! > operation.cursor.sessionRevision + 1) {
          bad();
        }
        result = value;
        break;
      case final WritePackProgress operation:
        final value = state(
          data,
          operation.cursor.packId,
          operation.cursor.version,
          receipt: true,
        );
        if (value.revision != operation.cursor.progressRevision + 1 ||
            value.sessionRevision != operation.cursor.sessionRevision ||
            value.mark.pageId != operation.mark.pageId ||
            value.mark.offsetRatio != operation.mark.offsetRatio ||
            value.mark.completed != operation.mark.completed) {
          bad();
        }
        result = value;
        break;
      case final WritePackPreferences operation:
        final value = preferences(data);
        if (!value.overridden ||
            value.revision != operation.preferences.revision + 1 ||
            jsonEncode(value.values) !=
                jsonEncode(operation.preferences.values)) {
          bad();
        }
        result = value;
        break;
      case final WriteReaderDefaults operation:
        final value = preferences(data, defaults: true);
        if (value.revision != operation.preferences.revision + 1 ||
            jsonEncode(value.values) !=
                jsonEncode(operation.preferences.values)) {
          bad();
        }
        result = value;
        break;
    }
    return result as T;
  }

  Json cursor(ReaderCursor value) => {
    'expected_session_revision': integer(value.sessionRevision),
    'expected_revision': integer(value.progressRevision),
    'content_version': integer(value.version, minimum: 1),
  };

  @override
  Future<T> submit<T>(ReaderCommand<T> command) async {
    current(writes);
    id(command.requestId);
    late String method, path;
    late Json body;
    switch (command) {
      case final CreatePackReading operation:
        final query = operation.entry.query;
        final directory = query.folder.isEmpty
            ? null
            : await owner._packDirectoryId(query.folder, target, writes);
        current(writes);
        final scope = {
          'directory_id': directory,
          'search': query.search,
          'tag_ids': query.tags.toList()..sort(),
          'read_state': query.readState.name,
        };
        if (!createScopes.containsKey(operation.requestId) &&
            createScopes.length >= 16) {
          throw const LibraryFailure('请先确认此前的阅读范围请求');
        }
        createScopes[operation.requestId] = scope;
        method = 'POST';
        path = '/api/v1/pack-sessions';
        body = {
          'scope': scope,
          'source': operation.entry.source.name,
          'sort': owner._packSort(query.sort),
          'order': operation.entry.random ? 'random' : 'sequential',
          'anchor_pack_id': operation.entry.anchorId,
        };
        break;
      case final MovePackReading operation:
        if ((operation.packId != null) == operation.finish) bad();
        method = 'PATCH';
        path = '/api/v1/pack-sessions/${segment(operation.sessionId)}/position';
        body = {
          'expected_revision': integer(operation.revision),
          'pack_id': operation.packId,
          'finish': operation.finish,
        };
        break;
      case final OpenPackReading operation:
        method = 'POST';
        path =
            '/api/v1/pack-sessions/${segment(operation.cursor.sessionId)}/opened';
        body = {
          ...cursor(operation.cursor),
          'pack_id': id(operation.cursor.packId),
          'page_id': id(operation.pageId),
        };
        break;
      case final WritePackProgress operation:
        method = 'PATCH';
        path = '/api/v1/packs/${segment(operation.cursor.packId)}/progress';
        body = {
          ...cursor(operation.cursor),
          'session_id': id(operation.cursor.sessionId),
          'page_id': id(operation.mark.pageId),
          'offset_ratio': ratio(operation.mark.offsetRatio),
          'completed': operation.mark.completed,
        };
        break;
      case final WritePackPreferences operation:
        method = 'PATCH';
        path = '/api/v1/packs/${segment(operation.cursor.packId)}/preferences';
        body = {
          'session_id': id(operation.cursor.sessionId),
          'expected_session_revision': integer(
            operation.cursor.sessionRevision,
          ),
          'expected_revision': integer(operation.preferences.revision),
          'values': operation.preferences.values,
        };
        break;
      case final WriteReaderDefaults operation:
        method = 'PATCH';
        path = '/api/v1/reading-defaults';
        body = {
          'expected_revision': integer(operation.preferences.revision),
          'values': operation.preferences.values,
        };
        break;
    }
    try {
      final data = await call(
        method,
        path,
        writes,
        body: {'request_id': command.requestId, ...body},
      );
      current(writes);
      final result = decode(command, data);
      createScopes.remove(command.requestId);
      owner.publish();
      current(writes);
      return result;
    } on ApiFailure catch (error) {
      final status = error.status;
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429) {
        createScopes.remove(command.requestId);
      }
      rethrow;
    }
  }

  @override
  Future<T?> receipt<T>(ReaderCommand<T> command) async {
    current();
    cancelMetadata();
    final scope = metadata = RequestScope();
    try {
      final data = await call(
        'GET',
        '/api/v1/pack-reading-requests/${command.kind}/${segment(command.requestId)}',
        scope,
      );
      current(scope);
      if (data['status'] != 'completed') bad();
      final result = decode(command, map(data['result']));
      createScopes.remove(command.requestId);
      owner.publish();
      current(scope);
      return result;
    } on ApiFailure catch (error) {
      if (error.status == 404 && error.code == 'reading_request_not_found') {
        current(scope);
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<PackReadingRange> read(String sessionId) async {
    current();
    cancelMetadata();
    final scope = metadata = RequestScope();
    final data = await call(
      'GET',
      '/api/v1/pack-sessions/${segment(sessionId)}',
      scope,
    );
    current(scope);
    return range(data, expectedId: sessionId);
  }

  @override
  Future<PackManifest> pages(
    String packId, {
    required int version,
    int offset = 0,
    int limit = 40,
  }) async {
    current();
    cancelPages();
    final scope = manifest = RequestScope();
    integer(version, minimum: 1);
    integer(offset);
    if (limit < 1 || limit > 200) bad();
    final data = await call(
      'GET',
      '/api/v1/packs/${segment(packId)}/pages',
      scope,
      query: {'v': '$version', 'offset': '$offset', 'limit': '$limit'},
    );
    current(scope);
    if (data['content_version'] != version ||
        data['offset'] != offset ||
        data['limit'] != limit) {
      bad();
    }
    final total = integer(data['total']), raw = items(data);
    if (raw.length != min(limit, max(0, total - offset))) bad();
    final values = raw.map((row) => page(row, packId, version)).toList();
    if (values.map((row) => row.id).toSet().length != values.length) bad();
    for (var i = 1; i < values.length; i++) {
      if (values[i].ordinal <= values[i - 1].ordinal) bad();
    }
    return PackManifest(
      pages: values,
      packId: packId,
      version: version,
      total: total,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<ReaderQueuePage> queue(
    String sessionId, {
    int offset = 0,
    int limit = 40,
  }) async {
    current();
    final scope = RequestScope();
    _entryReads.add(scope);
    try {
      integer(offset);
      if (limit < 1 || limit > 200) bad();
      final data = await call(
        'GET',
        '/api/v1/pack-sessions/${segment(sessionId)}/entries',
        scope,
        query: {'offset': '$offset', 'limit': '$limit'},
      );
      current(scope);
      final total = integer(data['total']), raw = items(data);
      if (data['offset'] != offset ||
          data['limit'] != limit ||
          raw.length != min(limit, max(0, total - offset))) {
        bad();
      }
      final values = <ReaderQueueEntry>[];
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (integer(item['ordinal']) != offset + i) bad();
        values.add(
          ReaderQueueEntry(
            offset + i,
            pack(map(item['pack'])),
            available: flag(item['available']),
          ),
        );
      }
      if (values.map((row) => row.pack.id).toSet().length != values.length) {
        bad();
      }
      return ReaderQueuePage(
        entries: values,
        total: total,
        offset: offset,
        limit: limit,
        revision: integer(data['revision']),
      );
    } finally {
      _entryReads.remove(scope);
    }
  }

  @override
  Future<ReaderPreferences> defaults() async {
    current();
    cancelMetadata();
    final scope = metadata = RequestScope();
    final data = await call('GET', '/api/v1/reading-defaults', scope);
    current(scope);
    return preferences(data, defaults: true);
  }

  @override
  void cancelMetadata() => metadata.cancel();
  @override
  void cancelPages() => manifest.cancel();
  @override
  void cancelQueue() {
    for (final read in _entryReads.toList()) {
      read.cancel();
    }
    _entryReads.clear();
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    cancelMetadata();
    cancelPages();
    cancelQueue();
    writes.cancel();
    createScopes.clear();
    owner._readers.remove(this);
  }
}
