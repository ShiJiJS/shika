import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'credentials.dart';
import 'file_command_store.dart';
import 'backup_work_store.dart';
import 'server_backups.dart';
import 'models.dart';
import 'repository.dart';
import 'server_api.dart';

part 'server_pack_catalog.dart';

typedef Json = Map<String, dynamic>;

Json object(Object? value) => Map<String, dynamic>.from(value as Map);
List<Json> rows(Json value) => (value['items'] as List).map(object).toList();
String requestId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

/// Server IDs remain authoritative; this cache contains only visited pages and
/// the small playback window. It is never used as a replacement NAS database.
class ServerLibraryRepository extends LibraryRepository
    with _ServerPackCatalog {
  ServerLibraryRepository(
    this.credentials, {
    FileCommandStore? fileCommands,
    BackupWorkStore? backupWork,
    String address = '10.0.2.2',
    int port = 8760,
  }) : fileCommands = fileCommands ?? MemoryFileCommandStore(),
       backupWork = backupWork ?? MemoryBackupWorkStore(),
       _state = LibrarySnapshot(
         videos: [],
         roots: [],
         tags: [],
         query: VideoQuery(),
         round: [],
         address: address,
         port: port,
         connected: false,
       ) {
    libraryPreparation.value = const LibraryPreparation(ready: false);
  }
  final CredentialStore credentials;
  final FileCommandStore fileCommands;
  final BackupWorkStore backupWork;
  ServiceCapabilities _capabilities = const ServiceCapabilities.legacy();
  @override
  ServiceCapabilities get capabilities => _capabilities;
  ServerBackups? _backups;
  @override
  bool get backupRestorePending => _backups?.restorePending ?? false;
  @override
  Object get connectionIdentity => _api ?? this;
  @override
  void ensureNotRestoring() {
    if (backupRestorePending) throw const LibraryFailure('恢复结果尚未确认，请先查询结果');
  }

  Json _fileState = {};
  String? _fileScope;
  Future<void> _fileWrites = Future.value();
  @override
  bool get fileOperationPending => _fileState['pending'] != null;
  LibrarySnapshot _state;
  ServerApi? _api;
  Json? _round;
  Json? _pendingRound;
  Json? _pendingOrder;
  String? _pendingOrderSignature;
  final Map<String, Future<void>> _openedWork = {};
  final Set<String> _opened = {};
  String? _pendingRoundSignature;
  final Map<String, LibraryVideo> _videos = {};
  final Map<String, FolderEntry> _directories = {};
  final Map<String, String> _tagNames = {}, _trashIds = {};
  final Map<String, int> _tagCounts = {};
  final Map<String, String> _retryKeys = {};
  final Map<String, String> _tagRetryKeys = {};
  Future<void> _tagWrites = Future.value();
  RequestScope _videoRead = RequestScope(),
      _folderRead = RequestScope(),
      _trashRead = RequestScope(),
      _missingRead = RequestScope(),
      _scanRead = RequestScope();
  Future<void>? _refreshWork;
  @override
  int _generation = 0;
  int _scopeGeneration = 0, _missing = 0, _trash = 0;
  @override
  bool _disposed = false;
  @override
  String _session = requestId();
  String? _scanTask;
  Timer? _preparationTimer;
  RequestScope _preparationRead = RequestScope();
  bool _scanAfterRestore = false;
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
  String get playbackIdentity => _round?['id'] as String? ?? '';
  @override
  bool get fixedPreview => _round?['membership'] == 'fixed';
  @override
  VideoEntryScope? get savedPreviewEntry => !fixedPreview
      ? null
      : VideoEntryScope(
          query: _state.query,
          search: (_round?['scope'] as Map?)?['search'] as String? ?? '',
          source: BrowseSource.values.byName(
            _round?['source'] as String? ?? 'library',
          ),
          sort: VideoSort.values.byName(_round?['sort'] as String? ?? 'path'),
        );
  @override
  String get playbackSequenceIdentity =>
      '$playbackIdentity:${_round?['sequence_revision'] ?? 0}';
  @override
  bool get previewFinished => _round?['finished'] == true;
  @override
  Future<VideoPage> loadPlaybackVideos({int offset = 0, int limit = 48}) async {
    final identity = playbackIdentity,
        sequence = playbackSequenceIdentity,
        generation = _generation;
    final target = api;
    final version = fixedPreview && capabilities.versionedVideoQueue
        ? _round!['sequence_revision'] as int? ?? 0
        : null;
    late Json page;
    try {
      page = await call(
        'GET',
        '/api/v1/rounds/$identity/entries',
        query: {
          'offset': '$offset',
          'limit': '$limit',
          if (version != null) 'v': '$version',
        },
        using: target,
      );
    } on ApiFailure catch (failure) {
      if (failure.code != 'round_order_changed') rethrow;
      if (generation == _generation &&
          identity == playbackIdentity &&
          sequence == playbackSequenceIdentity) {
        await synchronize(target, generation);
      }
      throw const RequestCancelled();
    }
    if (generation != _generation ||
        identity != playbackIdentity ||
        sequence != playbackSequenceIdentity ||
        _disposed) {
      throw const RequestCancelled();
    }
    return VideoPage(
      items: rows(page).map((row) => video(object(row['video']), target)),
      total: page['total'],
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<void> moveToVideo(String id) async {
    ensureNotRestoring();
    final target = api, generation = _generation, scope = _scopeGeneration;
    final round = await call(
      'PATCH',
      '/api/v1/rounds/$playbackIdentity/position',
      body: {'video_id': id, 'expected_revision': _round!['revision']},
      using: target,
    );
    await acceptRound(round, target, generation, scope);
  }

  @override
  LibraryVideo? get current =>
      _state.round.isEmpty ? null : _videos[_state.round[_state.position]];

  @override
  void publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  ServerApi get api => _api ?? (throw const LibraryFailure('请先连接视频库'));

  @override
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
    cancelTrashRead();
    cancelMissingRead();
    _resetPackConnection();
    _scanRead.cancel();
    _preparationTimer?.cancel();
    _preparationRead.cancel();
    _scanAfterRestore = false;
    libraryPreparation.value = const LibraryPreparation(ready: false);
    _api?.close();
    _api = null;
    _capabilities = const ServiceCapabilities.legacy();
    _backups?.dispose();
    _backups = null;
    backupStatus.value = null;
    _videos.clear();
    _directories.clear();
    _tagNames.clear();
    _tagCounts.clear();
    _trashIds.clear();
    _round = null;
    _pendingRound = null;
    _pendingRoundSignature = null;
    _tagRetryKeys.clear();
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
      await synchronize(
        candidate,
        generation,
        allowConnection: true,
        capabilities: ServiceCapabilities.fromInfo(info),
      );
      await activateFileCommands(saved);
      await activateBackupWork(saved);
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
        capabilities: ServiceCapabilities.fromInfo(info),
      );
      await activateFileCommands(session);
      await activateBackupWork(session);
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
      createdAt: (data['created_at'] as num?)?.toDouble() ?? 0,
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
    ServiceCapabilities? capabilities,
  }) async {
    final scopeGeneration = _scopeGeneration;
    final response = await Future.wait([
      call('GET', '/api/v1/roots', using: target),
      readCurrent(target, capabilities ?? _capabilities),
      call(
        'GET',
        '/api/v1/videos',
        query: {'status': 'missing', 'limit': '1'},
        using: target,
      ),
      call('GET', '/api/v1/trash', query: {'limit': '1'}, using: target),
      call('GET', '/api/v1/library-state', using: target),
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
        kind: root['kind'] == 'pack' ? MediaKind.pack : MediaKind.video,
        enabled: root['enabled'] as bool? ?? true,
        directoryId: root['directory_id'],
        error: root['error'],
        lastScan: date == null
            ? '等待首次扫描完成'
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
      _backups?.dispose();
      _backups = null;
      _pendingRound = null;
      _pendingRoundSignature = null;
      _pendingOrder = null;
      _pendingOrderSignature = null;
      _opened.clear();
      _openedWork.clear();
      _tagRetryKeys.clear();
      cancelVideoRead();
      cancelFolderRead();
      cancelTrashRead();
      cancelMissingRead();
      _resetPackConnection();
      _scanRead.cancel();
      _scanTask = null;
      _scanAfterRestore = false;
      scanStatus.value = null;
      _api?.close();
      _videos.clear();
      _directories.clear();
      _tagNames.clear();
      _trashIds.clear();
      _session = requestId();
    }
    _api = target;
    if (capabilities != null) _capabilities = capabilities;
    if (_round != null && _round!['id'] != round['id']) {
      ++_scopeGeneration;
      cancelVideoRead();
    }
    _connectionError = null;
    _tagNames
      ..clear()
      ..addEntries(
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
        available: root.available && root.enabled,
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
    _round = round['id'] is String ? round : null;
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
    libraryPreparation.value = LibraryPreparation.fromJson(
      response[4],
      ready: response[4]['ready'] == true && round['library_locked'] != true,
    );
    publish();
    schedulePreparation(target, generation);
  }

  Future<Json> readCurrent(
    ServerApi target,
    ServiceCapabilities capabilities,
  ) async {
    try {
      return await call(
        'GET',
        '/api/v1/playback',
        using: target,
        query: {if (capabilities.fixedVideoSessions) 'create': 'false'},
      );
    } on ApiFailure catch (error) {
      if (!capabilities.fixedVideoSessions ||
          error.code != 'round_not_started') {
        rethrow;
      }
      // Local disconnected-from-viewing state, not an invented server session.
      return {
        'id': null,
        'order': _state.order.name,
        'scope': <String, dynamic>{},
        'position': 0,
        'total': 0,
        'revision': 0,
        'finished': true,
        'current': null,
        'window': <dynamic>[],
      };
    }
  }

  void schedulePreparation(ServerApi target, int generation) {
    _preparationTimer?.cancel();
    if (_disposed || generation != _generation || !identical(target, _api)) {
      return;
    }
    _preparationTimer = Timer(
      Duration(
        seconds:
            libraryPreparation.value.scanning || !libraryPreparation.value.ready
            ? 2
            : 10,
      ),
      () => unawaited(pollPreparation(target, generation)),
    );
  }

  Future<void> pollPreparation(ServerApi target, int generation) async {
    _preparationRead.cancel();
    final work = _preparationRead = RequestScope();
    bool valid() =>
        !_disposed &&
        !work.cancelled &&
        generation == _generation &&
        identical(target, _api);
    try {
      if (!valid() || backupRestorePending) return;
      if (_scanAfterRestore) {
        await call('POST', '/api/v1/scans', using: target, cancel: work);
        if (!valid()) return;
        _scanAfterRestore = false;
      }
      final data = await call(
        'GET',
        '/api/v1/library-state',
        using: target,
        cancel: work,
      );
      if (!valid()) return;
      final previous = libraryPreparation.value;
      final next = LibraryPreparation.fromJson(data);
      // Keep playback locked until the matching, complete round is installed.
      final finished =
          !next.scanning &&
          (previous.scanning || previous.taskId != next.taskId);
      if ((!previous.ready && next.ready) || finished) {
        await synchronize(
          target,
          generation,
          beforePublish: () async {
            cancelVideoRead();
            cancelFolderRead();
            cancelMissingRead();
            _videos.clear();
            _directories.clear();
          },
        );
      } else {
        libraryPreparation.value = next;
      }
    } on RequestCancelled {
      // Another connection or restore owns this read.
    } catch (_) {
      if (valid()) {
        libraryPreparation.value = libraryPreparation.value.offline();
      }
    } finally {
      if (valid()) schedulePreparation(target, generation);
    }
  }

  @override
  Future<void> requestScan() async {
    ensureNotRestoring();
    final target = api, generation = _generation;
    await call('POST', '/api/v1/scans', using: target);
    await pollPreparation(target, generation);
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
              videoIsAvailable(item, _state.roots) &&
              (chosen.folder.isEmpty || under(item.path, chosen.folder)) &&
              item.tags.containsAll(chosen.tags) &&
              (chosen.orientation.isEmpty ||
                  (chosen.orientation == 'portrait') == item.portrait) &&
              (chosen.duration.isEmpty ||
                  (chosen.duration == 'short'
                      ? item.seconds <= 10
                      : item.seconds > 10)) &&
              (chosen.type.isEmpty || chosen.type == item.type) &&
              videoMatchesSearch(item, _state.roots, search),
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
  Future<VideoPage> restoreVideoEntry(
    VideoEntryScope entry, {
    required List<String> anchors,
    required int fallbackIndex,
    int limit = 24,
  }) {
    if (!capabilities.videoEntryAnchors) {
      throw const LibraryFailure('当前服务尚不支持返回位置恢复，请升级服务端');
    }
    return loadVideos(
      scope: entry.query,
      search: entry.search,
      offset: fallbackIndex,
      limit: limit,
      entry: entry,
      anchorIds: anchors,
    );
  }

  @override
  Future<VideoPage> loadVideoEntry(
    VideoEntryScope entry, {
    int offset = 0,
    int limit = 24,
  }) => loadVideos(
    scope: entry.query,
    search: entry.search,
    offset: offset,
    limit: limit,
    entry: entry,
  );

  @override
  Future<VideoPage> loadVideos({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 24,
    VideoEntryScope? entry,
    List<String> anchorIds = const [],
  }) async {
    if (entry != null &&
        !capabilities.fixedVideoSessions &&
        (entry.source != BrowseSource.library ||
            entry.sort != VideoSort.path)) {
      throw const LibraryFailure('当前服务尚不支持此入口，请升级服务端');
    }
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
        if (anchorIds.isNotEmpty) 'anchor_ids': anchorIds.take(16).toList(),
        if (search.isNotEmpty) 'search': search,
        if (entry != null && capabilities.fixedVideoSessions) ...{
          'source': entry.source.name,
          'sort': entry.sort.name,
        },
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
      offset: page['offset'] ?? offset,
      limit: limit,
      anchorIndex: page['anchor_index'],
    );
  }

  @override
  List<FolderEntry> folders(String parent) => parent.isEmpty
      ? _state.roots
            .where((root) => root.kind == MediaKind.video)
            .map(
              (root) => FolderEntry(
                root.name,
                root.path,
                id: root.directoryId,
                available: root.available && root.enabled,
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
        scopeGeneration != _scopeGeneration ||
        (_round?['id'] == round['id'] &&
            (_round?['revision'] as int? ?? 0) > (round['revision'] as int))) {
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
    VideoEntryScope? entry,
  }) {
    ensureNotRestoring();
    cancelVideoRead();
    final scopeGeneration = ++_scopeGeneration, generation = _generation;
    final target = api;
    final result = _roundWrites.then((_) async {
      if (scopeGeneration != _scopeGeneration || generation != _generation) {
        throw const RequestCancelled();
      }
      final resolved = await scopeBody(scope);
      if (entry != null && entry.search.isNotEmpty) {
        resolved['search'] = entry.search;
      }
      if (scopeGeneration != _scopeGeneration || generation != _generation) {
        throw const RequestCancelled();
      }
      final signature = jsonEncode({
        'order': order.name,
        'scope': resolved,
        'anchor': anchor,
        if (entry != null) ...{
          'membership': 'fixed',
          'source': entry.source.name,
          'sort': entry.sort.name,
        },
      });
      if (_pendingRoundSignature != signature) {
        _pendingRoundSignature = signature;
        _pendingRound = {
          'request_id': requestId(),
          'order': order.name,
          'scope': resolved,
          'anchor_video_id': ?anchor,
          if (entry != null) ...{
            'membership': 'fixed',
            'source': entry.source.name,
            'sort': entry.sort.name,
          },
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
  Future<void> newRound() => fixedPreview
      ? changePreviewOrder(_state.order, restart: true)
      : setScope(_state.query);
  @override
  Future<void> beginPreview(
    VideoEntryScope entry, {
    String? anchor,
    PlayOrder? order,
  }) {
    if (!supportsFixedPreviews) {
      throw const LibraryFailure('当前服务尚不支持固定预览范围，请升级服务端');
    }
    return changeRound(
      entry.query,
      order ?? _state.order,
      anchor: anchor,
      entry: entry,
    );
  }

  @override
  Future<void> changePreviewOrder(PlayOrder order, {bool restart = false}) {
    ensureNotRestoring();
    if (!fixedPreview) throw const LibraryFailure('请从媒体库选择范围开始预览');
    final target = api,
        generation = _generation,
        scope = _scopeGeneration,
        identity = playbackIdentity;
    final result = _roundWrites.then((_) async {
      if (_disposed ||
          generation != _generation ||
          scope != _scopeGeneration ||
          identity != playbackIdentity) {
        throw const RequestCancelled();
      }
      final signature = jsonEncode([
        identity,
        _round!['revision'],
        order.name,
        restart,
      ]);
      if (_pendingOrderSignature != signature) {
        _pendingOrderSignature = signature;
        _pendingOrder = {
          'request_id': requestId(),
          'expected_revision': _round!['revision'],
          'order': order.name,
          'restart': restart,
        };
      }
      final round = await call(
        'PATCH',
        '/api/v1/rounds/$identity/order',
        using: target,
        body: _pendingOrder,
      );
      await acceptRound(round, target, generation, scope);
      _pendingOrder = null;
      _pendingOrderSignature = null;
    });
    _roundWrites = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return result;
  }

  @override
  Future<void> recordVideoOpened(String id) {
    if (!fixedPreview || current?.id != id) {
      return Future.error(const RequestCancelled());
    }
    final target = api, generation = _generation, identity = playbackIdentity;
    final revision = _round!['revision'];
    final key = '$identity:$revision:$id';
    if (_opened.contains(key)) return Future.value();
    return _openedWork.putIfAbsent(key, () async {
      try {
        await call(
          'POST',
          '/api/v1/rounds/$identity/opened',
          using: target,
          body: {
            'request_id': 'opened-$key',
            'video_id': id,
            'expected_revision': revision,
          },
        );
        if (_disposed ||
            generation != _generation ||
            identity != playbackIdentity) {
          throw const RequestCancelled();
        }
        _opened.add(key);
        if (_opened.length > 256) _opened.remove(_opened.first);
      } finally {
        _openedWork.remove(key);
      }
    });
  }

  @override
  Future<void> finishPreview() async {
    if (!fixedPreview) return;
    final target = api,
        generation = _generation,
        scope = _scopeGeneration,
        identity = playbackIdentity;
    final round = await call(
      'PATCH',
      '/api/v1/rounds/$identity/position',
      using: target,
      body: {'expected_revision': _round!['revision'], 'finish': true},
    );
    await acceptRound(round, target, generation, scope);
  }

  @override
  Future<void> openVideo(String id) =>
      changeRound(_state.query, _state.order, anchor: id);

  @override
  Future<void> step(int delta) async {
    ensureNotRestoring();
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

  Future<T> serializeFiles<T>(Future<T> Function() action) {
    final result = _fileWrites.then((_) => action());
    _fileWrites = result.then<void>(
      (_) {},
      onError: (Object e, StackTrace s) {},
    );
    return result;
  }

  Future<void> saveFileState(Json next) async {
    await fileCommands.write(jsonEncode(next));
    _fileState = next;
  }

  Future<void> activateFileCommands(
    ConnectionCredentials session,
  ) => serializeFiles(() async {
    final scope = jsonEncode([session.endpoint.toString(), session.serverId]);
    final text = await fileCommands.read();
    if (_api?.token != session.token) throw const RequestCancelled();
    Json saved = {};
    if (text != null) {
      try {
        saved = object(jsonDecode(text));
      } catch (_) {
        /* Ignore invalid local receipts. */
      }
    }
    _fileScope = scope;
    _fileState = saved['scope'] == scope ? saved : {'scope': scope};
    final last = _fileState['lastDelete'];
    _state = _state.copy(
      clearDelete: last == null,
      lastDelete: last == null ? null : DeleteOperation.fromJson(object(last)),
    );
    publish();
  });

  Future<Json> operation(String path, Json body, {String? idempotency}) {
    ensureNotRestoring();
    final target = api, generation = _generation;
    return serializeFiles(() async {
      if (generation != _generation || !identical(target, _api)) {
        throw const RequestCancelled();
      }
      final old = _fileState['pending'];
      final signature = jsonEncode([path, body]);
      if (old != null && object(old)['signature'] != signature) {
        throw const LibraryFailure('上次文件操作的结果尚未确认，请先查询结果');
      }
      if (old == null) {
        await saveFileState({
          ..._fileState,
          'scope': _fileScope,
          'pending': {
            'path': path,
            'body': body,
            'signature': signature,
            'key': idempotency ?? requestId(),
            'before': {'round': _state.round, 'position': _state.position},
            'labels': {
              for (final v in _videos.values)
                if ((body['video_ids'] as List? ?? []).contains(v.id) ||
                    (body['trash_ids'] as List? ?? []).contains(
                      _trashIds[v.id],
                    ))
                  v.id: v.name,
            },
          },
        });
        publish();
      }
      return runFileCommand(target, generation, submit: true);
    });
  }

  @override
  Future<void> reconcileFileOperation() {
    final target = api, generation = _generation;
    return serializeFiles(() async {
      if (!fileOperationPending) return;
      final task = await runFileCommand(
        target,
        generation,
        submit: false,
        wait: false,
      );
      if (['queued', 'running'].contains(task['status'])) return;
      if (task['status'] != 'completed' ||
          object(task['result'])['partial'] == true) {
        throw LibraryFailure(failure(task));
      }
    });
  }

  Future<Json> runFileCommand(
    ServerApi target,
    int generation, {
    required bool submit,
    bool wait = true,
  }) async {
    void check() {
      if (_disposed || generation != _generation || !identical(target, _api)) {
        throw const RequestCancelled();
      }
    }

    check();
    var command = object(_fileState['pending']);
    if (command['task'] == null) {
      Json accepted;
      try {
        accepted = submit
            ? await call(
                'POST',
                command['path'],
                using: target,
                body: {
                  'request_id': command['key'],
                  ...object(command['body']),
                },
              )
            : await call(
                'GET',
                '/api/v1/file-requests/${command['key']}',
                using: target,
              );
      } on ApiFailure catch (error) {
        // Unknown response remains pending. Reopening only queries; it never
        // replays a destructive command into a restored or different database.
        if ((!submit && error.status == 404) ||
            (submit &&
                error.status != null &&
                error.status! >= 400 &&
                error.status! < 500 &&
                ![408, 429].contains(error.status))) {
          check();
          await saveFileState({..._fileState}..remove('pending'));
          fileStatus.value = null;
          publish();
        }
        rethrow;
      }
      check();
      command = {...command, 'task': accepted['id']};
      await saveFileState({..._fileState, 'pending': command});
    }
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    late Json task;
    while (true) {
      check();
      try {
        task = await call(
          'GET',
          '/api/v1/tasks/${command['task']}',
          using: target,
        );
      } on ApiFailure catch (error) {
        if (!submit && error.status == 404) {
          check();
          await saveFileState({..._fileState}..remove('pending'));
          fileStatus.value = null;
          publish();
          throw const LibraryFailure('原任务已不存在，请核对文件状态后重新操作；未重复执行');
        }
        rethrow;
      }
      check();
      final progress = object(task['result'] ?? {});
      final label = command['path'] == '/api/v1/trash/restore'
          ? '正在恢复'
          : '正在处理文件';
      fileStatus.value = progress['total'] == null
          ? label
          : '$label · ${progress['processed'] ?? 0} / ${progress['total']}';
      if (['completed', 'failed', 'interrupted'].contains(task['status'])) {
        break;
      }
      if (!wait) return task;
      if (DateTime.now().isAfter(deadline)) {
        throw const LibraryFailure('服务仍在处理文件，可稍后查询结果');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    check();
    if (task['status'] == 'interrupted') {
      throw const LibraryFailure('文件操作已中断，服务恢复后可查询结果');
    }
    await synchronize(
      target,
      generation,
      beforePublish: () async {
        cancelVideoRead();
        _videos.clear();
      },
    );
    check();
    final result = object(task['result']);
    final next = {..._fileState}..remove('pending');
    if (command['path'] == '/api/v1/videos/trash' &&
        (result['succeeded'] as int? ?? 0) > 0) {
      final before = object(command['before']);
      final successful = (result['items'] as List)
          .map(object)
          .where((item) => item['outcome'] == 'succeeded')
          .map((item) => item['video_id'] as String);
      next['lastDelete'] = DeleteOperation(
        task['id'],
        successful,
        List<String>.from(before['round']),
        before['position'],
      ).toJson();
    } else if ((command['path'] as String).endsWith('/undo') &&
        task['status'] == 'completed' &&
        result['partial'] != true) {
      next.remove('lastDelete');
    }
    await saveFileState(next);
    final last = next['lastDelete'];
    _state = _state.copy(
      clearDelete: last == null,
      lastDelete: last == null ? null : DeleteOperation.fromJson(object(last)),
    );
    publish();
    fileStatus.value = null;
    return {...task, '_labels': command['labels']};
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
      'item_not_found': '文件记录已变化，请刷新回收站',
      'operation_busy': '该视频的文件操作仍在处理中',
      'video_unavailable': '视频当前不可用，未删除',
      'restore_outside_library': '原目录已调整，请先重新接入后恢复',
    };
    if (problems.isEmpty) return '操作未完成，请刷新后重试';
    return problems
        .map((item) {
          final label = (task['_labels'] as Map?)?[item['video_id']];
          return '${label == null ? '' : '$label：'}${messages[item['error']] ?? '文件操作未完成，请刷新后重试'}';
        })
        .toSet()
        .join('\n');
  }

  @override
  Future<void> setVideoTags(
    Set<String> ids,
    Set<String> tags, {
    bool remove = false,
    bool replace = false,
  }) => _writeTags('PATCH', '/api/v1/video-tags', {
    'video_ids': ids.toList()..sort(),
    'tag_ids': tags.toList()..sort(),
    'mode': replace
        ? 'replace'
        : remove
        ? 'remove'
        : 'add',
  });

  @override
  Future<void> editTag({String? original, String? name, bool delete = false}) =>
      _writeTags(
        delete
            ? 'DELETE'
            : original == null
            ? 'POST'
            : 'PATCH',
        '/api/v1/tags${original == null ? '' : '/$original'}',
        {if (!delete) 'name': name?.trim()},
      );

  Future<void> _writeTags(String method, String path, Json payload) {
    ensureNotRestoring();
    final generation = _generation, target = api;
    final signature = jsonEncode([method, path, payload]);
    final result = _tagWrites.then((_) async {
      if (_disposed || generation != _generation || !identical(target, _api)) {
        throw const RequestCancelled();
      }
      final key = _tagRetryKeys.putIfAbsent(signature, requestId);
      var accepted = false;
      try {
        await call(
          method,
          path,
          using: target,
          body: {'request_id': key, ...payload},
        );
        accepted = true;
        await synchronize(
          target,
          generation,
          beforePublish: () async {
            cancelVideoRead();
            _videos.clear();
          },
        );
        _tagRetryKeys.remove(signature);
      } on ApiFailure catch (error) {
        final status = error.status;
        if (!accepted &&
            status != null &&
            status >= 400 &&
            status < 500 &&
            status != 408 &&
            status != 429) {
          _tagRetryKeys.remove(signature);
        }
        rethrow;
      }
    });
    _tagWrites = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  Future<void> deleteVideos(
    Set<String> ids, {
    required String requestId,
  }) async {
    final task = await operation('/api/v1/videos/trash', {
      'video_ids': ids.toList()..sort(),
    }, idempotency: requestId);
    final result = object(task['result']);
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
    _retryKeys.remove('undo:$operationId');
    if (task['status'] != 'completed' ||
        object(task['result'])['partial'] == true) {
      throw LibraryFailure(failure(task));
    }
  }

  @override
  Future<List<String>> restoreVideos(Set<String> ids) async {
    if (ids.length > 1000) {
      final all = ids.toList(), failures = <String>[];
      for (var i = 0; i < all.length; i += 1000) {
        failures.addAll(await restoreVideos(all.skip(i).take(1000).toSet()));
      }
      return failures;
    }
    final task = await operation('/api/v1/trash/restore', {
      'trash_ids': trashIds(ids),
    });
    return (object(task['result'])['items'] as List? ?? [])
        .map(object)
        .where((item) => item['outcome'] != 'succeeded')
        .map(
          (item) => failure({
            '_labels': task['_labels'],
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
      'trash_ids': trashIds(ids),
      'confirmed': true,
    });
    if (task['status'] != 'completed' ||
        object(task['result'])['partial'] == true) {
      throw LibraryFailure(failure(task));
    }
  }

  @override
  Future<int> forgetMissingVideos() async {
    ensureNotRestoring();
    final target = api, generation = _generation;
    final key = _retryKeys.putIfAbsent('forget-missing', requestId);
    final result = await call(
      'POST',
      '/api/v1/videos/forget-missing',
      body: {'request_id': key, 'confirmed': true},
      using: target,
    );
    await synchronize(
      target,
      generation,
      beforePublish: () async {
        cancelMissingRead();
        _videos.removeWhere((id, video) => video.status == VideoStatus.missing);
      },
    );
    _retryKeys.remove('forget-missing');
    return result['removed'] as int;
  }

  List<String> trashIds(Set<String> ids) {
    if (ids.isEmpty || ids.any((id) => !_trashIds.containsKey(id))) {
      throw const LibraryFailure('回收站记录已变化，请刷新后重新选择');
    }
    return ids.map((id) => _trashIds[id]!).toList()..sort();
  }

  @override
  Future<VideoPage> loadTrash({int offset = 0, int limit = 24}) async {
    cancelTrashRead();
    final work = _trashRead = RequestScope();
    final target = api, generation = _generation;
    final page = await call(
      'GET',
      '/api/v1/trash',
      query: {'offset': '$offset', 'limit': '$limit'},
      using: target,
      cancel: work,
    );
    if (generation != _generation ||
        !identical(target, _api) ||
        work.cancelled) {
      throw const RequestCancelled();
    }
    final items = <LibraryVideo>[];
    if (offset == 0) _trashIds.clear();
    for (final row in rows(page)) {
      final item = video(
        object(row['video']),
        target,
        status: VideoStatus.trash,
        originalPath: row['original_path'],
      );
      _trashIds[item.id] = row['id'];
      _videos[item.id] = item;
      items.add(item);
    }
    _trash = page['total'];
    _state = _state.copy(videos: _videos.values);
    return VideoPage(
      items: items,
      total: page['total'],
      offset: offset,
      limit: limit,
    );
  }

  @override
  void cancelTrashRead() => _trashRead.cancel();

  @override
  void cancelMissingRead() => _missingRead.cancel();

  @override
  Future<VideoPage> loadMissing({int offset = 0, int limit = 24}) async {
    cancelMissingRead();
    final work = _missingRead = RequestScope();
    final target = api, generation = _generation;
    final page = await call(
      'GET',
      '/api/v1/videos',
      query: {'status': 'missing', 'offset': '$offset', 'limit': '$limit'},
      using: target,
      cancel: work,
    );
    if (generation != _generation ||
        !identical(target, _api) ||
        work.cancelled) {
      throw const RequestCancelled();
    }
    final items = rows(page).map((row) => video(row, target)).toList();
    for (final item in items) {
      _videos[item.id] = item;
    }
    _missing = page['total'];
    _state = _state.copy(videos: _videos.values);
    return VideoPage(
      items: items,
      total: page['total'],
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<void> saveRoot(MediaRoot root) async {
    ensureNotRestoring();
    if (!capabilities.typedRoots &&
        (root.kind != MediaKind.video || !root.enabled)) {
      throw const LibraryFailure('请升级服务端后使用图包目录或停用目录');
    }
    await call(
      root.id.isEmpty ? 'POST' : 'PUT',
      '/api/v1/roots${root.id.isEmpty ? '' : '/${root.id}'}',
      body: {
        'name': root.name,
        'path': root.path,
        if (capabilities.typedRoots) 'kind': root.kind.name,
        if (capabilities.typedRoots) 'enabled': root.enabled,
      },
    );
    await synchronize(api, _generation);
  }

  @override
  Future<void> refresh() {
    ensureNotRestoring();
    final existing = _refreshWork;
    if (existing != null) return existing;
    final work = scan();
    _refreshWork = work;
    void finished() {
      if (identical(_refreshWork, work)) _refreshWork = null;
    }

    work.then(
      (_) => finished(),
      onError: (Object e, StackTrace s) => finished(),
    );
    return work;
  }

  Future<void> scan() async {
    _scanRead.cancel();
    final work = _scanRead = RequestScope();
    final target = api, generation = _generation;
    void check() {
      if (_disposed ||
          work.cancelled ||
          generation != _generation ||
          !identical(target, _api)) {
        throw const RequestCancelled();
      }
    }

    final phases = {
      'queued': '扫描排队中',
      'discovering': '正在查找视频',
      'waiting_for_stable_files': '等待文件写入稳定',
      'processing_media': '正在读取视频信息',
      'reconciling_identities': '正在核对文件身份',
      'completed': '扫描完成',
      'failed': '扫描失败',
      'interrupted': '扫描已中断',
    };
    try {
      scanStatus.value = '正在扫描媒体目录…';
      _scanTask ??= (await call(
        'POST',
        '/api/v1/scans',
        using: target,
        cancel: work,
      ))['id'];
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      late Json task;
      while (true) {
        check();
        task = await call(
          'GET',
          '/api/v1/tasks/$_scanTask',
          using: target,
          cancel: work,
        );
        check();
        final counts = object(task['result']);
        final checked =
            (counts['imported'] as int? ?? 0) +
            (counts['unchanged'] as int? ?? 0);
        scanStatus.value =
            '${phases[task['phase']] ?? '正在扫描'} · 已核对 $checked 个视频';
        if (['completed', 'failed', 'interrupted'].contains(task['status'])) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw const LibraryFailure('扫描仍在服务端进行，可稍后刷新查询进度');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final counts = object(task['result']);
      _scanTask = null;
      await synchronize(
        target,
        generation,
        beforePublish: () async {
          cancelVideoRead();
          cancelFolderRead();
          cancelMissingRead();
          _videos.clear();
          _directories.clear();
        },
      );
      check();
      if (task['status'] != 'completed') {
        throw const LibraryFailure('扫描未完成，原有标签记录保留，请重试');
      }
      final roots = (counts['roots'] as List? ?? [])
          .map(object)
          .where((r) => r['status'] != 'completed')
          .length;
      final failed = counts['failed'] as int? ?? 0;
      if (roots > 0 || failed > 0) {
        throw LibraryFailure('扫描结束：$roots 个目录不可用，$failed 个文件未能读取；原记录和标签保留');
      }
      scanStatus.value =
          '扫描完成 · 新增 ${counts['imported'] ?? 0} · 缺失 ${counts['missing'] ?? 0} · 等待稳定 ${counts['deferred'] ?? 0}';
    } on RequestCancelled {
      rethrow;
    } catch (error) {
      if (!_disposed && generation == _generation && !work.cancelled) {
        if (error is ApiFailure && error.status == 404) _scanTask = null;
        scanStatus.value = error.toString();
      }
      rethrow;
    }
  }

  Future<void> activateBackupWork(ConnectionCredentials session) async {
    final target = api, generation = _generation;
    _backups?.dispose();
    late final ServerBackups client;
    client = ServerBackups(
      api: target,
      scope: jsonEncode([session.endpoint.toString(), session.serverId]),
      store: backupWork,
      status: backupStatus,
      onChanged: () {
        if (!_disposed &&
            generation == _generation &&
            identical(_backups, client)) {
          publish();
        }
      },
      onRestored: () async {
        if (_disposed ||
            generation != _generation ||
            !identical(target, _api)) {
          throw const RequestCancelled();
        }
        await serializeFiles(() => saveFileState({'scope': _fileScope}));
        _scanRead.cancel();
        _scanTask = null;
        scanStatus.value = null;
        await synchronize(
          target,
          generation,
          beforePublish: () async {
            cancelVideoRead();
            cancelFolderRead();
            cancelTrashRead();
            cancelMissingRead();
            _videos.clear();
            _directories.clear();
            _trashIds.clear();
            _retryKeys.clear();
            _tagRetryKeys.clear();
            _pendingRound = null;
            _pendingRoundSignature = null;
            _session = requestId();
            _state = _state.copy(clearDelete: true);
          },
        );
        _scanAfterRestore = !libraryPreparation.value.ready;
      },
    );
    _backups = client;
    await client.initialize();
  }

  Future<T> backupAction<T>(
    Future<T> Function(ServerBackups client) action,
  ) async {
    final client = _backups;
    if (client == null) throw const LibraryFailure('请先连接视频库');
    final generation = _generation;
    try {
      return await action(client);
    } catch (error) {
      if (!_disposed &&
          generation == _generation &&
          identical(_backups, client)) {
        backupStatus.value = error.toString();
        if (error is ApiFailure && error.status == 401) await expire();
      }
      rethrow;
    }
  }

  @override
  Future<String> exportBackupFile() =>
      backupAction((client) => client.export());
  @override
  Future<BackupPreview> inspectBackupFile(String text) =>
      backupAction((client) => client.inspect(text));
  @override
  Future<void> restoreBackup(String text, Map<String, String> rootMappings) =>
      backupAction((client) => client.restore(text, rootMappings));
  @override
  Future<void> reconcileBackupRestore() =>
      backupAction((client) => client.reconcile());

  @override
  void dispose() {
    _disposed = true;
    _preparationTimer?.cancel();
    _preparationRead.cancel();
    cancelVideoRead();
    cancelFolderRead();
    cancelTrashRead();
    cancelMissingRead();
    _resetPackConnection();
    _scanRead.cancel();
    _api?.close();
    _backups?.dispose();
    super.dispose();
  }
}
