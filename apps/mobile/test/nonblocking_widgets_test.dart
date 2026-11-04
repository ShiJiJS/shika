import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/library/models.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';

import 'browsing_session_test.dart' show SlowLibrary;

/// Keep these legacy feedback checks; the fixed route has its own end panel.
class LegacySlowLibrary extends SlowLibrary {
  @override
  bool get supportsFixedPreviews => false;
}

/// Native initialization intentionally never finishes during these tests.
class UnreadyVideo extends VideoPlayerPlatform {
  int next = 0;
  final events = <int, StreamController<VideoEvent>>{};
  @override
  Future<void> init() async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    events[++next] = StreamController<VideoEvent>.broadcast();
    return next;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    await events.remove(playerId)?.close();
  }
}

void main() {
  late SlowLibrary repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = LegacySlowLibrary();
    await repo.initialize();
    await repo.setScope(VideoQuery(), order: PlayOrder.sequential);
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });

  String visible(WidgetTester t) {
    final stage = t.widget<MovieStage>(find.byType(MovieStage));
    return stage.videos[stage.index].id;
  }

  Future<void> pump(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 350));
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
    await t.pump();
  }

  testWidgets('querying a pending file result leaves navigation enabled', (
    t,
  ) async {
    repo.fileQuery = Completer<void>();
    await t.pumpWidget(ShikaApp(repository: repo));
    await pump(t);
    await t.tap(find.text('查询结果'));
    await pump(t);
    expect(find.text('正在查询…'), findsOneWidget);
    expect(find.byKey(const Key('management-loading')), findsNothing);
    await t.tap(find.byKey(const Key('nav-settings')));
    await pump(t);
    expect(find.text('媒体目录'), findsOneWidget);
    repo.fileQuery!.complete();
    await pump(t);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  });

  testWidgets(
    'round completion floats without resizing and vanishes after three seconds',
    (t) async {
      await t.runAsync(
        () => repo.setScope(VideoQuery(folder: '/videos/收集/花草/横版')),
      );
      expect(repo.snapshot.round, hasLength(1));
      await t.pumpWidget(ShikaApp(repository: repo));
      await pump(t);
      final stage = find.byKey(const Key('video-stage'));
      final rect = t.getRect(stage);
      await t.drag(stage, const Offset(0, -500));
      await pump(t);
      final banner = find.byKey(const Key('round-notice'));
      expect(banner, findsOneWidget);
      expect(t.getRect(stage), rect);
      expect(t.getTopLeft(banner).dy, greaterThan(rect.top));
      await t.pump(const Duration(seconds: 4));
      expect(banner, findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );

  testWidgets(
    'uninitialized video and blocked position save never capture vertical swipes',
    (t) async {
      final ids = repo.snapshot.round;
      repo.navigation = Completer<void>();
      await t.pumpWidget(ShikaApp(repository: repo));
      await pump(t);
      for (var i = 1; i <= 3; i++) {
        await t.drag(
          find.byKey(const Key('video-stage')),
          const Offset(0, -500),
        );
        await pump(t);
        expect(visible(t), ids[i]);
      }
      expect(repo.current!.id, ids.first);
      repo.navigation!.complete();
      await pump(t);
      expect(visible(t), ids[3]);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );

  testWidgets(
    'delete notice is at top, replaced by next deletion, and expires after eight seconds',
    (t) async {
      final ids = repo.snapshot.round;
      await t.pumpWidget(ShikaApp(repository: repo));
      await pump(t);
      await t.tap(find.byTooltip('更多'));
      await pump(t);
      await t.tap(find.text('进入快速整理'));
      await pump(t);
      repo.deletion = Completer<void>();
      final videoRect = t.getRect(find.byKey(const Key('video-stage')));
      await t.tap(find.byKey(const Key('quick-delete')));
      await pump(t);
      expect(visible(t), ids[1]);
      final banner = find.byKey(const Key('delete-notice'));
      expect(banner, findsOneWidget);
      expect(t.getRect(find.byKey(const Key('video-stage'))), videoRect);
      expect(t.getTopLeft(banner).dy, greaterThan(videoRect.top));
      expect(t.getBottomLeft(banner).dy, lessThan(videoRect.top + 80));
      expect(find.byType(SnackBar), findsNothing);
      await t.pump(const Duration(seconds: 5));
      await t.tap(find.byKey(const Key('quick-delete')));
      await pump(t);
      expect(visible(t), ids[2]);
      expect(banner, findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      expect(banner, findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      expect(banner, findsNothing);
      repo.deletion!.complete();
      await pump(t);
      expect(banner, findsNothing); // A late response must not resurrect it.
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
}
