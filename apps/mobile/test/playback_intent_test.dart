import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/ui/player.dart';

class BufferingPlayer extends VideoPlayerController {
  BufferingPlayer() : super.asset('isolated-test') {
    value = const VideoPlayerValue(
      duration: Duration(seconds: 30),
      position: Duration(seconds: 3),
      size: Size(160, 96),
      isInitialized: true,
      isBuffering: true,
    );
  }
  final commands = <String>[];
  @override
  Future<void> setPlaybackSpeed(double speed) async {
    commands.add('speed:$speed');
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> play() async {
    commands.add('play');
    value = value.copyWith(isPlaying: true, isBuffering: false);
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    commands.add('seek');
    value = value.copyWith(position: position);
  }
}

void main() {
  testWidgets(
    'a transient device hint disappearing does not discard an open speed menu',
    (t) async {
      final controller = BufferingPlayer();
      const device = MethodChannel('video_viewer/playback');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        device,
        (call) async => call.method == 'restoreBrightness'
            ? null
            : {'brightness': .5, 'volume': .5, 'windowBrightness': -1.0},
      );
      addTearDown(() => messenger.setMockMethodCallHandler(device, null));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSurface(
              controller: controller,
              name: 'fullscreen',
              fullscreen: true,
              inlineControls: true,
              isPlayRequested: () => true,
            ),
          ),
        ),
      );
      await t.pump();
      final surface = t.getRect(find.byKey(const Key('video-gesture-surface')));
      await t.dragFrom(
        Offset(surface.left + 30, surface.center.dy),
        const Offset(0, -70),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('device-level-hint')), findsOneWidget);
      await t.tap(find.byTooltip('播放速度'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('1.5×'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('device-level-hint')), findsNothing);
      await t.tap(find.text('1.5×'));
      await t.pump(const Duration(milliseconds: 300));
      expect(controller.value.playbackSpeed, 1.5);
      await t.pumpWidget(const SizedBox());
      await controller.dispose();
    },
  );

  testWidgets(
    'inline paused controls stay visible and expose an explicit resume action',
    (t) async {
      final controller = BufferingPlayer();
      var requested = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSurface(
              controller: controller,
              name: 'inline',
              inlineControls: true,
              isPlayRequested: () => requested,
              onPlayRequested: (value) => requested = value,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('inline-play')), findsOneWidget);
      await t.tap(find.byKey(const Key('inline-play')));
      await t.pump();
      expect(requested, isTrue);
      expect(controller.value.isPlaying, isTrue);
      await t.tap(find.byKey(const Key('video-gesture-surface')));
      await t.pump();
      expect(requested, isFalse);
      expect(controller.value.isPlaying, isFalse);
      await t.pump(const Duration(seconds: 4));
      expect(
        find.byKey(const Key('inline-play')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byTooltip('播放速度').hitTestable(), findsOneWidget);
      final track = find.byKey(const Key('video-progress-touch'));
      await t.drag(track, Offset(t.getSize(track).width / 4, 0));
      await t.pump();
      expect(controller.value.position.inSeconds, inInclusiveRange(20, 25));
      expect(controller.value.isPlaying, isFalse);
      expect(requested, isFalse);
      await t.tap(find.byTooltip('播放速度'));
      await t.pumpAndSettle();
      await t.tap(find.text('1.5×'));
      await t.pumpAndSettle();
      expect(controller.value.playbackSpeed, 1.5);
      expect(controller.value.isPlaying, isFalse);
      await t.pumpWidget(const SizedBox());
      await controller.dispose();
    },
  );

  testWidgets(
    'a buffering play request can boost, but an explicit pause cannot',
    (t) async {
      final controller = BufferingPlayer();
      var requested = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSurface(
              controller: controller,
              name: 'buffering',
              isPlayRequested: () => requested,
              onPlayRequested: (playing) => requested = playing,
            ),
          ),
        ),
      );
      final surface = find.byKey(const Key('video-gesture-surface'));
      expect(controller.value.isPlaying, isFalse);
      final hold = await t.startGesture(t.getCenter(surface));
      await t.pump(const Duration(milliseconds: 650));
      expect(controller.value.playbackSpeed, 2);
      expect(controller.commands, contains('play'));
      await hold.up();
      await t.pump();
      expect(controller.value.playbackSpeed, 1);
      await t.tap(surface);
      await t.pump();
      expect(requested, isFalse);
      final commands = controller.commands.length;
      final pausedHold = await t.startGesture(t.getCenter(surface));
      await t.pump(const Duration(milliseconds: 650));
      expect(find.byKey(const Key('hold-speed-hint')), findsNothing);
      expect(controller.commands.length, commands);
      await pausedHold.up();
      await t.pumpWidget(const SizedBox());
      await controller.dispose();
    },
  );

  testWidgets(
    'seeking through a buffer preserves play intent; tapping pauses it',
    (t) async {
      final controller = BufferingPlayer();
      var requested = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSurface(
              controller: controller,
              name: 'buffering',
              isPlayRequested: () => requested,
              onPlayRequested: (playing) => requested = playing,
            ),
          ),
        ),
      );
      final surface = find.byKey(const Key('video-gesture-surface'));
      await t.drag(surface, const Offset(130, 0));
      await t.pump();
      expect(requested, isTrue);
      expect(
        controller.commands,
        containsAllInOrder(['pause', 'seek', 'play']),
      );
      controller.value = controller.value.copyWith(
        isPlaying: false,
        isBuffering: true,
      );
      await t.tap(surface);
      await t.pump();
      expect(requested, isFalse);
      expect(controller.commands.last, 'pause');
      await t.pumpWidget(const SizedBox());
      await controller.dispose();
    },
  );
}
