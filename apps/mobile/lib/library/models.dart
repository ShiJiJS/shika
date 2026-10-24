import 'dart:convert';

enum MediaKind { video, pack }

enum BrowseSource { library, tags, recent }

enum VideoSort { path, name, newest, recent }

/// Missing capabilities mean the original video-only protocol.
class ServiceCapabilities {
  const ServiceCapabilities.legacy() : values = const {};
  ServiceCapabilities(Iterable<String> values)
    : values = Set.unmodifiable(values);
  factory ServiceCapabilities.fromInfo(Map<String, dynamic> info) =>
      ServiceCapabilities(
        (info['capabilities'] as List? ?? const []).whereType<String>(),
      );
  final Set<String> values;
  bool get typedRoots => values.contains('typed_roots');
  bool get packTags => values.contains('pack_tags');
  bool get imagePacks => values.contains('image_packs');
  bool get fixedVideoSessions => values.contains('fixed_video_sessions');
  bool get versionedVideoQueue => values.contains('versioned_video_queue');
  bool get videoEntryAnchors => values.contains('video_entry_anchors');
  bool get catalogSelection => values.contains('catalog_selection');
  bool get packTagNames => values.contains('pack_tag_names');
  bool get packReadingSessions => values.contains('pack_reading_sessions');
  bool get packEntryAnchors => values.contains('pack_entry_anchors');
  bool get packLogicalTrash => values.contains('pack_logical_trash');
}

enum VideoStatus { available, missing, trash }

enum PlayOrder { random, sequential }

enum DemoScenario {
  normal,
  empty,
  offline,
  unavailable,
  writeFailure,
  storageFailure,
  conflict,
  changedFiles,
  identityConflict,
}

class LibraryFailure implements Exception {
  const LibraryFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class RequestCancelled implements Exception {
  const RequestCancelled();
  @override
  String toString() => '请求已取消';
}

bool under(String path, String parent) =>
    path == parent || path.startsWith('$parent/');
String basename(String path) => path.split('/').last;

class MediaSource {
  const MediaSource(
    this.location, {
    this.asset = true,
    this.headers = const {},
  });
  final String location;
  final bool asset;
  final Map<String, String> headers;
  Map<String, dynamic> toJson() => {'location': location, 'asset': asset};
  factory MediaSource.fromJson(Map<String, dynamic> j) => MediaSource(
    j['location'] as String,
    asset: j['asset'] as bool,
    headers: Map<String, String>.from(j['headers'] as Map? ?? {}),
  );
}

/// A label in the video namespace, with an authoritative catalog count.
class VideoTag {
  const VideoTag(this.id, this.name, this.count);
  final String id, name;
  final int count;
}

class LibraryVideo {
  LibraryVideo({
    required this.id,
    required this.path,
    required this.rootId,
    required this.portrait,
    required this.source,
    required this.poster,
    Iterable<String> tags = const [],
    this.seconds = 5,
    this.type = 'MP4',
    this.status = VideoStatus.available,
    this.originalPath,
    this.createdAt = 0,
  }) : tags = Set.unmodifiable(tags);
  final String id, path, rootId, poster, type;
  final bool portrait;
  final int seconds;
  final MediaSource source;
  final Set<String> tags;
  final VideoStatus status;
  final String? originalPath;
  final double createdAt;
  String get name => basename(path);
  LibraryVideo copy({
    String? path,
    Set<String>? tags,
    VideoStatus? status,
    String? originalPath,
  }) => LibraryVideo(
    id: id,
    path: path ?? this.path,
    rootId: rootId,
    portrait: portrait,
    source: source,
    poster: poster,
    tags: tags ?? this.tags,
    seconds: seconds,
    type: type,
    status: status ?? this.status,
    originalPath: originalPath ?? this.originalPath,
    createdAt: createdAt,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'rootId': rootId,
    'portrait': portrait,
    'source': source.toJson(),
    'poster': poster,
    'tags': tags.toList(),
    'seconds': seconds,
    'type': type,
    'status': status.name,
    'originalPath': originalPath,
    'createdAt': createdAt,
  };
  factory LibraryVideo.fromJson(Map<String, dynamic> j) => LibraryVideo(
    id: j['id'],
    path: j['path'],
    rootId: j['rootId'],
    portrait: j['portrait'],
    source: MediaSource.fromJson(Map<String, dynamic>.from(j['source'])),
    poster: j['poster'],
    tags: List<String>.from(j['tags']),
    seconds: j['seconds'],
    type: j['type'],
    status: VideoStatus.values.byName(j['status']),
    originalPath: j['originalPath'],
    createdAt: (j['createdAt'] as num?)?.toDouble() ?? 0,
  );
}

class MediaRoot {
  const MediaRoot(
    this.id,
    this.name,
    this.path, {
    this.available = true,
    this.kind = MediaKind.video,
    this.enabled = true,
    this.lastScan = '今天 09:20',
    this.directoryId = '',
    this.error,
  });
  final String id, name, path, lastScan, directoryId;
  final String? error;
  final bool available, enabled;
  final MediaKind kind;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'available': available,
    'kind': kind.name,
    'enabled': enabled,
    'lastScan': lastScan,
    'directoryId': directoryId,
    'error': error,
  };
  factory MediaRoot.fromJson(Map<String, dynamic> j) => MediaRoot(
    j['id'],
    j['name'],
    j['path'],
    available: j['available'],
    kind: j['kind'] == 'pack' ? MediaKind.pack : MediaKind.video,
    enabled: j['enabled'] as bool? ?? true,
    lastScan: j['lastScan'],
    directoryId: j['directoryId'] ?? '',
    error: j['error'],
  );
}

