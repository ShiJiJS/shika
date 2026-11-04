import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';

/// Exercises the actual non-DemoControls settings path without file commands.
class ScanDetailsLibrary extends LibraryRepository {
  ScanDetailsLibrary() {
    libraryPreparation.value = const LibraryPreparation(
      phase: 'completed',
      status: 'completed',
      discovered: 4,
      processed: 4,
    );
  }

  @override
  final snapshot = LibrarySnapshot(
    videos: const [],
    roots: const [MediaRoot('fixture', 'Fixture root', '/fixture/videos')],
    tags: const [],
    query: VideoQuery(),
    round: const [],
  );
  @override
  LibraryVideo? get current => null;
  @override
  Future<void> initialize() async {}
  @override
  List<LibraryVideo> query({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 100000,
  }) => [];
  @override
  List<FolderEntry> folders(String parent) => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected scan fixture operation: ${invocation.memberName}',
  );
}
