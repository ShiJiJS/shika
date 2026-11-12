import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';

class DelayedEntryCatalog extends DemoLibraryRepository {
  DelayedEntryCatalog() : super(MemoryStateStore(), latency: Duration.zero);
  final begins = <Completer<void>>[];
  final restores = <Completer<VideoPage>>[];
  final offsets = <int>[];
  late final entries = [
    for (var i = 0; i < 72; i++)
      LibraryVideo(
        id: 'entry-$i',
        path: '/videos/${i.toString().padLeft(2, '0')}.mp4',
        rootId: 'r1',
        portrait: true,
        source: snapshot.videos.first.source,
        poster: snapshot.videos.first.poster,
      ),
  ];

  VideoPage page(int offset) => VideoPage(
    items: entries.skip(offset).take(24),
    total: entries.length,
    offset: offset,
    limit: 24,
    anchorIndex: offset,
  );

  @override
  Future<VideoPage> loadVideoEntry(
    VideoEntryScope entry, {
    int offset = 0,
    int limit = 24,
  }) async {
    offsets.add(offset);
    return page(offset);
  }

  @override
  Future<VideoPage> restoreVideoEntry(
    VideoEntryScope entry, {
    required List<String> anchors,
    required int fallbackIndex,
    int limit = 24,
  }) {
    final pending = Completer<VideoPage>();
    restores.add(pending);
    return pending.future;
  }

  @override
  Future<void> beginPreview(
    VideoEntryScope entry, {
    String? anchor,
    PlayOrder? order,
  }) {
    final pending = Completer<void>();
    begins.add(pending);
    return pending.future;
  }

  void metadataChanged() => notifyListeners();
}

Future<void> frames(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late DelayedEntryCatalog repo;
  setUp(() async {
    repo = DelayedEntryCatalog();
    await repo.initialize();
  });
  tearDown(() => repo.dispose());

  for (final cancelled in [false, true]) {
    testWidgets(
      'failed preview entry releases an overlapping return lookup and pagination; cancelled=$cancelled',
      (t) async {
        await t.pumpWidget(ShikaApp(repository: repo));
        await frames(t);
        expect(find.text('72 个视频'), findsOneWidget);
        repo.metadataChanged();
        await frames(t);
        expect(repo.restores, hasLength(1));
        // Scope actions are disabled while restoring; visible media can still
        // enter preview, preserving this overlapping-read recovery scenario.
        await t.tap(find.byKey(const Key('tile-entry-0')));
        await frames(t);
        expect(repo.begins, hasLength(1));
        repo.begins.single.completeError(
          cancelled ? const RequestCancelled() : const LibraryFailure('预览创建失败'),
        );
        await frames(t);
        expect(find.byType(MovieStage), findsNothing);
        expect(repo.restores, hasLength(2));
        repo.restores.first.complete(repo.page(48));
        await frames(t);
        expect(find.byKey(const Key('tile-entry-0')), findsOneWidget);
        repo.restores.last.complete(repo.page(0));
        await frames(t);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        final scroll = t
            .widget<CustomScrollView>(find.byKey(const Key('video-grid')))
            .controller!;
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await frames(t);
        expect(repo.offsets, contains(24));
        expect(find.byKey(const Key('library-loading-more')), findsNothing);
        expect(repo.snapshot.recentVideos, isEmpty);
        await t.pumpWidget(const SizedBox());
        await frames(t);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'leaving the library cancels navigation from a late begin result',
    (t) async {
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      await t.tap(find.byKey(const Key('video-quick-cleanup')));
      await frames(t);
      expect(repo.begins, hasLength(1));
      await t.tap(find.byKey(const Key('nav-settings')));
      await frames(t);
      repo.begins.single.complete();
      await frames(t);
      expect(find.byKey(const Key('video-preview-route')), findsNothing);
      expect(find.byType(MovieStage), findsNothing);
      expect(find.text('服务连接'), findsOneWidget);
      expect(repo.snapshot.recentVideos, isEmpty);
      await t.tap(find.byKey(const Key('nav-library')));
      await frames(t);
      expect(repo.restores, isNotEmpty);
      repo.restores.last.complete(repo.page(0));
      await frames(t);
      final scroll = t
          .widget<CustomScrollView>(find.byKey(const Key('video-grid')))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await frames(t);
      expect(repo.offsets, contains(24));
      await t.pumpWidget(const SizedBox());
      await frames(t);
      expect(t.takeException(), isNull);
    },
  );
}
