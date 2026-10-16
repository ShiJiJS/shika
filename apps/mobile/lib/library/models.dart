import 'dart:convert';

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
  }) : tags = Set.unmodifiable(tags);
  final String id, path, rootId, poster, type;
  final bool portrait;
  final int seconds;
  final MediaSource source;
  final Set<String> tags;
  final VideoStatus status;
  final String? originalPath;
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
  );
}

class MediaRoot {
  const MediaRoot(
    this.id,
    this.name,
    this.path, {
    this.available = true,
    this.lastScan = '今天 09:20',
  });
  final String id, name, path, lastScan;
  final bool available;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'available': available,
    'lastScan': lastScan,
  };
  factory MediaRoot.fromJson(Map<String, dynamic> j) => MediaRoot(
    j['id'],
    j['name'],
    j['path'],
    available: j['available'],
    lastScan: j['lastScan'],
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
  }) : videos = List.unmodifiable(videos),
       roots = List.unmodifiable(roots),
       tags = List.unmodifiable(tags),
       round = List.unmodifiable(round),
       completedRequests = List.unmodifiable(completedRequests);
  final List<LibraryVideo> videos;
  final List<MediaRoot> roots;
  final List<String> tags, round, completedRequests;
  final VideoQuery query;
  final int position, port;
  final PlayOrder order;
  final String address;
  final bool connected;
  final DeleteOperation? lastDelete;
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
    );
  }
}

class FolderEntry {
  const FolderEntry(this.name, this.path, {this.available = true});
  final String name, path;
  final bool available;
}

class BackupPreview {
  const BackupPreview(this.snapshot);
  final LibrarySnapshot snapshot;
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
