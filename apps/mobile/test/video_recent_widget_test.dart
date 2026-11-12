import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/features/library/video_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/media_history.dart';
import 'package:shika/ui/media_layout.dart';
import 'package:shika/ui/player.dart';

import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_recent_widget_test.dart' show RecentLayoutLibrary;

class RecentVideos extends RecentLayoutLibrary {
  final videos = [for (var i = 0; i < 180; i++) i];
  bool emptyVideos = false;
  final videoReads = <({int offset, VideoEntryScope entry})>[];
  final videoRestores = <List<String>>[];
  List<LibraryVideo> get history => [
    if (!emptyVideos)
      for (final i in videos)
        LibraryVideo(
          id: 'history-$i',
          path: '/videos/最近视频$i.mp4',
          rootId: 'r1',
          portrait: true,
          seconds: 6,
          source: const MediaSource('assets/media/flower-portrait.mp4'),
          poster: 'assets/media/flower-portrait.jpg',
        ),
  ];
  void reorderVideos() {
    videos.insert(0, videos.removeLast());
    notifyListeners();
  }

  void clearVideos() {
    emptyVideos = true;
    notifyListeners();
  }

  @override
  Future<VideoPage> loadVideoEntry(
    VideoEntryScope entry, {
    int offset = 0,
    int limit = 24,
  }) async {
    if (entry.source != BrowseSource.recent) {
      return super.loadVideoEntry(entry, offset: offset, limit: limit);
    }
    videoReads.add((offset: offset, entry: entry));
    final all = history;
    return VideoPage(
      items: all.skip(offset).take(limit),
      total: all.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<VideoPage> restoreVideoEntry(
    VideoEntryScope entry, {
    required List<String> anchors,
    required int fallbackIndex,
    int limit = 24,
  }) async {
    if (entry.source != BrowseSource.recent) {
      return super.restoreVideoEntry(
        entry,
        anchors: anchors,
        fallbackIndex: fallbackIndex,
        limit: limit,
      );
    }
    videoRestores.add(anchors);
    final all = history;
    var index = -1;
    for (final id in anchors) {
      index = all.indexWhere((v) => v.id == id);
      if (index >= 0) break;
    }
    if (index < 0) {
      index = fallbackIndex.clamp(0, all.isEmpty ? 0 : all.length - 1);
    }
    final offset = index ~/ limit * limit;
    return VideoPage(
      items: all.skip(offset).take(limit),
      total: all.length,
      offset: offset,
      limit: limit,
      anchorIndex: index,
    );
  }
}

void main() {
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.6),
  ]) {
    testWidgets(
      'video history pages, restores a boundary anchor and keeps independent library ${sample.$1}/${sample.$2}',
      (t) async {
        final original = VideoPlayerPlatform.instance;
        final previousError = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint('RECENT_LAYOUT_ERROR:$details');
          previousError?.call(details);
        };
        VideoPlayerPlatform.instance = UnreadyVideo();
        final repo = RecentVideos();
        await repo.initialize();
        t.view.physicalSize = sample.$1;
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = sample.$2;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          repo.dispose();
          VideoPlayerPlatform.instance = original;
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
          FlutterError.onError = previousError;
        });
        Future<void> until(bool Function() done) async {
          for (var i = 0; i < 180; i++) {
            await t.pump(const Duration(milliseconds: 50));
            await t.runAsync(() => Future<void>.delayed(Duration.zero));
            expect(t.takeException(), isNull);
            if (done()) return;
          }
          fail('Recent video UI did not reach expected state');
        }

        VideoCatalogPageState catalog() =>
            t.state(find.byType(VideoCatalogPage));
        await t.pumpWidget(ShikaApp(repository: repo));
        await until(
          () => find.byKey(const Key('video-search')).evaluate().isNotEmpty,
        );
        await t.enterText(find.byKey(const Key('video-search')), '花间微风');
        await until(() => !catalog().data.loading && catalog().data.total == 1);
        await t.tap(find.byKey(const Key('nav-recent')));
        await until(
          () =>
              find.text('最近预览的视频').evaluate().isNotEmpty &&
              !catalog().data.loading &&
              find
                  .byKey(const Key('recent-video-history-0'))
                  .evaluate()
                  .isNotEmpty,
        );
        expect(catalog().data.total, 180);
        expect(catalog().columns, 1);
        expect(find.byKey(const Key('video-search')), findsNothing);
        expect(find.byType(MediaCatalogToolbar), findsNothing);
        final first = find.byKey(const Key('recent-video-history-0'));
        expect(first, findsOneWidget);
        expect(t.getRect(first).width, sample.$1.width - 40);
        final cover = find.descendant(
          of: first,
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 64 && w.height == 78,
          ),
        );
        expect(t.getSize(cover), const Size(64, 78));
        expect(find.byType(MediaHistoryRow), findsWidgets);
        // The catalog's existing selection state must not turn row selection
        // into playback when presentation changes from cards to history rows.
        final initialPlayback = repo.playbackIdentity;
        catalog().toggleSelection();
        await until(() => catalog().selecting);
        await t.tap(first);
        await until(() => catalog().selected.contains('history-0'));
        expect(find.byType(MovieStage), findsNothing);
        expect(repo.playbackIdentity, initialPlayback);
        expect(repo.snapshot.preview, isNull);
        catalog().toggleSelection();
        await until(() => !catalog().selecting);
        for (var i = 0; i < 14 && catalog().data.offset < 24; i++) {
          await t.drag(
            find.byKey(const Key('video-grid')),
            const Offset(0, -2600),
          );
          await until(() => !catalog().data.loading);
          expect(catalog().data.items.length, lessThanOrEqualTo(120));
        }
        expect(catalog().data.offset, greaterThanOrEqualTo(24));
        await t.pumpAndSettle();
        final anchor = catalog().data.items[22].id;
        catalog().scroll.jumpTo(
          catalog().listHeader + 22 * catalog().stride + 19,
        );
        await until(() => catalog().position().ids.first == anchor);
        await t.pumpAndSettle();
        expect(catalog().position().context.scrollInset, closeTo(19, 1));
        final row = find.byKey(Key('recent-video-$anchor'));
        final oldY = t.getTopLeft(row).dy;
        repo.reorderVideos();
        await until(
          () =>
              !catalog().data.loading &&
              catalog().pendingReturn == null &&
              row.evaluate().isNotEmpty &&
              repo.videoRestores.isNotEmpty,
        );
        await t.pumpAndSettle();
        expect(t.getTopLeft(row).dy, closeTo(oldY, 1));
        expect(catalog().position().ids.first, anchor);
        final oldStride = catalog().stride;
        final oldHeader = catalog().listHeader;
        t.platformDispatcher.textScaleFactorTestValue = sample.$2 * 1.3;
        await until(
          () =>
              catalog().stride != oldStride ||
              catalog().listHeader != oldHeader,
        );
        await t.pump();
        expect(catalog().position().ids.first, anchor);
        expect(catalog().position().context.scrollInset, closeTo(19, 1));
        repo.clearVideos();
        await until(() => find.text('还没有观看记录').evaluate().isNotEmpty);
        await t.tap(find.byKey(const Key('nav-library')));
        await until(
          () =>
              find.byKey(const Key('video-search')).evaluate().isNotEmpty &&
              !catalog().data.loading,
        );
        final filterLabel = find.descendant(
          of: find.byKey(const ValueKey('筛选视频')),
          matching: find.text('筛选'),
        );
        expect(
          t.renderObject<RenderParagraph>(filterLabel).didExceedMaxLines,
          isFalse,
          reason: 'The enlarged filter label remains fully visible',
        );
        expect(catalog().search.text, '花间微风');
        expect(catalog().data.total, 1);
        expect(
          repo.videoReads.every(
            (r) =>
                r.entry.search.isEmpty &&
                r.entry.query.count == 0 &&
                r.entry.sort == VideoSort.recent,
          ),
          isTrue,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
