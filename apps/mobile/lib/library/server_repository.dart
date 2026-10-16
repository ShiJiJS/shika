import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'credentials.dart';
import 'models.dart';
import 'repository.dart';
import 'server_api.dart';

typedef Json = Map<String, dynamic>;

Json object(Object? value) => Map<String, dynamic>.from(value as Map);
List<Json> rows(Json value) => (value['items'] as List).map(object).toList();
String requestId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

/// Server IDs remain authoritative; this cache contains only visited pages and
/// the small playback window. It is never used as a replacement NAS database.
class ServerLibraryRepository extends LibraryRepository {
  ServerLibraryRepository(
    this.credentials, {
    String address = '10.0.2.2',
    int port = 8760,
  }) : _state = LibrarySnapshot(
         videos: [],
         roots: [],
         tags: [],
         query: VideoQuery(),
         round: [],
         address: address,
         port: port,
         connected: false,
       );
  final CredentialStore credentials;
  LibrarySnapshot _state;
  ServerApi? _api;
  Json? _round;
  Json? _pendingRound;
  String? _pendingRoundSignature;
  final Map<String, LibraryVideo> _videos = {};
  final Map<String, FolderEntry> _directories = {};
  final Map<String, String> _tagNames = {}, _trashIds = {};
  final Map<String, int> _tagCounts = {};
  final Map<String, String> _retryKeys = {};
  RequestScope _videoRead = RequestScope(),
      _folderRead = RequestScope(),
      _scanRead = RequestScope();
  int _generation = 0, _scopeGeneration = 0, _missing = 0, _trash = 0;
  bool _disposed = false;
  String _session = requestId();
  String? _scanTask,
      _exportTask,
      _importTask,
      _importKey,
      _previewText,
      _restoreTask,
      _restoreKey;
  BackupPreview? _preview;
  int? _connectingGeneration;
  Future<void> _credentialWrites = Future.value(),
      _roundWrites = Future.value();
  String? _connectionError;
  @override
  String? get connectionError => _connectionError;
  @override
  Future<String?> playbackFailure(MediaSource source) async {
    final target = _api;
    if (target == null ||
        source.headers['Authorization'] !=
            target.authorization['Authorization']) {
      return null;
    }
    final generation = _generation;
    try {
      await target.request(
        'HEAD',
        Uri.parse(source.location).path,
        timeout: const Duration(seconds: 5),
      );
      return null;
    } on ApiFailure catch (error) {
      if (generation != _generation || !identical(target, _api)) return null;
      if (error.status == 401) {
        await expire();
        return null;
      }
      if (error.status == 409 || error.status == 404) {
        await synchronize(target, generation);
        return '视频已不可用，已更新当前播放范围';
      }
      if (error.status == 503) return '播放连接繁忙，请稍后重试或滑动继续';
      return error.message;
    }
  }

  @override
  Future<void> mediaUnauthorized(MediaSource source) async {
    if (_connectingGeneration == null &&
        _api != null &&
        source.headers['Authorization'] ==
            _api!.authorization['Authorization']) {
      await expire();
    }
  }

  @override
  LibrarySnapshot get snapshot => _state;
  @override
  String tagName(String id) => _tagNames[id] ?? '标签';
  @override
  int tagVideoCount(String id) => _tagCounts[id] ?? 0;
  @override
  int get missingCount => _missing;
  @override
  int get trashCount => _trash;
  @override
  int get playbackPosition => (_round?['position'] as num?)?.toInt() ?? 0;
  @override
  int get playbackTotal => (_round?['total'] as num?)?.toInt() ?? 0;
  @override
  LibraryVideo? get current =>
      _state.round.isEmpty ? null : _videos[_state.round[_state.position]];

  void publish() {
    if (!_disposed) notifyListeners();
  }

  ServerApi get api => _api ?? (throw const LibraryFailure('请先连接视频库'));

