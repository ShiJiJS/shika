import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';

void main() {
  late MemoryStateStore store;
  late DemoLibraryRepository repo;
  setUp(() async {
    store = MemoryStateStore();
    repo = DemoLibraryRepository(store, latency: Duration.zero);
    await repo.initialize();
  });
  tearDown(() => repo.dispose());

  test('fixed filtered members and selection survive tag deletion, mode switches and reopening', () async {
    final entry = VideoEntryScope(
      query: VideoQuery(tags: {'花卉'}),
      sort: VideoSort.name,
      source: BrowseSource.tags,
    );
    final matches = (await repo.loadVideoEntry(entry)).items
        .map((v) => v.id)
        .toList();
    await repo.beginPreview(entry, anchor: 'v2', order: PlayOrder.sequential);
    final identity = repo.playbackIdentity;
    await repo.setVideoTags({'v2'}, {}, replace: true);
    expect(repo.current!.id, 'v2');
    expect(repo.snapshot.round, matches);
    await repo.editTag(original: '花卉', delete: true);
    expect(repo.current!.id, 'v2');
    expect(repo.snapshot.round, matches);
    final sequence = repo.playbackSequenceIdentity;
    await repo.changePreviewOrder(PlayOrder.random);
    expect(repo.playbackSequenceIdentity, isNot(sequence));
    expect(repo.current!.id, 'v2');
    expect(repo.snapshot.round.toSet(), matches.toSet());
    await repo.changePreviewOrder(PlayOrder.sequential);
    expect(repo.snapshot.round, matches);
    final reopened = DemoLibraryRepository(store, latency: Duration.zero);
    await reopened.initialize();
    expect(reopened.playbackIdentity, identity);
    expect(reopened.current!.id, 'v2');
    expect(reopened.snapshot.preview!.entry.source, BrowseSource.tags);
    await reopened.newRound();
    expect(reopened.snapshot.round, matches);
    expect(reopened.playbackIdentity, identity);
    reopened.dispose();
  });

  test(
    'only visible opens enter recents; recent entry has its own fixed baseline',
    () async {
      expect(
        (await repo.loadVideoEntry(
          VideoEntryScope(source: BrowseSource.recent, sort: VideoSort.recent),
        )).total,
        0,
      );
      await repo.beginPreview(
        VideoEntryScope(),
        anchor: 'v1',
        order: PlayOrder.sequential,
      );
      expect(repo.snapshot.recentVideos, isEmpty);
      await repo.recordVideoOpened('v1');
      await repo.moveToVideo('v2');
      expect(repo.snapshot.recentVideos.keys.toSet(), {'v1'});
      await repo.recordVideoOpened('v2');
      final recent = VideoEntryScope(
        source: BrowseSource.recent,
        sort: VideoSort.recent,
      );
      final before = (await repo.loadVideoEntry(recent)).items
          .map((v) => v.id)
          .toList();
      expect(before.toSet(), {'v1', 'v2'});
      await repo.beginPreview(recent, order: PlayOrder.sequential);
      await repo.moveToVideo(before.last);
      await repo.recordVideoOpened(before.last);
      await repo.changePreviewOrder(PlayOrder.random);
      await repo.changePreviewOrder(PlayOrder.sequential);
      expect(repo.snapshot.round, before);
      expect(repo.snapshot.round.length, 2);
    },
  );

  test(
    'fixed undo follows the deleted identity after mode reordering',
    () async {
      await repo.beginPreview(
        VideoEntryScope(),
        anchor: 'v1',
        order: PlayOrder.sequential,
      );
      final original = repo.snapshot.round.toSet();
      await repo.deleteVideos({'v1'}, requestId: 'fixed-delete');
      await repo.changePreviewOrder(PlayOrder.random);
      final mode = repo.snapshot.order;
      await repo.undoDelete(operationId: 'fixed-delete');
      expect(repo.current!.id, 'v1');
      expect(repo.snapshot.round.toSet(), original);
      expect(repo.snapshot.order, mode);
    },
  );

  test(
    'directory search matches relative paths and empty scope never expands',
    () async {
      final entry = VideoEntryScope(
        search: '花草',
        query: VideoQuery(folder: '/videos/收集'),
      );
      final page = await repo.loadVideoEntry(entry);
      expect(page.items.map((v) => v.id).toSet(), {'v1', 'v2', 'v3'});
      await repo.beginPreview(entry, anchor: 'v3');
      expect(repo.snapshot.round.toSet(), {'v1', 'v2', 'v3'});
      await repo.beginPreview(VideoEntryScope(search: 'not-a-video'));
      expect(repo.current, isNull);
      expect(repo.snapshot.round, isEmpty);
      await repo.newRound();
      expect(repo.snapshot.round, isEmpty);
    },
  );
}
