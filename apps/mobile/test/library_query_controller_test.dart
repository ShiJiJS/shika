import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/library/browse_context.dart';
import 'package:video_viewer/features/library/library_query_controller.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';

class DelayedCatalog extends DemoLibraryRepository {
  DelayedCatalog() : super(MemoryStateStore(), latency: Duration.zero);
  final requests =
      <({String search, int offset, Completer<VideoPage> result})>[];
  final restores =
      <({List<String> anchors, int fallback, Completer<VideoPage> result})>[];

  @override
  Future<VideoPage> restoreVideoEntry(
    VideoEntryScope entry, {
    required List<String> anchors,
    required int fallbackIndex,
    int limit = 24,
  }) {
    final result = Completer<VideoPage>();
    restores.add((anchors: anchors, fallback: fallbackIndex, result: result));
    return result.future;
  }

  @override
  Future<VideoPage> loadVideos({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 24,
  }) {
    final result = Completer<VideoPage>();
    requests.add((search: search, offset: offset, result: result));
    return result.future;
  }
}

VideoPage page(int offset, int count, {int total = 27}) => VideoPage(
  items: [
    for (var i = offset; i < offset + count; i++)
      LibraryVideo(
        id: 'video-$i',
        path: '/videos/$i.mp4',
        rootId: 'r1',
        portrait: true,
        source: const MediaSource('test-only'),
        poster: '',
      ),
  ],
  offset: offset,
  limit: 24,
  total: total,
);

void main() {
  late DelayedCatalog repo;
  late LibraryQueryController controller;
  setUp(() async {
    repo = DelayedCatalog();
    await repo.initialize();
    controller = LibraryQueryController(repo);
  });
  tearDown(() {
    controller.dispose();
    repo.dispose();
  });

  test('deep return failure retains the old window; retry locates one page then pages both ways', () async {
    final context = VideoBrowseContext(
      scrollIndex: 999,
      scrollAnchor: 'video-999',
    );
    final initial = controller.load(context);
    repo.requests.last.result.complete(page(0, 24, total: 2000));
    await initial;
    final failed = controller.restore(
      context,
      anchors: ['video-999', 'video-1000'],
    );
    repo.restores.last.result.completeError(StateError('offline'));
    await failed;
    expect(controller.state.items.first.id, 'video-0');
    expect(controller.state.offset, 0);
    expect(controller.state.error, contains('offline'));
    final retry = controller.restore(
      context,
      anchors: ['video-999', 'video-1000'],
    );
    expect(repo.restores.last.fallback, 999);
    repo.restores.last.result.complete(
      VideoPage(
        items: page(984, 24, total: 2001).items,
        offset: 984,
        limit: 24,
        total: 2001,
        anchorIndex: 1000,
      ),
    );
    await retry;
    expect(controller.state.items.length, 24);
    expect(controller.state.anchorIndex, 1000);
    expect(controller.state.offset, 984);
    expect(controller.state.hasBefore, isTrue);
    expect(controller.state.hasAfter, isTrue);
    final more = controller.load(context, more: true);
    expect(repo.requests.last.offset, 1008);
    repo.requests.last.result.complete(page(1008, 24, total: 2001));
    await more;
    final beforeFailed = controller.load(context, before: true);
    repo.requests.last.result.completeError(
      StateError('previous page offline'),
    );
    await beforeFailed;
    expect(controller.state.beforeFailure, isTrue);
    expect(controller.state.offset, 984);
    expect(controller.state.items.length, 48);
    final before = controller.load(context, before: true);
    expect(repo.requests.last.offset, 960);
    repo.requests.last.result.complete(page(960, 24, total: 2001));
    await before;
    expect(controller.state.offset, 960);
    expect(controller.state.items.length, 72);
    expect(controller.state.items.last.id, 'video-1031');
    expect(controller.state.beforeFailure, isFalse);
  });

  test('a late return lookup cannot replace a new search', () async {
    final old = controller.restore(
      VideoBrowseContext(search: 'old'),
      anchors: ['old-id'],
    );
    final current = controller.load(VideoBrowseContext(search: 'new'));
    repo.requests.last.result.complete(page(0, 1, total: 1));
    await current;
    repo.restores.last.result.complete(page(984, 24, total: 2000));
    await old;
    expect(controller.state.context.search, 'new');
    expect(controller.state.offset, 0);
    expect(controller.state.items.length, 1);
  });

  test(
    'new query wins over a late response without changing playback',
    () async {
      final round = repo.snapshot.round;
      final query = repo.snapshot.query;
      final old = controller.load(VideoBrowseContext(search: 'old'));
      final current = controller.load(VideoBrowseContext(search: 'new'));
      repo.requests[1].result.complete(page(24, 1, total: 1));
      await current;
      repo.requests[0].result.complete(page(0, 24));
      await old;
      expect(controller.state.items.single.id, 'video-24');
      expect(controller.state.context.search, 'new');
      expect(controller.state.total, 1);
      expect(repo.snapshot.round, round);
      expect(identical(repo.snapshot.query, query), isTrue);
    },
  );

  test('pagination failure keeps cards and retries the same offset', () async {
    final context = VideoBrowseContext();
    final first = controller.load(context);
    repo.requests.last.result.complete(page(0, 24));
    await first;
    final more = controller.load(context, more: true);
    await controller.load(context, more: true);
    expect(repo.requests.length, 2);
    repo.requests.last.result.completeError(StateError('offline'));
    await more;
    expect(controller.state.items.length, 24);
    expect(controller.state.error, contains('offline'));
    final retry = controller.load(context, more: true);
    expect(repo.requests.last.offset, 24);
    repo.requests.last.result.complete(page(24, 3));
    await retry;
    expect(controller.state.items.length, 27);
    expect(controller.state.total, 27);
    expect(controller.state.error, isEmpty);
  });

  test(
    'leaving a page rejects in-flight results and releases loading',
    () async {
      final request = controller.load(VideoBrowseContext(search: 'leave'));
      controller.cancel();
      repo.requests.last.result.complete(page(0, 24));
      await request;
      expect(controller.state.loading, isFalse);
      expect(controller.state.items, isEmpty);
    },
  );

  test(
    'empty append reports catalog changes without endless auto pagination',
    () async {
      final context = VideoBrowseContext();
      final first = controller.load(context);
      repo.requests.last.result.complete(page(0, 24));
      await first;
      final more = controller.load(context, more: true);
      repo.requests.last.result.complete(page(24, 0));
      await more;
      expect(controller.state.items.length, 24);
      expect(controller.state.error, contains('视频列表已变化'));
    },
  );

  test(
    'scroll position does not change query identity; source and tags do',
    () {
      final context = VideoBrowseContext(query: VideoQuery(tags: {'b', 'a'}));
      final equivalent = context.copyWith(
        query: VideoQuery(tags: {'a', 'b'}),
        scrollOffset: 120,
        scrollAnchor: 'video-4',
      );
      expect(context.queryKey, equivalent.queryKey);
      expect(
        context.queryKey,
        isNot(context.copyWith(source: BrowseSource.recent).queryKey),
      );
      expect(context.scrollOffset, 0);
      expect(equivalent.kind, MediaKind.video);
    },
  );
}
