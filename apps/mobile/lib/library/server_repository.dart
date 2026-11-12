import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import 'credentials.dart';
import 'file_command_store.dart';
import 'backup_work_store.dart';
import 'backup_document.dart';
import 'backup_file_picker.dart';
import 'management_archives.dart';
import 'server_backups.dart';
import 'models.dart';
import 'repository.dart';
import 'server_api.dart';
import 'scoped_journal.dart';

part 'server_pack_catalog.dart';
part 'server_pack_reading.dart';
part 'server_pack_trash.dart';
part 'server_pack_purge.dart';
part 'server_maintenance_tasks.dart';
part 'server_task_history.dart';
part 'server_purge_history.dart';
part 'server_playback_defaults.dart';
part 'server_pack_missing.dart';

typedef Json = Map<String, dynamic>;

Json object(Object? value) => Map<String, dynamic>.from(value as Map);
List<Json> rows(Json value) => (value['items'] as List).map(object).toList();

class _ScopedBackupWork implements BackupWorkStore {
  _ScopedBackupWork(this.book, this.scope);
  final ScopedJournal book;
  final String scope;
  @override
  Future<String?> read() => book.read(scope);
  @override
  Future<void> write(String value) => book.write(scope, value);
}

String requestId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

/// Server IDs remain authoritative; this cache contains only visited pages and
/// the small playback window. It is never used as a replacement NAS database.
class ServerLibraryRepository extends LibraryRepository
    with _ServerPackCatalog
    implements ManagementArchiveRepository {
  ServerLibraryRepository(
    this.credentials, {
    FileCommandStore? fileCommands,
    FileCommandStore? packCommands,
    BackupWorkStore? backupWork,
    Future<BackupFileStore> Function(String owner)? archiveFileStore,
    String address = '',
    int port = 8760,
  }) : fileCommands = fileCommands ?? MemoryFileCommandStore(),
       packFileJournal = PackFileJournal(
         packCommands ?? MemoryFileCommandStore(),
       ),
       _archiveFileStoreFactory =
           archiveFileStore ?? NativeBackupArchiveFiles.storeFor,
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
    _videoBook = ScopedJournal(
      readText: this.fileCommands.read,
      writeText: this.fileCommands.write,
    );
    _backupBook = ScopedJournal(
      readText: this.backupWork.read,
      writeText: this.backupWork.write,
    );
    libraryPreparation.value = const LibraryPreparation(ready: false);
    packFileJournal.onChanged = publish;
  }
  final Set<_ServerPackReader> _readers = {};
  final Set<_ServerPackTrash> _trashReaders = {};
  final Set<_ServerPackPurge> _purgeReaders = {};
  final Set<_ServerMaintenanceTasks> _taskReaders = {};
  final Set<_ServerPlaybackDefaults> _defaultsReaders = {};
  final Set<_ServerPackMissing> _missingReaders = {};
  int _readerEpoch = 0;
  RequestScope? _countsWork;
  int _countsRevision = 0;

  void _clearCatalogCounts() {
    _countsWork?.cancel();
    _countsWork = null;
    catalogCounts.value = null;
  }

  void _acceptCatalogCounts(
    Json? data,
    ServerApi target,
    int generation,
    int revision,
  ) {
    if (_disposed ||
        generation != _generation ||
        !identical(target, _api) ||
        revision != _countsRevision) {
      return;
    }
    catalogCounts.value = !capabilities.mediaCatalogCounts || data == null
        ? null
        : MediaCatalogCounts.fromLibraryState(data);
  }

  @override
  Future<void> refreshCatalogCounts() async {
    if (_disposed ||
        !snapshot.connected ||
        !capabilities.mediaCatalogCounts ||
        backupRestorePending ||
        _connectingGeneration != null) {
      return;
    }
    _countsWork?.cancel();
    final work = _countsWork = RequestScope();
    final target = api, generation = _generation, revision = ++_countsRevision;
    try {
      final data = await call(
        'GET',
        '/api/v1/library-state',
        using: target,
        cancel: work,
      );
      if (!work.cancelled) {
        _acceptCatalogCounts(data, target, generation, revision);
      }
    } on RequestCancelled {
      // A newer read or connection owns the result.
    } catch (_) {
      if (!work.cancelled) {
        _acceptCatalogCounts(null, target, generation, revision);
      }
    }
  }

  @override
  void packFilesChanged() {
    _countsRevision++;
    catalogCounts.value = null;
    super.packFilesChanged();
    unawaited(refreshCatalogCounts());
    if (snapshot.connected) schedulePreparation(api, _generation);
  }

  bool _reconcilingPackDeletes = false;
  Future<void> reconcilePackDeletes() async {
    if (_reconcilingPackDeletes ||
        _disposed ||
        !snapshot.connected ||
        !capabilities.packDirectoryDelete ||
        _fileScope == null ||
        backupRestorePending) {
      return;
    }
    _reconcilingPackDeletes = true;
    try {
      final files = createPackFiles();
      var changed = false;
      for (final command in await files.pending()) {
        if (!files.isCurrent()) return;
        if (command.kind != 'directory_delete' &&
            !(command.kind == 'retry' &&
                command.expectedTaskKind == 'pack_directory_delete')) {
          continue;
        }
        try {
          final task = await files.receipt(command);
          if (!files.isCurrent()) return;
          if (task?.settled == true && !task!.result!.needsAttention) {
            await files.acknowledgeTask(task);
            changed = true;
          }
        } catch (_) {
          // Retry the original receipt on the next normal refresh, never POST.
        }
      }
      if (changed && files.isCurrent()) packFilesChanged();
    } catch (_) {
      // Network interruptions stay internal while the original request is kept.
    } finally {
      _reconcilingPackDeletes = false;
    }
  }

  @override
  PackMissingCatalog createPackMissing() {
    ensureNotRestoring();
    if (!capabilities.packMissingCleanup || _fileScope == null) {
      throw const LibraryFailure('当前服务尚不支持图包缺失管理，请升级服务端');
    }
    final value = _ServerPackMissing(
      this,
      api,
      _generation,
      _readerEpoch,
      _fileScope!,
    );
    _missingReaders.add(value);
    return value;
  }

  @override
  PlaybackDefaultsGateway createPlaybackDefaults() {
    ensureNotRestoring();
    if (!capabilities.managedPlaybackDefaults || _fileScope == null) {
      throw const LibraryFailure('当前服务尚不支持服务端默认播放顺序，请升级服务端');
    }
    final value = _ServerPlaybackDefaults(
      this,
      api,
      _generation,
      _readerEpoch,
      _fileScope!,
    );
    _defaultsReaders.add(value);
    return value;
  }

  @override
  Future<PlayOrder> defaultVideoOrder(PlayOrder fallback) async {
    if (!capabilities.managedPlaybackDefaults) return fallback;
    final gateway = createPlaybackDefaults();
    try {
      return (await gateway.read()).order;
    } finally {
      gateway.dispose();
    }
  }

  @override
  PackRestorePlans createPackRestorePlans() {
    if (!capabilities.packRestorePlans || _fileScope == null) {
      throw const LibraryFailure('当前服务尚不支持整份恢复计划，请升级服务端');
    }
    final target = api, generation = _generation, epoch = _readerEpoch;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        epoch == _readerEpoch &&
        identical(target, _api);
    return PackRestorePlans(
      journal: packFileJournal,
      scope: _fileScope!,
      isCurrent: current,
      call: (method, path, {body}) async {
        if (!current()) throw const RequestCancelled();
        if (method != 'GET') ensureNotRestoring();
        final result = await call(method, path, using: target, body: body);
        if (!current()) throw const RequestCancelled();
        return result;
      },
    );
  }

  @override
  MaintenanceTaskCatalog createMaintenanceTasks() {
    if (!capabilities.maintenanceTasks || _fileScope == null) {
      throw const LibraryFailure('当前服务尚不支持操作任务，请升级服务端');
    }
    final reader = _ServerMaintenanceTasks(
      this,
      api,
      _generation,
      _readerEpoch,
      _fileScope!,
    );
    _taskReaders.add(reader);
    return reader;
  }

  @override
  PackPurgeGateway createPackPurge() {
    ensureNotRestoring();
    if (!capabilities.packPurgePreview ||
        !capabilities.packPermanentDelete ||
        !capabilities.packLogicalTrash ||
        !capabilities.imagePacks) {
      throw const LibraryFailure('当前服务尚不支持图包永久删除，请升级服务端');
    }
    final gateway = _ServerPackPurge(this, api, _generation, _readerEpoch);
    _purgeReaders.add(gateway);
    return gateway;
  }

  @override
  PackTrashCatalog createPackTrash() {
    ensureNotRestoring();
    if (!capabilities.packLogicalTrash || !capabilities.imagePacks) {
      throw const LibraryFailure('当前服务尚不支持图包回收站，请升级服务端');
    }
    final catalog = _ServerPackTrash(this, api, _generation, _readerEpoch);
    _trashReaders.add(catalog);
    return catalog;
  }

  @override
  PackReader createPackReader() {
    ensureNotRestoring();
    if (!capabilities.packReadingSessions || !capabilities.imagePacks) {
      throw const LibraryFailure('当前服务尚不支持图包阅读，请升级服务端');
    }
    final reader = _ServerPackReader(this, api, _generation, _readerEpoch);
    _readers.add(reader);
    return reader;
  }

  @override
  void _resetReaders() {
    _readerEpoch++;
    for (final reader in _missingReaders.toList()) {
      reader.dispose();
    }
    for (final reader in _defaultsReaders.toList()) {
      reader.dispose();
    }
    for (final reader in _taskReaders.toList()) {
      reader.dispose();
    }
    for (final gateway in _purgeReaders.toList()) {
      gateway.dispose();
    }
    for (final catalog in _trashReaders.toList()) {
      catalog.dispose();
    }
    for (final reader in _readers.toList()) {
      reader.dispose();
    }
  }

  final CredentialStore credentials;
  final FileCommandStore fileCommands;
  final PackFileJournal packFileJournal;
  @override
  PackFiles createPackFiles() {
    ensureNotRestoring();
    if (!capabilities.packLogicalTrash || _fileScope == null) {
      throw const LibraryFailure('当前服务尚不支持图包回收，请升级服务端');
    }
    final target = api, generation = _generation, epoch = _readerEpoch;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        epoch == _readerEpoch &&
        identical(target, _api);
    return PackFiles(
      journal: packFileJournal,
      scope: _fileScope!,
      isCurrent: current,
      call: (method, path, {body}) async {
        ensureNotRestoring();
        if (!current()) throw const RequestCancelled();
        final result = await call(method, path, using: target, body: body);
        if (!current()) throw const RequestCancelled();
        ensureNotRestoring();
        return result;
      },
    );
  }

  final BackupWorkStore backupWork;
  final Future<BackupFileStore> Function(String owner) _archiveFileStoreFactory;
  late final ScopedJournal _videoBook, _backupBook;
  Future<void>? _authorityRecovery;
  Future<void> get managementSynchronization =>
      _authorityRecovery ?? Future.value();
  bool _backupJournalError = false;
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
    if (_authorityRecovery != null || _connectingGeneration != null) {
      throw const LibraryFailure('正在读取当前媒体库，请稍后重新操作');
    }
    if (_packJournalError || _backupJournalError) {
      throw const LibraryFailure('本机操作日志无法读取，请先核对操作任务；原记录已保留');
    }
    if (backupRestorePending) throw const LibraryFailure('恢复结果尚未确认，请先查询结果');
  }

  Json _fileState = {};
  String? _fileScope;
  Future<void> _fileWrites = Future.value();
  @override
  bool get fileOperationPending => _fileState['pending'] != null;
  bool _packJournalError = false;
  @override
  int? get maintenancePendingCount {
    final scope = _fileScope;
    if (scope == null || _packJournalError) return null;
    final count = packFileJournal.cachedCount(scope);
    if (count == null) return null;
    try {
      return count +
          (fileOperationPending ? 1 : 0) +
          (_backups?.pendingReceipts.length ?? 0);
    } catch (_) {
      return null;
    }
  }

  @override
  bool get maintenanceNeedsCheck {
    if (_packJournalError || fileOperationPending || backupRestorePending) {
      return true;
    }
    try {
      return (maintenancePendingCount ?? 0) > 0 ||
          (_backups?.pendingReceipts.isNotEmpty ?? false);
    } catch (_) {
      return true;
    }
  }

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
  RequestScope _videoTagRead = RequestScope(),
      _videoSelection = RequestScope(),
      _packSelection = RequestScope(),
      _videoRead = RequestScope(),
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
  bool sameMediaConnection(MediaSource source, ServerApi target) =>
      source.headers['Authorization'] ==
          target.authorization['Authorization'] &&
      source.headers['X-Management-Epoch'] == target.managementEpoch;
  @override
  Future<String?> playbackFailure(MediaSource source) async {
    final target = _api;
    if (target == null || !sameMediaConnection(source, target)) {
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
        sameMediaConnection(source, _api!)) {
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

  Future<void> expire({String? message, bool clearCredentials = true}) async {
    _connectionError = message ?? '连接凭据已失效，请重新输入口令';
    _generation++;
    _clearCatalogCounts();
    cancelVideoRead();
    cancelFolderRead();
    cancelTrashRead();
    cancelMissingRead();
    cancelVideoTagRead();
    cancelVideoSelection();
    cancelPackSelection();
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
    _fileScope = null;
    _fileState = {};
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
    if (clearCredentials) await writeCredentials(credentials.clear);
  }

  String commandScope(ConnectionCredentials session) => jsonEncode([
    session.endpoint.toString(),
    session.serverId,
    if ((session.managementEpoch ?? session.localGeneration) != null)
      session.managementEpoch ?? session.localGeneration,
  ]);

  Future<ConnectionCredentials> currentCredentials(
    ConnectionCredentials session,
    ServerApi target, {
    ConnectionCredentials? previous,
    bool explicit = false,
  }) async {
    String? local;
    if (target.managementEpoch == null) {
      final same =
          previous != null &&
          previous.endpoint == session.endpoint &&
          previous.serverId == session.serverId;
      if (!explicit && same && previous.localGeneration != null) {
        local = previous.localGeneration;
      } else {
        var fresh = same && (explicit || previous.managementEpoch != null);
        if (!fresh) {
          final base = jsonEncode([
            session.endpoint.toString(),
            session.serverId,
          ]);
          try {
            final scopes = {
              ...(await _videoBook.entries(base)).keys,
              ...(await _backupBook.entries(base)).keys,
              ...await packFileJournal.serverScopes(base),
            };
            fresh = scopes.any((v) => !isLegacyScope(v));
          } catch (_) {
            fresh = true;
          }
        }
        if (fresh) {
          final random = Random.secure();
          local = List.generate(
            16,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
        }
      }
    }
    return ConnectionCredentials(
      endpoint: session.endpoint,
      token: session.token,
      serverId: session.serverId,
      expiresAt: session.expiresAt,
      managementEpoch: target.managementEpoch,
      localGeneration: local,
    );
  }

  void managementChanged(ServerApi target) {
    if (_disposed || !identical(target, _api) || _authorityRecovery != null) {
      return;
    }
    final work = recoverAuthority(target);
    _authorityRecovery = work;
    work.then(
      (_) {
        if (identical(_authorityRecovery, work)) {
          _authorityRecovery = null;
          publish();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_authorityRecovery, work)) {
          _authorityRecovery = null;
          publish();
        }
      },
    );
  }

  Future<void> recoverAuthority(ServerApi target) async {
    if (_disposed || !identical(target, _api)) throw const RequestCancelled();
    final invalidatedGeneration = _generation + 1;
    await expire(
      message: '管理数据已恢复，正在重新读取媒体库；旧操作保留在任务中心',
      clearCredentials: false,
    );
    var expected = invalidatedGeneration;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_disposed || expected != _generation) throw const RequestCancelled();
      final next = expected + 1;
      try {
        await initialize();
        return;
      } catch (error) {
        if (_disposed || _generation != next) throw const RequestCancelled();
        expected = next;
        if (error is ApiFailure &&
            error.code == 'management_changed' &&
            attempt < 2) {
          continue;
        }
        _connectionError = '管理数据已恢复，重新读取未完成；旧操作已保留，请重新连接';
        publish();
        rethrow;
      }
    }
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
    if (savedEndpoint != null) {
      rememberAddress(savedEndpoint);
      // The connection form must show the saved endpoint while network reads
      // are still pending, including when the NAS is offline or a token expires.
      publish();
    }
    final saved = await credentials.read();
    if (generation != _generation) throw const RequestCancelled();
    if (saved == null || !saved.expiresAt.isAfter(DateTime.now())) {
      if (saved != null) {
        await writeCredentials(credentials.clear, generation: generation);
      }
      publish();
      return;
    }
    if (savedEndpoint != saved.endpoint) {
      rememberAddress(saved.endpoint);
      publish();
    }
    final candidate = ServerApi(saved.endpoint, token: saved.token);
    _connectingGeneration = generation;
    try {
      final info = await candidate.json('GET', '/api/v1/info');
      if (info['api_version'] != 1 || info['server_id'] != saved.serverId) {
        await writeCredentials(credentials.clear, generation: generation);
        throw const LibraryFailure('服务实例或版本已变化，请重新连接');
      }
      candidate.bindAuthority(info);
      final session = await currentCredentials(
        saved,
        candidate,
        previous: saved,
      );
      await synchronize(
        candidate,
        generation,
        allowConnection: true,
        beforePublish: () => writeCredentials(
          () => credentials.save(session),
          generation: generation,
        ),
        capabilities: ServiceCapabilities.fromInfo(info),
      );
      await activateFileCommands(session);
      await activateBackupWork(session);
    } on ApiFailure catch (error) {
      if (error.status == 401 && generation == _generation) {
        await writeCredentials(credentials.clear, generation: generation);
      }
      rethrow;
    } finally {
      if (_connectingGeneration == generation) _connectingGeneration = null;
      if (identical(candidate, _api)) {
        schedulePreparation(candidate, generation);
      } else {
        candidate.close();
      }
    }
  }

  @override
  Future<bool> connectionNeedsSetup(String address, int port) async {
    final candidate = ServerApi(endpoint(address, port));
    try {
      final status = await candidate.json('GET', '/api/v1/auth/status');
      if (status['initialized'] is! bool) {
        throw const LibraryFailure('服务返回的初始化状态不完整');
      }
      return status['initialized'] == false;
    } on ApiFailure catch (error) {
      if (error.status == 404) {
        return false; // Older servers still accept login.
      }
      rethrow;
    } finally {
      candidate.close();
    }
  }

  @override
  Future<void> connect(String address, int port, String passphrase) =>
      _connect(address, port, passphrase);

  @override
  Future<void> setupConnection(String address, int port, String passphrase) =>
      _connect(address, port, passphrase, initialSetup: true);

  @override
  Future<void> changePassphrase(String current, String replacement) {
    if (!capabilities.credentialManagement) {
      throw const LibraryFailure('当前服务不支持修改口令，请升级服务端');
    }
    if (_connectingGeneration != null) {
      throw const LibraryFailure('连接正在更新，请稍后再修改口令');
    }
    return _connect(
      snapshot.address,
      snapshot.port,
      replacement,
      currentPassphrase: current,
      authorizationToken: api.token,
    );
  }

  Future<void> _connect(
    String address,
    int port,
    String passphrase, {
    bool initialSetup = false,
    String? currentPassphrase,
    String authorizationToken = '',
  }) async {
    final location = endpoint(address, port);
    if (passphrase.isEmpty || passphrase.length > 1024) {
      throw const LibraryFailure('请填写个人口令');
    }
    final candidate = ServerApi(location, token: authorizationToken);
    var generation = currentPassphrase == null ? ++_generation : _generation;
    _connectingGeneration = generation;
    try {
      Json login;
      try {
        login = await candidate.json(
          'POST',
          initialSetup
              ? '/api/v1/auth/setup'
              : currentPassphrase != null
              ? '/api/v1/auth/passphrase'
              : '/api/v1/auth/login',
          body: currentPassphrase != null
              ? {
                  'current_passphrase': currentPassphrase,
                  'new_passphrase': passphrase,
                }
              : {'passphrase': passphrase},
        );
      } on ApiFailure catch (error) {
        if ((!initialSetup && currentPassphrase == null) ||
            error.status != null) {
          rethrow;
        }
        // A lost reply may follow a committed credential change. Authenticate
        // with the new secret once; never blindly repeat setup or rotation.
        candidate.token = '';
        try {
          login = await candidate.json(
            'POST',
            '/api/v1/auth/login',
            body: {'passphrase': passphrase},
          );
        } catch (_) {
          throw error;
        }
      }
      if (currentPassphrase != null) {
        // A rejected old password must not invalidate current reader gateways.
        if (_disposed || generation != _generation) {
          throw const RequestCancelled();
        }
        generation = ++_generation;
        _connectingGeneration = generation;
      }
      candidate.token = login['access_token'] as String;
      final info = await candidate.json('GET', '/api/v1/info');
      if (info['api_version'] != 1) throw const LibraryFailure('服务版本不兼容');
      candidate.bindAuthority(info);
      final session = await currentCredentials(
        ConnectionCredentials(
          endpoint: location,
          token: candidate.token,
          serverId: info['server_id'] as String,
          managementEpoch: candidate.managementEpoch,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            ((login['expires_at'] as num) * 1000).round(),
            isUtc: true,
          ),
        ),
        candidate,
        previous: await credentials.read(),
        explicit: true,
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
      if (identical(candidate, _api)) {
        schedulePreparation(candidate, generation);
      } else {
        candidate.close();
      }
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
      seconds: (data['duration'] as num).floor(),
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

  @override
  void cancelVideoTagRead() => _videoTagRead.cancel();

  @override
  Future<CatalogPage<VideoTag>> loadVideoTags({
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    cancelVideoTagRead();
    final work = _videoTagRead = RequestScope();
    final target = api, generation = _generation;
    final page = await call(
      'GET',
      '/api/v1/tags',
      using: target,
      cancel: work,
      query: {'search': search, 'offset': '$offset', 'limit': '$limit'},
    );
    if (_disposed ||
        generation != _generation ||
        !identical(target, _api) ||
        work.cancelled) {
      throw const RequestCancelled();
    }
    final tags = rows(page)
        .map((tag) => VideoTag(tag['id'], tag['name'], tag['video_count']))
        .toList();
    // Names for selected labels may not exist in the legacy complete cache yet.
    for (final tag in tags) {
      _tagNames[tag.id] = tag.name;
      _tagCounts[tag.id] = tag.count;
    }
    return CatalogPage(
      items: tags,
      total: page['total'],
      offset: page['offset'],
      limit: page['limit'],
    );
  }

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
    if (_disposed || generation != _generation) throw const RequestCancelled();
    final scopeGeneration = _scopeGeneration;
    final countsRevision = ++_countsRevision;
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
      _clearCatalogCounts();
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
      cancelVideoTagRead();
      cancelVideoSelection();
      cancelPackSelection();
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
    target.onManagementChanged = () => managementChanged(target);
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
    _acceptCatalogCounts(response[4], target, generation, countsRevision);
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
    unawaited(reconcilePackDeletes());
    _preparationTimer = Timer(
      Duration(
        seconds:
            libraryPreparation.value.scanning ||
                !libraryPreparation.value.ready ||
                (_fileScope != null &&
                    packFileJournal.hasCachedCommands(_fileScope!))
            ? 2
            : 10,
      ),
      () => unawaited(pollPreparation(target, generation)),
    );
  }

  Future<void> pollPreparation(ServerApi target, int generation) async {
    _preparationRead.cancel();
    final work = _preparationRead = RequestScope();
    final countsRevision = _countsRevision + 1;
    bool valid() =>
        !_disposed &&
        !work.cancelled &&
        generation == _generation &&
        identical(target, _api);
    try {
      if (!valid() || backupRestorePending) return;
      _countsRevision = countsRevision;
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
      _acceptCatalogCounts(data, target, generation, countsRevision);
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
        _acceptCatalogCounts(null, target, generation, countsRevision);
        libraryPreparation.value = libraryPreparation.value.offline();
      }
    } finally {
      if (valid()) schedulePreparation(target, generation);
    }
  }

  @override
  Future<ScanReport> loadScanReport(
    String taskId, {
    RequestScope? cancel,
  }) async {
    final target = api, generation = _generation;
    final data = await call(
      'GET',
      '/api/v1/tasks/${Uri.encodeComponent(taskId)}',
      using: target,
      cancel: cancel,
    );
    if (_disposed ||
        generation != _generation ||
        !identical(target, _api) ||
        cancel?.cancelled == true) {
      throw const RequestCancelled();
    }
    final report = ScanReport(data);
    if (report.id != taskId) {
      throw const LibraryFailure('扫描记录不一致，请重新读取');
    }
    return report;
  }

  @override
  Future<void> requestScan() async {
    ensureNotRestoring();
    final target = api, generation = _generation;
    await call('POST', '/api/v1/scans', using: target);
    await pollPreparation(target, generation);
  }

  @override
  Future<void> requestRootScan(String rootId) async {
    ensureNotRestoring();
    if (!capabilities.scopedScans || !capabilities.rootScanProgress) {
      throw const LibraryFailure('当前服务不支持单独扫描目录，请升级服务端');
    }
    final target = api, generation = _generation;
    await call(
      'POST',
      '/api/v1/scans',
      using: target,
      body: {'root_id': rootId},
    );
    if (_disposed || generation != _generation || !identical(target, _api)) {
      throw const RequestCancelled();
    }
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

  Json _videoOrder(VideoSort sort) => {
    'sort': sort.name,
    if (sort == VideoSort.name && capabilities.videoNameOrder)
      'name_locale': 'zh-CN',
  };

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
          ..._videoOrder(entry.sort),
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
  void cancelVideoSelection() => _videoSelection.cancel();
  @override
  void cancelPackSelection() => _packSelection.cancel();

  Set<String> _selectionIds(Json response, MediaKind kind) {
    final values = response['ids'];
    if (response['kind'] != kind.name ||
        values is! List ||
        values.any((id) => id is! String || id.isEmpty)) {
      throw const LibraryFailure('服务未返回完整的选择范围，请重试');
    }
    final ids = values.cast<String>().toSet();
    if (ids.length != values.length || response['total'] != ids.length) {
      throw const LibraryFailure('服务返回的选择范围不完整，请重试');
    }
    return ids;
  }

  @override
  Future<Set<String>> selectVideoIds(VideoEntryScope entry) async {
    if (!capabilities.catalogSelection) {
      throw const LibraryFailure('当前服务尚不支持跨页全选，请升级服务端');
    }
    cancelVideoSelection();
    final work = _videoSelection = RequestScope();
    final target = api, generation = _generation;
    final filters = await scopeBody(entry.query, cancel: work);
    final result = await call(
      'GET',
      '/api/v1/videos/selection',
      using: target,
      cancel: work,
      query: {
        ...filters,
        'search': entry.search,
        'source': entry.source.name,
        ..._videoOrder(entry.sort),
      },
    );
    _packCurrent(target, generation, work);
    return _selectionIds(result, MediaKind.video);
  }

  @override
  Future<Set<String>> selectPackIds(PackQuery query) async {
    _packQuerySupported(query);
    if (!capabilities.catalogSelection) {
      throw const LibraryFailure('当前服务尚不支持跨页全选，请升级服务端');
    }
    cancelPackSelection();
    final work = _packSelection = RequestScope();
    final target = api, generation = _generation;
    final directory = query.folder.isEmpty
        ? null
        : await _packDirectoryId(query.folder, target, work);
    _packCurrent(target, generation, work);
    final result = await call(
      'GET',
      '/api/v1/packs/selection',
      using: target,
      cancel: work,
      query: {
        'search': query.search,
        'read_state': query.readState.name,
        'source': query.source.name,
        'sort': _packSort(query.sort),
        'directory_id': ?directory,
        if (query.tags.isNotEmpty) 'tag_ids': query.tags.toList()..sort(),
      },
    );
    _packCurrent(target, generation, work);
    return _selectionIds(result, MediaKind.pack);
  }

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
          ..._videoOrder(entry.sort),
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
            ..._videoOrder(entry.sort),
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
    final scope = next['scope'];
    if (scope is! String) throw const RequestCancelled();
    try {
      await _videoBook.write(scope, jsonEncode(next));
    } catch (_) {
      _packJournalError = true;
      publish();
      rethrow;
    }
    if (_fileScope == scope) _fileState = next;
  }

  Future<void> activateFileCommands(ConnectionCredentials session) =>
      serializeFiles(() async {
        final generation = _generation, target = _api;
        final scope = commandScope(session);
        if (generation != _generation ||
            !identical(target, _api) ||
            _api?.token != session.token) {
          throw const RequestCancelled();
        }
        _fileScope = scope;
        _fileState = {'scope': scope};
        try {
          final text = await _videoBook.read(scope);
          if (generation != _generation || !identical(target, _api)) {
            throw const RequestCancelled();
          }
          if (text != null) _fileState = object(jsonDecode(text));
          await packFileJournal.pending(scope);
          await packFileJournal.restorePending(scope);
          await packFileJournal.purgeSelections(scope);
          await packFileJournal.missingPending(scope);
          for (final previous in await packFileJournal.serverScopes(scope)) {
            if (previous != scope) {
              await packFileJournal.historicalPurgeSelections(previous);
              await packFileJournal.historicalMissing(previous);
            }
          }
          if (generation != _generation || !identical(target, _api)) {
            throw const RequestCancelled();
          }
          _packJournalError = false;
        } on RequestCancelled {
          rethrow;
        } catch (_) {
          _packJournalError = true;
        }
        final last = _fileState['lastDelete'];
        _state = _state.copy(
          clearDelete: last == null,
          lastDelete: last == null
              ? null
              : DeleteOperation.fromJson(object(last)),
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
      final fresh = old == null;
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
      return runFileCommand(target, generation, submit: fresh);
    });
  }

  @override
  Future<void> reconcileFileOperation() {
    return _reconcileFileReceipt(null);
  }

  Future<void> _reconcileFileReceipt(String? expectedRequestId) {
    final target = api, generation = _generation;
    return serializeFiles(() async {
      if (!fileOperationPending) return;
      if (expectedRequestId != null &&
          object(_fileState['pending'])['key'] != expectedRequestId) {
        return;
      }
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
        if (submit &&
            error.status != null &&
            error.status! >= 400 &&
            error.status! < 500 &&
            ![408, 429].contains(error.status)) {
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
          throw const LibraryFailure('原任务暂未找到，原记录已保留；未重复执行，请继续核对');
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
  }) => _writeTagChunks(
    ids,
    (chunk) => _writeTags('PATCH', '/api/v1/video-tags', {
      'video_ids': chunk,
      'tag_ids': tags.toList()..sort(),
      'mode': replace
          ? 'replace'
          : remove
          ? 'remove'
          : 'add',
    }),
  );

  @override
  Future<void> _writeTagChunks(
    Set<String> ids,
    Future<void> Function(List<String>) write,
  ) async {
    if (ids.isEmpty) return;
    final ordered = ids.toList()..sort();
    final target = api, generation = _generation;
    var confirmed = 0;
    try {
      while (confirmed < ordered.length) {
        _packCurrent(target, generation);
        ensureNotRestoring();
        final end = min(confirmed + 1000, ordered.length);
        await write(ordered.sublist(confirmed, end));
        _packCurrent(target, generation);
        confirmed = end;
      }
    } catch (failure) {
      if (ordered.length <= 1000) rethrow;
      throw LibraryFailure(
        '标签尚未全部确认，已确认 $confirmed/${ordered.length} 项。'
        '选择已保留，可重试；已提交部分不会重复追加。$failure',
      );
    }
  }

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
      ensureNotRestoring();
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
    final target = api, generation = _generation;
    if (!capabilities.typedRoots &&
        (root.kind != MediaKind.video || !root.enabled)) {
      throw const LibraryFailure('请升级服务端后使用图包目录或停用目录');
    }
    await call(
      root.id.isEmpty ? 'POST' : 'PUT',
      '/api/v1/roots${root.id.isEmpty ? '' : '/${root.id}'}',
      using: target,
      body: {
        'name': root.name,
        'path': root.path,
        if (capabilities.typedRoots) 'kind': root.kind.name,
        if (capabilities.typedRoots) 'enabled': root.enabled,
      },
    );
    await synchronize(target, generation);
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
      scope: commandScope(session),
      store: _ScopedBackupWork(_backupBook, commandScope(session)),
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
        final work = _authorityRecovery;
        if (work != null) {
          await work;
          return;
        }
        if (target.managementEpoch == null) {
          // A confirmed restore on a legacy service has no remote epoch.
          // Retire its whole local generation instead of erasing old receipts.
          final saved = await credentials.read();
          if (saved == null ||
              generation != _generation ||
              !identical(target, _api)) {
            throw const RequestCancelled();
          }
          final next = await currentCredentials(
            saved,
            target,
            previous: saved,
            explicit: true,
          );
          await writeCredentials(
            () => credentials.save(next),
            generation: generation,
          );
        }
        await recoverAuthority(target);
        _scanAfterRestore = !libraryPreparation.value.ready;
      },
    );
    _backups = client;
    try {
      await client.initialize();
      if (generation != _generation || !identical(_backups, client)) {
        throw const RequestCancelled();
      }
      _backupJournalError = false;
    } on RequestCancelled {
      rethrow;
    } catch (_) {
      _backupJournalError = true;
      rethrow;
    }
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
        if (!client.storageHealthy) _backupJournalError = true;
        backupStatus.value = error is LibraryFailure
            ? error.message
            : '操作未完成，原任务已保留，请查询原结果';
        if (error is ApiFailure && error.status == 401) await expire();
      }
      rethrow;
    }
  }

  @override
  bool get archiveBackupsAvailable => capabilities.backupV2;
  @override
  Future<ArchiveRestorePoint?> latestArchiveRestorePoint() =>
      backupAction((client) => client.latestRestorePoint());
  @override
  Future<ArchivePreview> inspectArchiveRestorePoint(
    ArchiveRestorePoint point,
  ) => backupAction((client) => client.inspectRestorePoint(point));
  @override
  bool get archivePreviewPending => _backups?.archivePreviewPending ?? false;
  @override
  Future<ArchivePreview> resumeArchivePreview() =>
      backupAction((client) => client.resumeDocumentPreview());
  @override
  int get archiveMaximumBytes =>
      capabilities.archiveMaximumBytes ??
      (throw const LibraryFailure('当前服务未开放完整管理备份，请升级服务端'));
  @override
  Future<BackupFileStore> archiveFileStore() async {
    if (!archiveBackupsAvailable || _fileScope == null) {
      throw const LibraryFailure('请先连接支持完整管理备份的服务');
    }
    final generation = _generation, owner = _fileScope!;
    final files = await _archiveFileStoreFactory(owner);
    if (_disposed || generation != _generation || _fileScope != owner) {
      throw const RequestCancelled();
    }
    if (files.owner != owner) throw const LibraryFailure('备份暂存与当前连接不一致');
    return files;
  }

  @override
  Future<ArchiveExport> exportArchive() async {
    final files = await archiveFileStore();
    return backupAction(
      (client) =>
          client.exportDocument(files, maximumBytes: archiveMaximumBytes),
    );
  }

  @override
  Future<void> archiveSaved(String identity) async {
    final files = await archiveFileStore();
    return backupAction(
      (client) => client.markExportSaved(identity, files: files),
    );
  }

  @override
  Future<ArchivePreview> inspectArchive(BackupDocument document) {
    if (!archiveBackupsAvailable || document.bytes > archiveMaximumBytes) {
      throw const LibraryFailure('所选备份超过当前服务允许大小，或服务尚不支持完整管理备份');
    }
    return backupAction((client) => client.inspectDocument(document));
  }

  @override
  Future<ArchiveRootPage> archiveRoots(
    ArchivePreview preview, {
    int offset = 0,
    int limit = 24,
  }) => backupAction(
    (client) => client.documentRoots(preview, offset: offset, limit: limit),
  );
  @override
  Future<void> restoreArchive(
    ArchivePreview preview,
    Map<String, String?> mappings,
  ) => backupAction((client) => client.restoreDocument(preview, mappings));

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
    _clearCatalogCounts();
    packFileJournal.onChanged = null;
    _preparationTimer?.cancel();
    _preparationRead.cancel();
    cancelVideoRead();
    cancelFolderRead();
    cancelTrashRead();
    cancelMissingRead();
    cancelVideoTagRead();
    cancelVideoSelection();
    cancelPackSelection();
    _resetPackConnection();
    _scanRead.cancel();
    _api?.close();
    _backups?.dispose();
    super.dispose();
  }
}
