import 'package:flutter/foundation.dart';

import 'models.dart';

/// This boundary describes client-visible behavior, independent of transport.
/// A future network provider implements it; widgets never access NAS files.
abstract class LibraryRepository extends ChangeNotifier {
  LibrarySnapshot get snapshot;
  Future<void> initialize();
  List<LibraryVideo> query({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 100000,
  });
  List<FolderEntry> folders(String parent);
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
  String exportBackup();
  BackupPreview inspectBackup(String text);
  Future<void> restoreBackup(String text, Map<String, String> rootMappings);
}

abstract interface class DemoControls {
  DemoScenario get scenario;
  Future<void> reset({DemoScenario scenario = DemoScenario.normal});
}
