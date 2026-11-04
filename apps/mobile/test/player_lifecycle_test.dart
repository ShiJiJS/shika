import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/library/models.dart';
import 'package:shika/ui/playback_session.dart';
import 'package:shika/ui/player.dart';

class ReadyVideo extends VideoPlayerPlatform {
  var next = 0;
  final events = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  @override
  Future<void> init() async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool value) async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    final id = ++next;
    late StreamController<VideoEvent> stream;
    stream = StreamController.broadcast(
      onListen: () {
        scheduleMicrotask(
          () => stream.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 30),
              size: const Size(160, 96),
            ),
          ),
        );
      },
    );
    events[id] = stream;
    positions[id] = Duration.zero;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;
  @override
  Widget buildView(int playerId) => const SizedBox();
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
  @override
  Future<void> dispose(int playerId) async => events.remove(playerId)?.close();
}

Future<void> frames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final preload in [false, true]) {
    testWidgets(
      'queue selection starts a new video after suspension, preserving current pause; preload=$preload',
      (t) async {
        final original = VideoPlayerPlatform.instance;
        final platform = ReadyVideo();
        VideoPlayerPlatform.instance = platform;
        final session = PlaybackSession();
        addTearDown(() {
          unawaited(session.close());
          VideoPlayerPlatform.instance = original;
        });
        final videos = [
          for (final id in ['first', 'second'])
            LibraryVideo(
              id: id,
              path: '/fixture/$id.mp4',
              rootId: 'fixture',
              portrait: false,
              source: MediaSource(
                'https://fixture.invalid/$id.mp4',
                asset: false,
              ),
              poster: '',
            ),
        ];
        Future<void> show(int index, {bool suspended = false}) async {
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MovieStage(
                  videos: videos,
                  index: index,
                  suspended: suspended,
                  session: session,
                  inlineControls: true,
                  preloadAdjacent: preload,
                  onStep: (_) async => false,
                ),
              ),
            ),
          );
          await frames(t);
        }

        await show(0);
        final first = session.debugPlayers.singleWhere(
          (p) => p.dataSource.endsWith('/first.mp4'),
        );
        expect(first.value.isPlaying, isTrue);
        await show(0, suspended: true);
        expect(first.value.isPlaying, isFalse);
        await show(0);
        expect(first.value.isPlaying, isTrue);
        await t.tap(
          find.byKey(const Key('video-gesture-surface')).hitTestable(),
        );
        await frames(t);
        expect(first.value.isPlaying, isFalse);
        await show(0, suspended: true);
        await show(0);
        expect(first.value.isPlaying, isFalse);
        await show(0, suspended: true);
        await show(1, suspended: true);
        expect(session.debugPlayers.every((p) => !p.value.isPlaying), isTrue);
        await show(1);
        expect(
          session.debugPlayers
              .singleWhere((p) => p.dataSource.endsWith('/second.mp4'))
              .value
              .isPlaying,
          isTrue,
        );
        expect(
          session.debugPlayers.where((p) => p.value.isPlaying),
          hasLength(1),
        );
        await t.pumpWidget(const SizedBox());
        await frames(t);
        final closed = session.close();
        await frames(t);
        await closed;
        expect(platform.events, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final playing in [true, false]) {
    testWidgets(
      'fullscreen keeps play intent=$playing across rotation focus changes; real background still pauses',
      (t) async {
        final original = VideoPlayerPlatform.instance;
        final platform = ReadyVideo();
        VideoPlayerPlatform.instance = platform;
        final session = PlaybackSession();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            t.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          }
          return null;
        });
        const device = MethodChannel('video_viewer/playback');
        messenger.setMockMethodCallHandler(
          device,
          (call) async => call.method == 'restoreBrightness'
              ? null
              : {'brightness': .5, 'volume': .5, 'windowBrightness': -1.0},
        );
        addTearDown(() {
          unawaited(session.close());
          VideoPlayerPlatform.instance = original;
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          messenger.setMockMethodCallHandler(device, null);
        });
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MovieStage(
                videos: [
                  LibraryVideo(
                    id: 'network',
                    path: '/fixture/video.mp4',
                    rootId: 'fixture',
                    portrait: false,
                    source: const MediaSource(
                      'https://fixture.invalid/video.mp4',
                      asset: false,
                    ),
                    poster: '',
                  ),
                ],
                index: 0,
                session: session,
                inlineControls: true,
                preloadAdjacent: false,
                onStep: (_) async => false,
              ),
            ),
          ),
        );
        await frames(t);
        expect(session.debugPlayers.single.value.isPlaying, isTrue);
        final beforeRotation = session.debugPlayers.single;
        await beforeRotation.seekTo(const Duration(seconds: 7));
        if (!playing) {
          await t.tap(find.byKey(const Key('video-gesture-surface')));
          await frames(t);
        }
        await t.tap(find.text('横向全屏'));
        await frames(t);
        expect(find.byKey(const Key('fullscreen-exit')), findsOneWidget);
        expect(session.debugPlayers.single.value.isPlaying, playing);
        expect(identical(session.debugPlayers.single, beforeRotation), isTrue);
        expect(
          session.debugPlayers.single.value.position,
          const Duration(seconds: 7),
        );
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        var released = false;
        try {
          for (
            var index = 0;
            index < 20 && session.debugPlayers.isNotEmpty;
            index++
          ) {
            await t.pump(const Duration(milliseconds: 10));
          }
          released = session.debugPlayers.isEmpty;
        } finally {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
        expect(released, isTrue);
        await frames(t);
        expect(session.debugPlayers.single.value.isPlaying, isFalse);
        await t.tap(find.byKey(const Key('fullscreen-exit')));
        await frames(t);
        expect(session.debugPlayers.single.value.isPlaying, isFalse);
        await t.pumpWidget(const SizedBox());
        await frames(t);
        final closed = session.close();
        await frames(t);
        await closed;
        expect(platform.events, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