enum PackReadState { all, unread, reading, completed }

enum PackSort { name, newest, recent }

/// Pack-only filters cannot accidentally carry video orientation/duration.
class PackQuery {
  PackQuery({
    this.folder = '',
    Iterable<String> tags = const [],
    this.search = '',
    this.readState = PackReadState.all,
    this.source = BrowseSource.library,
    PackSort? sort,
  }) : sort =
           sort ??
           (source == BrowseSource.recent ? PackSort.recent : PackSort.name),
       tags = Set.unmodifiable(tags) {
    if (this.sort == PackSort.recent && source != BrowseSource.recent) {
      throw ArgumentError('最近排序仅适用于最近图包');
    }
  }
  final BrowseSource source;
  final String folder, search;
  final Set<String> tags;
  final PackReadState readState;
  final PackSort sort;
  int get count =>
      tags.length +
      (folder.isEmpty ? 0 : 1) +
      (readState == PackReadState.all ? 0 : 1);
  Map<String, dynamic> toJson() => {
    'folder': folder,
    'tag_ids': tags.toList()..sort(),
    'search': search,
    'read_state': readState.name,
    'source': source.name,
    'sort': sort.name,
  };
  String get queryKey => jsonEncode(toJson());
  PackQuery copy({
    String? folder,
    Set<String>? tags,
    String? search,
    PackReadState? readState,
    PackSort? sort,
    BrowseSource? source,
  }) => PackQuery(
    folder: folder ?? this.folder,
    tags: tags ?? this.tags,
    search: search ?? this.search,
    readState: readState ?? this.readState,
    source: source ?? this.source,
    sort:
        sort ??
        (source != null &&
                source != this.source &&
                (source == BrowseSource.recent || this.sort == PackSort.recent)
            ? null
            : this.sort),
  );
}