  Future<Json> call(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    RequestScope? cancel,
    ServerApi? using,
  }) async {
    final target = using ?? api;
    final generation = _generation;
    try {
      return await target.json(
        method,
        path,
        body: body,
        query: query,
        scope: cancel,
      );
    } on ApiFailure catch (error) {
      if (error.status == 401 &&
          identical(target, _api) &&
          generation == _generation &&
          _connectingGeneration == null) {
        await expire();
      }
      rethrow;
    }
  }

  Future<void> expire() async {
    _connectionError = '连接凭据已失效，请重新输入口令';
    _generation++;
    cancelVideoRead();
    cancelFolderRead();
    _scanRead.cancel();
    _api?.close();
    _api = null;
    _videos.clear();
    _directories.clear();
    _tagNames.clear();
    _tagCounts.clear();
    _trashIds.clear();
    _round = null;
    _pendingRound = null;
    _pendingRoundSignature = null;
    _state = _state.copy(
      connected: false,
      videos: [],
      roots: [],
      tags: [],
      round: [],
      position: 0,
      clearDelete: true,
    );
    publish();
    await writeCredentials(credentials.clear);
  }

  Future<void> writeCredentials(
    Future<void> Function() action, {
    int? generation,
  }) {
    final result = _credentialWrites.then((_) async {
      if (generation != null && generation != _generation) {
        throw const RequestCancelled();
      }
      await action();
    });
    _credentialWrites = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static Uri endpoint(String address, int port) {
    try {
      if (address.trim().isEmpty || port < 1 || port > 65535) {
        throw const FormatException();
      }
      final parsed = Uri.parse(
        address.contains('://') ? address.trim() : 'http://${address.trim()}',
      );
      if (!['http', 'https'].contains(parsed.scheme) ||
          parsed.host.isEmpty ||
          parsed.userInfo.isNotEmpty ||
          parsed.hasQuery ||
          parsed.hasFragment ||
          (parsed.path.isNotEmpty && parsed.path != '/')) {
        throw const FormatException();
      }
      return Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : port,
      );
    } catch (_) {
      throw const LibraryFailure('请填写有效服务地址和 1–65535 之间的端口');
    }
  }

  void rememberAddress(Uri endpoint) {
    _state = _state.copy(
      address: Uri(scheme: endpoint.scheme, host: endpoint.host).toString(),
      port: endpoint.port,
    );
  }

  @override
  Future<void> initialize() async {
    final generation = ++_generation;
    final savedEndpoint = await credentials.readEndpoint();
    if (generation != _generation) throw const RequestCancelled();
    if (savedEndpoint != null) rememberAddress(savedEndpoint);
    final saved = await credentials.read();
    if (generation != _generation) throw const RequestCancelled();
    if (saved == null || !saved.expiresAt.isAfter(DateTime.now())) {
      if (saved != null) {
        await writeCredentials(credentials.clear, generation: generation);
      }
      publish();
      return;
    }
    final candidate = ServerApi(saved.endpoint, token: saved.token);
    _connectingGeneration = generation;
    try {
      final info = await candidate.json('GET', '/api/v1/info');
      if (info['api_version'] != 1 || info['server_id'] != saved.serverId) {
        await writeCredentials(credentials.clear, generation: generation);
        throw const LibraryFailure('服务实例或版本已变化，请重新连接');
      }
      await synchronize(candidate, generation, allowConnection: true);
    } on ApiFailure catch (error) {
      if (error.status == 401 && generation == _generation) {
        await writeCredentials(credentials.clear, generation: generation);
      }
      rethrow;
    } finally {
      if (_connectingGeneration == generation) _connectingGeneration = null;
      if (!identical(candidate, _api)) candidate.close();
    }
  }

  @override
  Future<void> connect(String address, int port, String passphrase) async {
    final location = endpoint(address, port);
    if (passphrase.isEmpty || passphrase.length > 1024) {
      throw const LibraryFailure('请填写个人口令');
    }
    final candidate = ServerApi(location);
    final generation = ++_generation;
    _connectingGeneration = generation;
    try {
      final login = await candidate.json(
        'POST',
        '/api/v1/auth/login',
        body: {'passphrase': passphrase},
      );
      candidate.token = login['access_token'] as String;
      final info = await candidate.json('GET', '/api/v1/info');
      if (info['api_version'] != 1) throw const LibraryFailure('服务版本不兼容');
      final session = ConnectionCredentials(
        endpoint: location,
        token: candidate.token,
        serverId: info['server_id'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          ((login['expires_at'] as num) * 1000).round(),
          isUtc: true,
        ),
      );
      await synchronize(
        candidate,
        generation,
        beforePublish: () => writeCredentials(
          () => credentials.save(session),
          generation: generation,
        ),
        allowConnection: true,
      );
    } finally {
      if (_connectingGeneration == generation) _connectingGeneration = null;
      if (!identical(candidate, _api)) candidate.close();
    }
  }

  LibraryVideo video(
    Json data,
    ServerApi target, {
    VideoStatus? status,
    String? originalPath,
  }) {
    final thumbnail = data['thumbnail_url'] as String?;
    return LibraryVideo(
      id: data['id'],
      path: data['path'],
      rootId: data['root_id'],
      portrait: (data['height'] as num) > (data['width'] as num),
      source: MediaSource(
        target.resolve(data['media_url']).toString(),
        asset: false,
        headers: target.authorization,
      ),
      poster: thumbnail == null
          ? ''
          : target
                .resolve(thumbnail)
                .replace(queryParameters: {'session': _session})
                .toString(),
      tags: List<String>.from(data['tag_ids']),
      seconds: (data['duration'] as num).ceil(),
      type: data['type'],
      status: status ?? VideoStatus.values.byName(data['status']),
      originalPath: originalPath,
    );
  }

  FolderEntry folder(Json data) => FolderEntry(
    data['name'],
    data['path'],
    id: data['id'],
    available: data['available'],
  );

  Future<List<Json>> allTags(ServerApi target) async {
    final found = <Json>[];
    while (true) {
      final page = await call(
        'GET',
        '/api/v1/tags',
        query: {'offset': '${found.length}', 'limit': '200'},
        using: target,
      );
      final batch = rows(page);
      found.addAll(batch);
      if (batch.isEmpty || found.length >= (page['total'] as int)) return found;
    }
  }

  Future<void> synchronize(
    ServerApi target,
    int generation, {
    Future<void> Function()? beforePublish,
    bool allowConnection = false,
  }) async {
    final scopeGeneration = _scopeGeneration;
    final response = await Future.wait([
      call('GET', '/api/v1/roots', using: target),
      call('GET', '/api/v1/playback', using: target),
      call(
        'GET',
        '/api/v1/videos',
        query: {'status': 'missing', 'limit': '1'},
        using: target,
      ),
      call('GET', '/api/v1/trash', query: {'limit': '1'}, using: target),
    ]);
    final tags = await allTags(target);
    final roots = rows(response[0]).map((root) {
      final stamp = root['last_scan'] as num?;
      final date = stamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((stamp * 1000).round());
      return MediaRoot(
        root['id'],
        root['name'],
        root['path'],
        available: root['available'],
        directoryId: root['directory_id'],
        error: root['error'],
        lastScan: date == null
            ? '尚未扫描'
            : '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      );
    }).toList();
    final round = response[1];
    final scope = object(round['scope']);
    var path = '';
    FolderEntry? selectedDirectory;
    if (scope['directory_id'] != null) {
      try {
        selectedDirectory = folder(
          await call(
            'GET',
            '/api/v1/directories/${scope['directory_id']}',
            using: target,
          ),
        );
        path = selectedDirectory.path;
      } on ApiFailure catch (error) {
        if (error.status != 404) rethrow;
        path = '原目录已移除';
      }
    }
    if (generation != _generation ||
        _disposed ||
        scopeGeneration != _scopeGeneration ||
        (_round?['id'] == round['id'] &&
            (_round?['revision'] as int? ?? 0) > (round['revision'] as int))) {
      throw const RequestCancelled();
    }
    await beforePublish?.call();
    if (generation != _generation || _disposed) throw const RequestCancelled();
    if (!allowConnection && !identical(target, _api)) {
      throw const RequestCancelled();
    }
    if (!identical(target, _api)) {
      _pendingRound = null;
      _pendingRoundSignature = null;
      cancelVideoRead();
      cancelFolderRead();
      _scanRead.cancel();
      _api?.close();
      _videos.clear();
      _directories.clear();
      _tagNames.clear();
      _trashIds.clear();
      _session = requestId();
    }
    _api = target;
    if (_round != null && _round!['id'] != round['id']) {
      ++_scopeGeneration;
      cancelVideoRead();
    }
    _connectionError = null;
    _tagNames.addEntries(
      tags.map((tag) => MapEntry(tag['id'] as String, tag['name'] as String)),
    );
    _tagCounts
      ..clear()
      ..addEntries(
        tags.map(
          (tag) => MapEntry(tag['id'] as String, tag['video_count'] as int),
        ),
      );
    for (final root in roots) {
      _directories[root.path] = FolderEntry(
        root.name,
        root.path,
        id: root.directoryId,
        available: root.available,
      );
    }
    if (selectedDirectory != null) {
      _directories[selectedDirectory.path] = selectedDirectory;
    }
    _missing = response[2]['total'];
    _trash = response[3]['total'];
    final window = (round['window'] as List).map(object).toList();
    for (final entry in window) {
      final item = video(object(entry['video']), target);
      _videos[item.id] = item;
    }
    final currentId = (round['current'] as Map?)?['id'];
    final ids = window.map((entry) => entry['video']['id'] as String).toList();
    _round = round;
    _state = _state.copy(
      videos: _videos.values,
      roots: roots,
      tags: tags.map((tag) => tag['id'] as String),
      round: ids,
      position: currentId is String ? max(0, ids.indexOf(currentId)) : 0,
      connected: true,
      address: Uri(
        scheme: target.endpoint.scheme,
        host: target.endpoint.host,
      ).toString(),
      port: target.endpoint.port,
      order: PlayOrder.values.byName(round['order']),
      query: VideoQuery(
        folder: path,
        tags: List<String>.from(scope['tag_ids'] ?? []),
        orientation: scope['orientation'] ?? '',
        duration: scope['duration'] ?? '',
        type: scope['file_type'] ?? '',
      ),
    );
    publish();
  }

  @override
  List<LibraryVideo> query({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 100000,
  }) {
    final chosen = scope ?? _state.query;
    return _videos.values
        .where(
          (item) =>
              item.status == VideoStatus.available &&
              _state.roots.any(
                (root) => root.id == item.rootId && root.available,
              ) &&
              (chosen.folder.isEmpty || under(item.path, chosen.folder)) &&
              item.tags.containsAll(chosen.tags) &&
              (chosen.orientation.isEmpty ||
                  (chosen.orientation == 'portrait') == item.portrait) &&
              (chosen.duration.isEmpty ||
                  (chosen.duration == 'short'
                      ? item.seconds <= 10
                      : item.seconds > 10)) &&
              (chosen.type.isEmpty || chosen.type == item.type) &&
              item.name.contains(search),
        )
        .skip(offset)
        .take(limit)
        .toList();
  }

  Future<String?> directoryId(String path, {RequestScope? cancel}) async {
    if (path.isEmpty) return null;
    if (path == _state.query.folder &&
        _round?['scope']['directory_id'] != null) {
      return _round!['scope']['directory_id'] as String;
    }
    final cached = _directories[path];
    if (cached != null) return cached.id;
    final resolved = folder(
      await call(
        'GET',
        '/api/v1/directories/resolve',
        query: {'path': path},
        cancel: cancel,
      ),
    );
    _directories[path] = resolved;
    return resolved.id;
  }

  Future<Json> scopeBody(VideoQuery scope, {RequestScope? cancel}) async => {
    if (scope.folder.isNotEmpty)
      'directory_id': await directoryId(scope.folder, cancel: cancel),
    'tag_ids': scope.tags.toList()..sort(),
    if (scope.orientation.isNotEmpty) 'orientation': scope.orientation,
    if (scope.duration.isNotEmpty) 'duration': scope.duration,
    if (scope.type.isNotEmpty) 'file_type': scope.type,
  };

  @override
  Future<VideoPage> loadVideos({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 24,
  }) async {
    cancelVideoRead();
    final work = _videoRead = RequestScope();
    final generation = _generation, scopeGeneration = _scopeGeneration;
    final chosen = await scopeBody(scope ?? _state.query, cancel: work);
    final page = await call(
      'GET',
      '/api/v1/videos',
      query: {
        ...chosen,
        'offset': '$offset',
        'limit': '$limit',
        if (search.isNotEmpty) 'search': search,
      },
      cancel: work,
    );
    if (generation != _generation ||
        scopeGeneration != _scopeGeneration ||
        work.cancelled) {
      throw const RequestCancelled();
    }
    final items = rows(page).map((item) => video(item, api)).toList();
    for (final item in items) {
      _videos[item.id] = item;
    }
    _state = _state.copy(videos: _videos.values);
    return VideoPage(
      items: items,
      total: page['total'],
      offset: offset,
      limit: limit,
    );
  }

  @override
  List<FolderEntry> folders(String parent) => parent.isEmpty
      ? _state.roots
            .map(
              (root) => FolderEntry(
                root.name,
                root.path,
                id: root.directoryId,
                available: root.available,
              ),
            )
            .toList()
      : _directories.values
            .where(
              (entry) =>
                  entry.path != parent &&
                  entry.path.substring(0, entry.path.lastIndexOf('/')) ==
                      parent,
            )
            .toList();

  @override
  Future<List<FolderEntry>> loadFolders(String parent) async {
    cancelFolderRead();
    final work = _folderRead = RequestScope();
    if (parent.isEmpty) return folders(parent);
    final id = await directoryId(parent, cancel: work);
    final found = rows(
      await call(
        'GET',
        '/api/v1/directories',
        query: {'parent_id': id},
        cancel: work,
      ),
    ).map(folder).toList();
    if (work.cancelled) throw const RequestCancelled();
    for (final entry in found) {
      _directories[entry.path] = entry;
    }
    return found;
  }

  @override
  void cancelVideoRead() => _videoRead.cancel();
  @override
  void cancelFolderRead() => _folderRead.cancel();

  @override
  Future<void> setScope(VideoQuery scope, {PlayOrder? order}) =>
      changeRound(scope, order ?? _state.order);

  Future<void> acceptRound(
    Json round,
    ServerApi target,
    int generation,
    int scopeGeneration,
  ) async {
    final scope = object(round['scope']);
    var path = '';
    if (scope['directory_id'] != null) {
      final known = _directories.values
          .where((entry) => entry.id == scope['directory_id'])
          .firstOrNull;
      if (known != null) {
        path = known.path;
      } else {
        try {
          final found = folder(
            await call(
              'GET',
              '/api/v1/directories/${scope['directory_id']}',
              using: target,
            ),
          );
          path = found.path;
          if (generation == _generation) _directories[found.path] = found;
        } on ApiFailure catch (error) {
          if (error.status != 404) rethrow;
          path = '原目录已移除';
        }
      }
    }
    if (_disposed ||
        generation != _generation ||
        scopeGeneration != _scopeGeneration) {
      throw const RequestCancelled();
    }
    final window = (round['window'] as List).map(object).toList();
    for (final entry in window) {
      final item = video(object(entry['video']), target);
      _videos[item.id] = item;
    }
    final ids = window.map((entry) => entry['video']['id'] as String).toList();
    final currentId = (round['current'] as Map?)?['id'];
    _round = round;
    _state = _state.copy(
      videos: _videos.values,
      round: ids,
      position: currentId is String ? max(0, ids.indexOf(currentId)) : 0,
      order: PlayOrder.values.byName(round['order']),
      query: VideoQuery(
        folder: path,
        tags: List<String>.from(scope['tag_ids'] ?? []),
        orientation: scope['orientation'] ?? '',
        duration: scope['duration'] ?? '',
        type: scope['file_type'] ?? '',
      ),
    );
    publish();
  }

  Future<void> changeRound(
    VideoQuery scope,
    PlayOrder order, {
    String? anchor,
  }) {
    cancelVideoRead();
    final scopeGeneration = ++_scopeGeneration, generation = _generation;
    final target = api;
    final result = _roundWrites.then((_) async {
      if (scopeGeneration != _scopeGeneration || generation != _generation) {
        throw const RequestCancelled();
      }
      final resolved = await scopeBody(scope);
      if (scopeGeneration != _scopeGeneration || generation != _generation) {
        throw const RequestCancelled();
      }
      final signature = jsonEncode({
        'order': order.name,
        'scope': resolved,
        'anchor': anchor,
      });
      if (_pendingRoundSignature != signature) {
        _pendingRoundSignature = signature;
        _pendingRound = {
          'request_id': requestId(),
          'order': order.name,
          'scope': resolved,
          'anchor_video_id': ?anchor,
        };
      }
      final round = await call(
        'POST',
        '/api/v1/rounds',
        using: target,
        body: _pendingRound,
      );
      _pendingRound = null;
      _pendingRoundSignature = null;
      if (round['active'] == false) {
        await synchronize(target, generation);
        throw const LibraryFailure('播放范围已变化，已恢复当前轮次');
      }
      await acceptRound(round, target, generation, scopeGeneration);
    });
    _roundWrites = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  Future<void> newRound() => setScope(_state.query);
  @override
  Future<void> openVideo(String id) =>
      changeRound(_state.query, _state.order, anchor: id);

  @override
  Future<void> step(int delta) async {
    if (_round == null || _state.round.isEmpty) return;
    final targetApi = api,
        generation = _generation,
        scopeGeneration = _scopeGeneration;
    final target = _state.position + delta;
    final body = <String, dynamic>{'expected_revision': _round!['revision']};
    if (target >= _state.round.length) {
      body['finish'] = true;
    } else if (target < 0) {
      return;
    } else {
      body['video_id'] = _state.round[target];
    }
    try {
      final round = await call(
        'PATCH',
        '/api/v1/rounds/${_round!['id']}/position',
        body: body,
        using: targetApi,
      );
      await acceptRound(round, targetApi, generation, scopeGeneration);
    } on ApiFailure catch (error) {
      if (error.status == 409 &&
          generation == _generation &&
          scopeGeneration == _scopeGeneration) {
        await synchronize(targetApi, generation);
      }
      rethrow;
    }
  }

  Future<Json> waitTask(String id, {RequestScope? cancel}) async {
    while (true) {
      if (_disposed || cancel?.cancelled == true) {
        throw const RequestCancelled();
      }
      final task = await call('GET', '/api/v1/tasks/$id', cancel: cancel);
      if (['completed', 'failed', 'interrupted'].contains(task['status'])) {
        return task;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<Json> operation(String path, Json body, {String? idempotency}) async {
    final submitted = await call(
      'POST',
      path,
      body: {'request_id': idempotency ?? requestId(), ...body},
    );
    final result = await waitTask(submitted['id']);
    _videos.clear();
    await synchronize(api, _generation);
    return result;
  }

  String failure(Json task) {
    final items = (task['result'] as Map?)?['items'] as List? ?? [];
    final problems = items
        .map(object)
        .where((item) => item['outcome'] != 'succeeded');
    final messages = {
      'destination_conflict': '原位置已有同名文件，未覆盖',
      'permission_denied': '目录没有写入权限',
      'insufficient_space': '目标空间不足，完整来源已保留',
      'source_missing': '源文件已缺失',
      'source_replaced': '源文件已被替换，未执行',
      'stale_delete': '撤销已失效，请在回收站查看',
    };
    if (problems.isEmpty) return '操作未完成，请刷新后重试';
    return problems
        .map((item) => messages[item['error']] ?? '部分文件操作未完成，请刷新后重试')
        .toSet()
        .join('\n');
  }

  @override
  Future<void> setVideoTags(
    Set<String> ids,
    Set<String> tags, {
    bool remove = false,
    bool replace = false,
  }) async {
    await call(
      'PATCH',
      '/api/v1/video-tags',
      body: {
        'request_id': requestId(),
        'video_ids': ids.toList(),
        'tag_ids': tags.toList(),
        'mode': replace
            ? 'replace'
            : remove
            ? 'remove'
            : 'add',
      },
    );
    _videos.clear();
    await synchronize(api, _generation);
  }

  @override
  Future<void> editTag({
    String? original,
    String? name,
    bool delete = false,
  }) async {
    await call(
      delete
          ? 'DELETE'
          : original == null
          ? 'POST'
          : 'PATCH',
      '/api/v1/tags${original == null ? '' : '/$original'}',
      body: {'request_id': requestId(), if (!delete) 'name': name},
    );
    await synchronize(api, _generation);
  }

  @override
  Future<void> deleteVideos(
    Set<String> ids, {
    required String requestId,
  }) async {
    final before = _state;
    final task = await operation('/api/v1/videos/trash', {
      'video_ids': ids.toList(),
    }, idempotency: requestId);
    final result = object(task['result']);
    if ((result['succeeded'] as int? ?? 0) > 0) {
      final successful = (result['items'] as List)
          .map(object)
          .where((item) => item['outcome'] == 'succeeded')
          .map((item) => item['video_id'] as String);
      _state = _state.copy(
        lastDelete: DeleteOperation(
          task['id'],
          successful,
          before.round,
          before.position,
        ),
      );
      publish();
    }
    if (task['status'] != 'completed' || result['partial'] == true) {
      throw LibraryFailure(failure(task));
    }
  }

  @override
  Future<void> undoDelete({required String operationId}) async {
    final key = _retryKeys.putIfAbsent('undo:$operationId', requestId);
    final task = await operation(
      '/api/v1/operations/$operationId/undo',
      {},
      idempotency: key,
    );
    if (task['status'] != 'completed') throw LibraryFailure(failure(task));
    _state = _state.copy(clearDelete: true);
    publish();
  }

  @override
  Future<List<String>> restoreVideos(Set<String> ids) async {
    final task = await operation('/api/v1/trash/restore', {
      'trash_ids': ids.map((id) => _trashIds[id] ?? '').toList(),
    });
    return (object(task['result'])['items'] as List? ?? [])
        .map(object)
        .where((item) => item['outcome'] != 'succeeded')
        .map(
          (item) => failure({
            'result': {
              'items': [item],
            },
          }),
        )
        .toList();
  }

  @override
  Future<void> permanentlyDelete(Set<String> ids) async {
    final task = await operation('/api/v1/trash/permanent', {
      'trash_ids': ids.map((id) => _trashIds[id] ?? '').toList(),
      'confirmed': true,
    });
    if (task['status'] != 'completed' ||
        object(task['result'])['partial'] == true) {
      throw LibraryFailure(failure(task));
    }
  }

  @override
  Future<void> saveRoot(MediaRoot root) async {
    await call(
      root.id.isEmpty ? 'POST' : 'PUT',
      '/api/v1/roots${root.id.isEmpty ? '' : '/${root.id}'}',
      body: {'name': root.name, 'path': root.path},
    );
    await synchronize(api, _generation);
  }

  @override
  Future<void> refresh() async {
    _scanRead.cancel();
    final work = _scanRead = RequestScope();
    final submitted = await call('POST', '/api/v1/scans');
    _scanTask = submitted['id'];
    final result = await waitTask(_scanTask!, cancel: work);
    if (result['status'] != 'completed') {
      throw const LibraryFailure('扫描未完成，请重试');
    }
    _videos.clear();
    await synchronize(api, _generation);
    _scanTask = null;
  }

  @override
  Future<String> exportBackupFile() async {
    _exportTask ??= (await call(
      'POST',
      '/api/v1/backups',
      body: {'request_id': requestId()},
    ))['id'];
    final task = await waitTask(_exportTask!);
    if (task['status'] != 'completed') {
      _exportTask = null;
      throw const LibraryFailure('备份导出失败，请重试');
    }
    final response = await api.request(
      'GET',
      '/api/v1/backups/$_exportTask/download',
      maximumBytes: 32 * 1024 * 1024,
    );
    _exportTask = null;
    return utf8.decode(response.bytes);
  }

  @override
  Future<BackupPreview> inspectBackupFile(String text) async {
    if (_previewText == text && _preview != null) return _preview!;
    if (_previewText != text) {
      _previewText = text;
      _preview = null;
      _importTask = null;
      _importKey = requestId();
    }
    if (_importTask == null) {
      final accepted = await api.request(
        'POST',
        '/api/v1/backup-imports',
        body: utf8.encode(text),
        headers: {'Idempotency-Key': _importKey!},
      );
      _importTask = object(jsonDecode(utf8.decode(accepted.bytes)))['id'];
    }
    final task = await waitTask(_importTask!);
    if (task['status'] != 'completed') {
      throw const LibraryFailure('备份校验失败，请检查文件格式和版本');
    }
    final result = object(task['result']);
    final roots = (result['roots'] as List).map(object).toList();
    return _preview = BackupPreview(
      LibrarySnapshot(
        videos: [],
        roots: roots.map(
          (root) => MediaRoot(root['id'], root['name'], root['original_path']),
        ),
        tags: [],
        query: VideoQuery(),
        round: [],
      ),
      importId: _importTask,
      suggestedMappings: {
        for (final root in roots) root['id']: root['suggested_path'],
      },
    );
  }

  @override
  Future<void> restoreBackup(
    String text,
    Map<String, String> rootMappings,
  ) async {
    final preview = await inspectBackupFile(text);
    final payload = {
      'preview_id': preview.importId,
      'root_mapping': rootMappings.map(
        (key, value) =>
            MapEntry(key, value.trim().isEmpty ? null : value.trim()),
      ),
      'confirmed': true,
    };
    final signature = jsonEncode(payload);
    final key = _retryKeys.putIfAbsent('restore:$signature', requestId);
    if (_restoreKey != key) {
      _restoreTask = null;
      _restoreKey = key;
    }
    _restoreTask ??= (await call(
      'POST',
      '/api/v1/backup-restores',
      body: {'request_id': key, ...payload},
    ))['id'];
    final task = await waitTask(_restoreTask!);
    if (task['status'] != 'completed') {
      throw const LibraryFailure('恢复未完成，原管理数据已保留；可重试查询任务');
    }
    _videos.clear();
    await synchronize(api, _generation);
    _state = _state.copy(clearDelete: true);
    publish();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelVideoRead();
    cancelFolderRead();
    _scanRead.cancel();
    _api?.close();
    super.dispose();
  }
}
