import 'package:flutter/foundation.dart';

import 'models.dart';

/// This boundary describes client-visible behavior, independent of transport.
/// A future network provider implements it; widgets never access NAS files.
abstract class LibraryRepository extends ChangeNotifier {
  final ValueNotifier<String?> scanStatus = ValueNotifier(null);
  final libraryPreparation = ValueNotifier(const LibraryPreparation());
  Future<void> requestScan() => refresh();
  final ValueNotifier<String?> backupStatus = ValueNotifier(null);
  final ValueNotifier<String?> fileStatus = ValueNotifier(null);
  ServiceCapabilities get capabilities => const ServiceCapabilities.legacy();
  bool get backupRestorePending => false;
  Object get connectionIdentity => this;
  Future<void> reconcileBackupRestore() async {}
  @override
  void dispose() {
    scanStatus.dispose();
    libraryPreparation.dispose();
    backupStatus.dispose();
    fileStatus.dispose();
    super.dispose();
  }

  Future<String?> playbackFailure(MediaSource source) async => null;
  LibrarySnapshot get snapshot;
  Future<void> initialize();
  List<LibraryVideo> query({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 100000,
  });
  List<FolderEntry> folders(String parent);
  Future<VideoPage> loadVideos({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 24,
  }) async {
    final items = query(scope: scope, search: search);
    return VideoPage(
      items: items.skip(offset).take(limit),
      total: items.length,
      offset: offset,
      limit: limit,
    );
  }

  Future<List<FolderEntry>> loadFolders(String parent) async =>
      folders(parent)
          .map(
            (folder) => FolderEntry(
              folder.name,
              folder.path,
              available: folder.available,
              id: folder.id,
              videoCount:
                  folder.videoCount ??
                  query(scope: VideoQuery(folder: folder.path)).length,
            ),
          )
          .toList();
  int get playbackPosition => snapshot.position;
  int get playbackTotal => snapshot.round.length;
  String get playbackIdentity => '${snapshot.query.toJson()}-${snapshot.order}';
  Future<VideoPage> loadPlaybackVideos({int offset = 0, int limit = 48}) async {
    final ids = snapshot.round.skip(offset).take(limit);
    return VideoPage(
      items: ids.map((id) => snapshot.videos.firstWhere((v) => v.id == id)),
      total: snapshot.round.length,
      offset: offset,
      limit: limit,
    );
  }

  Future<void> moveToVideo(String id) async {
    final index = snapshot.round.indexOf(id);
    if (index >= 0) await step(index - snapshot.position);
  }

  String tagName(String id) => id;
  int tagVideoCount(String id) => query(scope: VideoQuery(tags: {id})).length;
  int get missingCount => snapshot.videos
      .where((video) => video.status == VideoStatus.missing)
      .length;
  int get trashCount => snapshot.videos
      .where((video) => video.status == VideoStatus.trash)
      .length;
  Future<VideoPage> loadTrash({int offset = 0, int limit = 24}) async {
    final items = snapshot.videos
        .where((v) => v.status == VideoStatus.trash)
        .toList();
    return VideoPage(
      items: items.skip(offset).take(limit),
      total: items.length,
      offset: offset,
      limit: limit,
    );
  }

  Future<VideoPage> loadMissing({int offset = 0, int limit = 24}) async {
    final items = snapshot.videos
        .where((v) => v.status == VideoStatus.missing)
        .toList();
    return VideoPage(
      items: items.skip(offset).take(limit),
      total: items.length,
      offset: offset,
      limit: limit,
    );
  }

  bool get fileOperationPending => false;
  Future<void> reconcileFileOperation() async {}
  Future<int> forgetMissingVideos() async => 0;
  void cancelVideoRead() {}
  void cancelFolderRead() {}
  void cancelTrashRead() {}
  void cancelMissingRead() {}
  String? get connectionError => null;
  Future<void> mediaUnauthorized(MediaSource source) async {}
  LibraryVideo? get current;
  Future<void> connect(String address, int port, String passphrase);
  Future<void> setScope(VideoQuery scope, {PlayOrder? order});
  Future<void> newRound();
  Future<void> step(int delta);
  Future<void> openVideo(String id);
  Future<void> setVideoTags(
    Set<String> ids,
    Set<String> tags, {
    bool remove = false,
    bool replace = false,
  });
  Future<void> editTag({String? original, String? name, bool delete = false});
  Future<void> deleteVideos(Set<String> ids, {required String requestId});
  Future<void> undoDelete({required String operationId});
  Future<List<String>> restoreVideos(Set<String> ids);
  Future<void> permanentlyDelete(Set<String> ids);
  Future<void> saveRoot(MediaRoot root);
  Future<void> refresh();
  Future<String> exportBackupFile();
  Future<BackupPreview> inspectBackupFile(String text);
  Future<void> restoreBackup(String text, Map<String, String> rootMappings);
}

abstract interface class DemoControls {
  DemoScenario get scenario;
  Future<void> reset({DemoScenario scenario = DemoScenario.normal});
}