class VideoQuery {
  VideoQuery({
    this.folder = '',
    Iterable<String> tags = const [],
    this.orientation = '',
    this.duration = '',
    this.type = '',
  }) : tags = Set.unmodifiable(tags);
  final String folder, orientation, duration, type;
  final Set<String> tags;
  int get count =>
      tags.length +
      [folder, orientation, duration, type].where((s) => s.isNotEmpty).length;
  VideoQuery copy({
    String? folder,
    Set<String>? tags,
    String? orientation,
    String? duration,
    String? type,
  }) => VideoQuery(
    folder: folder ?? this.folder,
    tags: tags ?? this.tags,
    orientation: orientation ?? this.orientation,
    duration: duration ?? this.duration,
    type: type ?? this.type,
  );
  Map<String, dynamic> toJson() => {
    'folder': folder,
    'tags': tags.toList(),
    'orientation': orientation,
    'duration': duration,
    'type': type,
  };
  factory VideoQuery.fromJson(Map<String, dynamic> j) => VideoQuery(
    folder: j['folder'],
    tags: List<String>.from(j['tags']),
    orientation: j['orientation'],
    duration: j['duration'],
    type: j['type'],
  );
}

/// The complete entry selection; loading it never starts a viewing session.
class VideoEntryScope {
  VideoEntryScope({
    VideoQuery? query,
    this.search = '',
    this.source = BrowseSource.library,
    this.sort = VideoSort.path,
  }) : query = query ?? VideoQuery();
  final VideoQuery query;
  final String search;
  final BrowseSource source;
  final VideoSort sort;
  Map<String, dynamic> toJson() => {
    'query': query.toJson(),
    'search': search,
    'source': source.name,
    'sort': sort.name,
  };
  factory VideoEntryScope.fromJson(Map<String, dynamic> j) => VideoEntryScope(
    query: VideoQuery.fromJson(Map<String, dynamic>.from(j['query'])),
    search: j['search'] as String? ?? '',
    source: BrowseSource.values.byName(j['source'] as String? ?? 'library'),
    sort: VideoSort.values.byName(j['sort'] as String? ?? 'path'),
  );
}

/// Demo persistence mirrors the server's baseline and current member ordering.
class VideoPreviewData {
  VideoPreviewData({
    required this.id,
    required this.entry,
    required Iterable<String> sequence,
    Iterable<String>? ordered,
    this.finished = false,
    this.ordering = 0,
  }) : sequence = List.unmodifiable(sequence),
       ordered = List.unmodifiable(ordered ?? sequence);
  final String id;
  final VideoEntryScope entry;
  final List<String> sequence, ordered;
  final bool finished;
  final int ordering;
  VideoPreviewData withOrder(
    Iterable<String> ids, {
    bool finished = false,
    bool reordered = true,
  }) => VideoPreviewData(
    id: id,
    entry: entry,
    sequence: sequence,
    ordered: ids,
    finished: finished,
    ordering: ordering + (reordered ? 1 : 0),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'entry': entry.toJson(),
    'sequence': sequence,
    'ordered': ordered,
    'finished': finished,
    'ordering': ordering,
  };
  factory VideoPreviewData.fromJson(Map<String, dynamic> j) => VideoPreviewData(
    id: j['id'],
    entry: VideoEntryScope.fromJson(Map<String, dynamic>.from(j['entry'])),
    sequence: List<String>.from(j['sequence']),
    ordered: List<String>.from(j['ordered']),
    finished: j['finished'] as bool? ?? false,
    ordering: j['ordering'] as int? ?? 0,
  );
}

bool videoIsAvailable(LibraryVideo video, Iterable<MediaRoot> roots) {
  final owned = roots.where((root) => root.id == video.rootId).firstOrNull;
  if (video.status != VideoStatus.available ||
      owned == null ||
      !owned.available ||
      !owned.enabled ||
      owned.kind != MediaKind.video) {
    return false;
  }
  final policies = roots.where((root) => under(video.path, root.path)).toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  final policy = policies.firstOrNull;
  return policy != null &&
      policy.available &&
      policy.enabled &&
      policy.kind == MediaKind.video;
}

