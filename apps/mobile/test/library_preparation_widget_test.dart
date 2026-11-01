import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';

class PagedLibrary extends DemoLibraryRepository {
  @override
  bool get supportsFixedPreviews => false;
  PagedLibrary() : super(MemoryStateStore(), latency: Duration.zero) {
    libraryPreparation.value = const LibraryPreparation(
      ready: false,
      scanning: true,
      phase: 'processing_media',
      discovered: 27,
      processed: 24,
    );
  }
  final offsets = <int>[];
  final next = <Completer<void>>[];
  @override
  Future<VideoPage> loadVideos({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 24,
  }) async {
    offsets.add(offset);
    if (offset > 0 && next.isNotEmpty) await next.removeAt(0).future;
    return VideoPage(
      items: [
        for (var i = offset; i < 27 && i < offset + limit; i++)
          LibraryVideo(
            id: 'page-$i',
            path: '/videos/示例$i.mp4',
            rootId: 'r1',
            portrait: true,
            source: const MediaSource('test-only'),
            poster: 'assets/media/flower-portrait.jpg',
          ),
      ],
      total: 27,
      offset: offset,
      limit: limit,
    );
  }
}

void main() {
  testWidgets(
    'thumbnail warnings are displayed separately from source failures',
    (t) async {
      final repo = PagedLibrary();
      await repo.initialize();
      final preparation = LibraryPreparation.fromJson({
        'ready': false,
        'scanning': true,
        'phase': 'processing_media',
        'counts': {'failed': 2, 'thumbnail_failed': 204},
        'failure_reasons': {'probe_timeout': 2},
      });
      repo.libraryPreparation.value = preparation.offline();
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('2 个视频信息读取失败'), findsOneWidget);
      expect(find.textContaining('204 个缩略图待补充（不影响入库）'), findsOneWidget);
      expect(find.text('读取媒体信息超时 2 个'), findsOneWidget);
      expect(find.text('进度暂未同步，正在重试'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets(
    'preparation blocks the player and updates progress without reloading the grid',
    (t) async {
      final repo = PagedLibrary();
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await t.pump();
      expect(find.byType(MovieStage), findsNothing);
      expect(find.byKey(const Key('library-preparation')), findsOneWidget);
      expect(find.textContaining('24 / 27 个'), findsOneWidget);
      await t.tap(find.byKey(const Key('nav-library')));
      await t.pumpAndSettle();
      expect(repo.offsets, [0]);
      repo.libraryPreparation.value = const LibraryPreparation(
        ready: false,
        scanning: true,
        phase: 'processing_media',
        discovered: 27,
        processed: 25,
      );
      await t.pump();
      expect(repo.offsets, [0]);
      expect(find.widgetWithText(OutlinedButton, '播放'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '播放'))
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets(
    'near-bottom pagination animates, preserves cards on failure, and retries the same offset',
    (t) async {
      final repo = PagedLibrary();
      final failed = Completer<void>(), recovered = Completer<void>();
      repo.next.addAll([failed, recovered]);
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await t.tap(find.byKey(const Key('nav-library')));
      await t.pumpAndSettle();
      final grid = find.byKey(const Key('video-grid'));
      final controller = t.widget<CustomScrollView>(grid).controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await t.pump();
      await t.pump();
      expect(repo.offsets, [0, 24]);
      expect(find.byKey(const Key('library-loading-more')), findsOneWidget);
      await t.drag(grid, const Offset(0, -200));
      await t.pump();
      expect(repo.offsets, [0, 24]);
      failed.completeError(StateError('测试网络中断'));
      await t.pump();
      await t.pumpAndSettle();
      expect(find.textContaining('测试网络中断'), findsOneWidget);
      final offset = t.widget<CustomScrollView>(grid).controller!.offset;
      expect(offset, greaterThan(0));
      await t.tap(find.widgetWithText(TextButton, '重试'));
      await t.pump();
      expect(repo.offsets, [0, 24, 24]);
      recovered.complete();
      await t.pumpAndSettle();
      controller.jumpTo(controller.position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(find.text('已显示全部视频'), findsOneWidget);
      expect(
        t.widget<CustomScrollView>(grid).controller!.offset,
        greaterThan(0),
      );
      await t.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}