bool videoMatchesSearch(
  LibraryVideo video,
  Iterable<MediaRoot> roots,
  String search,
) {
  final root = roots.where((root) => root.id == video.rootId).firstOrNull;
  final relative = root != null && under(video.path, root.path)
      ? video.path.substring(root.path.length)
      : video.name;
  return relative.toLowerCase().contains(search.toLowerCase());
}

class DeleteOperation {
  DeleteOperation(
    this.id,
    Iterable<String> ids,
    Iterable<String> round,
    this.position,
  ) : ids = List.unmodifiable(ids),
      round = List.unmodifiable(round);
  final String id;
  final List<String> ids, round;
  final int position;
  Map<String, dynamic> toJson() => {
    'id': id,
    'ids': ids,
    'round': round,
    'position': position,
  };
  factory DeleteOperation.fromJson(Map<String, dynamic> j) => DeleteOperation(
    j['id'],
    List<String>.from(j['ids']),
    List<String>.from(j['round']),
    j['position'],
  );
}

class LibrarySnapshot {
  LibrarySnapshot({
    required Iterable<LibraryVideo> videos,
    required Iterable<MediaRoot> roots,
    required Iterable<String> tags,
    required this.query,
    required Iterable<String> round,
    this.position = 0,
    this.order = PlayOrder.random,
    this.address = '192.168.1.20',
    this.port = 8760,
    this.connected = true,
    this.lastDelete,
    Iterable<String> completedRequests = const [],
    this.preview,
    Map<String, double> recentVideos = const {},
  }) : videos = List.unmodifiable(videos),
       roots = List.unmodifiable(roots),
       tags = List.unmodifiable(tags),
       round = List.unmodifiable(round),
       completedRequests = List.unmodifiable(completedRequests),
       recentVideos = Map.unmodifiable(recentVideos);
  final List<LibraryVideo> videos;
  final List<MediaRoot> roots;
  final List<String> tags, round, completedRequests;
  final VideoQuery query;
  final int position, port;
  final PlayOrder order;
  final String address;
  final bool connected;
  final DeleteOperation? lastDelete;
  final VideoPreviewData? preview;
  final Map<String, double> recentVideos;
  LibrarySnapshot copy({
    Iterable<LibraryVideo>? videos,
    Iterable<MediaRoot>? roots,
    Iterable<String>? tags,
    VideoQuery? query,
    Iterable<String>? round,
    int? position,
    PlayOrder? order,
    String? address,
    int? port,
    bool? connected,
    DeleteOperation? lastDelete,
    bool clearDelete = false,
    Iterable<String>? completedRequests,
    VideoPreviewData? preview,
    bool clearPreview = false,
    Map<String, double>? recentVideos,
  }) => LibrarySnapshot(
    videos: videos ?? this.videos,
    roots: roots ?? this.roots,
    tags: tags ?? this.tags,
    query: query ?? this.query,
    round: round ?? this.round,
    position: position ?? this.position,
    order: order ?? this.order,
    address: address ?? this.address,
    port: port ?? this.port,
    connected: connected ?? this.connected,
    lastDelete: clearDelete ? null : lastDelete ?? this.lastDelete,
    completedRequests: completedRequests ?? this.completedRequests,
    preview: clearPreview ? null : preview ?? this.preview,
    recentVideos: recentVideos ?? this.recentVideos,
  );
  Map<String, dynamic> toJson({bool connection = true}) => {
    'videos': videos.map((v) => v.toJson()).toList(),
    'roots': roots.map((r) => r.toJson()).toList(),
    'tags': tags,
    'query': query.toJson(),
    'round': round,
    'position': position,
    'order': order.name,
    'lastDelete': lastDelete?.toJson(),
    'completedRequests': completedRequests,
    if (preview != null) 'preview': preview!.toJson(),
    'recentVideos': recentVideos,
    if (connection)
      'connection': {'address': address, 'port': port, 'connected': connected},
  };
  factory LibrarySnapshot.fromJson(Map<String, dynamic> j) {
    final c = j['connection'] as Map? ?? {};
    return LibrarySnapshot(
      videos: (j['videos'] as List).map(
        (v) => LibraryVideo.fromJson(Map<String, dynamic>.from(v)),
      ),
      roots: (j['roots'] as List).map(
        (r) => MediaRoot.fromJson(Map<String, dynamic>.from(r)),
      ),
      tags: List<String>.from(j['tags']),
      query: VideoQuery.fromJson(Map<String, dynamic>.from(j['query'])),
      round: List<String>.from(j['round']),
      position: j['position'],
      order: PlayOrder.values.byName(j['order']),
      address: c['address'] ?? '192.168.1.20',
      port: c['port'] ?? 8760,
      connected: c['connected'] ?? true,
      lastDelete: j['lastDelete'] == null
          ? null
          : DeleteOperation.fromJson(
              Map<String, dynamic>.from(j['lastDelete']),
            ),
      completedRequests: List<String>.from(j['completedRequests'] ?? []),
      preview: j['preview'] == null
          ? null
          : VideoPreviewData.fromJson(Map<String, dynamic>.from(j['preview'])),
      recentVideos: {
        for (final e in (j['recentVideos'] as Map? ?? {}).entries)
          e.key as String: (e.value as num).toDouble(),
      },
    );
  }
}

class FolderEntry {
  const FolderEntry(
    this.name,
    this.path, {
    this.available = true,
    this.id = '',
    this.videoCount,
  });
  final String name, path, id;
  final bool available;
  final int? videoCount;
}

class VideoPage {
  VideoPage({
    required Iterable<LibraryVideo> items,
    required this.total,
    required this.offset,
    required this.limit,
    this.anchorIndex,
  }) : items = List.unmodifiable(items);
  final List<LibraryVideo> items;
  final int total, offset, limit;
  final int? anchorIndex;
}

class BackupPreview {
  const BackupPreview(
    this.snapshot, {
    this.importId,
    this.suggestedMappings = const {},
    this.counts = const {},
  });
  final LibrarySnapshot snapshot;
  final String? importId;
  final Map<String, String?> suggestedMappings;
  final Map<String, int> counts;
  static BackupPreview parse(String text) {
    try {
      if (text.length > 2 * 1024 * 1024) throw const FormatException();
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['format'] != 'video-viewer-flutter-demo' || j['version'] != 1) {
        throw const LibraryFailure('备份格式或版本不兼容');
      }
      final s = LibrarySnapshot.fromJson(Map<String, dynamic>.from(j['data']));
      final ids = s.videos.map((v) => v.id).toSet();
      final roots = s.roots.map((r) => r.id).toSet();
      if (ids.length != s.videos.length ||
          roots.length != s.roots.length ||
          s.tags.toSet().length != s.tags.length ||
          s.tags.any((t) => t.trim().isEmpty) ||
          s.videos.any(
            (v) =>
                !roots.contains(v.rootId) ||
                !v.path.startsWith('/') ||
                v.path.split('/').contains('..') ||
                !s.tags.toSet().containsAll(v.tags),
          ) ||
          s.roots.any(
            (r) =>
                !r.path.startsWith('/') ||
                r.path == '/' ||
                r.path.split('/').contains('..'),
          ) ||
          s.round.any((id) => !ids.contains(id)) ||
          s.round.toSet().length != s.round.length ||
          s.position < 0 ||
          (s.round.isNotEmpty && s.position >= s.round.length) ||
          !['', 'portrait', 'landscape'].contains(s.query.orientation) ||
          !['', 'short', 'long'].contains(s.query.duration) ||
          !s.tags.toSet().containsAll(s.query.tags)) {
        throw const FormatException();
      }
      return BackupPreview(s);
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('备份内容不完整或已损坏，现有数据未改变');
    }
  }
}

/// Server-owned preparation state. Progress updates do not replace paged lists.
class LibraryPreparation {
  const LibraryPreparation({
    this.ready = true,
    this.scanning = false,
    this.phase = 'idle',
    this.taskId,
    this.status = 'idle',
    this.discovered = 0,
    this.processed = 0,
    this.bytesTotal = 0,
    this.bytesProcessed = 0,
    this.failed = 0,
    this.thumbnailFailed = 0,
    this.failureReasons = const {},
    this.deferred = 0,
    this.roots = const {},
    this.syncError,
  });
  final bool ready, scanning;
  final String phase, status;
  final String? taskId, syncError;
  final int discovered, processed, bytesTotal, bytesProcessed, failed, deferred;
  final int thumbnailFailed;
  final Map<String, int> failureReasons;
  final Map<String, Map<String, dynamic>> roots;
  factory LibraryPreparation.fromJson(
    Map<String, dynamic> data, {
    bool? ready,
  }) {
    final progress = data['progress'] as Map? ?? {};
    final counts = data['counts'] as Map? ?? {};
    return LibraryPreparation(
      ready: ready ?? data['ready'] == true,
      scanning: data['scanning'] == true,
      phase: data['phase'] as String? ?? 'idle',
      status: data['status'] as String? ?? 'idle',
      taskId: data['task_id'] as String?,
      discovered: (progress['discovered'] as num?)?.toInt() ?? 0,
      processed: (progress['processed'] as num?)?.toInt() ?? 0,
      bytesTotal: (progress['bytes_total'] as num?)?.toInt() ?? 0,
      bytesProcessed: (progress['bytes_processed'] as num?)?.toInt() ?? 0,
      failed: (counts['failed'] as num?)?.toInt() ?? 0,
      thumbnailFailed: (counts['thumbnail_failed'] as num?)?.toInt() ?? 0,
      failureReasons: {
        for (final entry in (data['failure_reasons'] as Map? ?? {}).entries)
          entry.key as String: (entry.value as num).toInt(),
      },
      deferred: (counts['deferred'] as num?)?.toInt() ?? 0,
      roots: {
        for (final root in data['roots'] as List? ?? [])
          root['id'] as String: Map<String, dynamic>.from(root as Map),
      },
    );
  }
  LibraryPreparation offline() => LibraryPreparation(
    ready: ready,
    scanning: scanning,
    phase: phase,
    taskId: taskId,
    status: status,
    discovered: discovered,
    processed: processed,
    bytesTotal: bytesTotal,
    bytesProcessed: bytesProcessed,
    failed: failed,
    thumbnailFailed: thumbnailFailed,
    failureReasons: failureReasons,
    deferred: deferred,
    roots: roots,
    syncError: '进度暂未同步，正在重试',
  );
  String get label => switch (phase) {
    'queued' => '扫描排队中',
    'discovering' => '正在查找视频',
    'waiting_for_stable_files' => '等待文件写入稳定',
    'processing_media' => '正在读取视频信息',
    'reconciling_identities' => '正在核对文件身份',
    'completed' => ready ? '扫描完成' : '部分目录未就绪，请检查媒体目录',
    'interrupted' => '扫描已中断',
    'failed' => '扫描失败',
    _ => ready ? '视频库已就绪' : '等待首次扫描',
  };
  String get summary =>
      '$label${discovered > 0
          ? phase == 'discovering'
                ? ' · 已发现 $discovered 个'
                : ' · $processed / $discovered 个'
          : ''}';
  String get failureDetail => failureReasons.entries
      .map((entry) {
        final label = switch (entry.key) {
          'probe_timeout' => '读取媒体信息超时',
          'probe_failed' => '媒体信息无法解析',
          'probe_unavailable' => '探测工具不可用',
          'no_video_stream' => '未找到视频轨道',
          'invalid_duration' ||
          'invalid_dimensions' ||
          'invalid_metadata' => '媒体信息不完整',
          'file_missing' => '文件已移走',
          'permission_denied' => '读取权限不足',
          _ => '其他读取问题',
        };
        return '$label ${entry.value} 个';
      })
      .join(' · ');
}
