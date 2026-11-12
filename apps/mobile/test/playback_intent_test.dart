import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:shika/ui/player.dart';

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

class DelayedSeekPlayer extends BufferingPlayer {
  final seeks = <Completer<void>>[];
  @override
  Future<void> seekTo(Duration position) async {
    commands.add('seek');
    final pending = Completer<void>();
    seeks.add(pending);
    await pending.future;
    value = value.copyWith(position: position);
  }
}

void main() {
  for (final externalIntent in [false, true]) {
    testWidgets(
      'pause supersedes a pending seek; external intent=$externalIntent',
      (t) async {
        final controller = DelayedSeekPlayer();
        var requested = true;
        await controller.play();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerSurface(
                controller: controller,
                name: 'delayed seek',
                isPlayRequested: externalIntent ? () => requested : null,
                onPlayRequested: externalIntent
                    ? (value) => requested = value
                    : null,
              ),
            ),
          ),
        );
        final surface = find.byKey(const Key('video-gesture-surface'));
        await t.drag(surface, const Offset(120, 0));
        await t.pump();
        expect(controller.seeks, hasLength(1));
        await t.tap(surface);
        await t.pump();
        final playCount = controller.commands.where((e) => e == 'play').length;
        controller.seeks.single.complete();
        await t.pump();
        expect(
          controller.commands.where((e) => e == 'play'),
          hasLength(playCount),
        );
        expect(controller.value.isPlaying, isFalse);
        if (externalIntent) expect(requested, isFalse);
        await t.pumpWidget(const SizedBox());
        await controller.dispose();
      },
    );

    testWidgets(
      'only the latest seek resumes playback; external intent=$externalIntent',
      (t) async {
        final controller = DelayedSeekPlayer();
        await controller.play();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerSurface(
                controller: controller,
                name: 'consecutive seeks',
                isPlayRequested: externalIntent ? () => true : null,
              ),
            ),
          ),
        );
        final surface = find.byKey(const Key('video-gesture-surface'));
        await t.drag(surface, const Offset(120, 0));
        await t.pump();
        await t.drag(surface, const Offset(80, 0));
        await t.pump();
        expect(controller.seeks, hasLength(2));
        final playCount = controller.commands.where((e) => e == 'play').length;
        controller.seeks.first.complete();
        await t.pump();
        expect(
          controller.commands.where((e) => e == 'play'),
          hasLength(playCount),
        );
        expect(controller.value.isPlaying, isFalse);
        controller.seeks.last.complete();
        await t.pump();
        expect(
          controller.commands.where((e) => e == 'play'),
          hasLength(playCount + 1),
        );
        expect(controller.value.isPlaying, isTrue);
        await t.pumpWidget(const SizedBox());
        await controller.dispose();
      },
    );
  }

  for (final background in [false, true]) {
    testWidgets(
      'pending seek cannot resume after an interruption; background=$background',
      (t) async {
        final controller = DelayedSeekPlayer();
        await controller.play();
        Future<void> show(bool enabled) => t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerSurface(
                controller: controller,
                name: 'interrupted seek',
                interactionsEnabled: enabled,
                isPlayRequested: () => true,
              ),
            ),
          ),
        );
        await show(true);
        await t.drag(
          find.byKey(const Key('video-gesture-surface')),
          const Offset(120, 0),
        );
        await t.pump();
        if (background) {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await t.pump();
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pump();
        } else {
          await show(false);
          await show(true);
        }
        final playCount = controller.commands.where((e) => e == 'play').length;
        controller.seeks.single.complete();
        await t.pump();
        expect(
          controller.commands.where((e) => e == 'play'),
          hasLength(playCount),
        );
        expect(controller.value.isPlaying, isFalse);
        await t.pumpWidget(const SizedBox());
        await controller.dispose();
      },
    );
  }

  for (final interrupt in [
    'disabled',
    'background',
    'pointer cancel',
    'release',
  ]) {
    testWidgets(
      'device level write respects $interrupt with a native write pending',
      (t) async {
        final controller = BufferingPlayer();
        const channel = MethodChannel('video_viewer/playback');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final firstWrite = Completer<void>();
        final writes = <double>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'restoreBrightness') return null;
          if (call.method == 'brightness' || call.method == 'volume') {
            writes.add((call.arguments['value'] as num).toDouble());
            if (writes.length == 1) {
              await firstWrite.future;
              if (interrupt != 'release') {
                throw PlatformException(code: 'interrupted-write');
              }
            }
          }
          return {'brightness': .5, 'volume': .5, 'windowBrightness': -1.0};
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        Future<void> show(bool enabled) => t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerSurface(
                controller: controller,
                name: 'device gesture',
                fullscreen: true,
                interactionsEnabled: enabled,
              ),
            ),
          ),
        );
        await show(true);
        await t.pump();
        final rect = t.getRect(find.byKey(const Key('video-gesture-surface')));
        final gesture = await t.startGesture(
          Offset(rect.left + 30, rect.center.dy),
        );
        await gesture.moveBy(const Offset(0, -40));
        await t.pump();
        await gesture.moveBy(const Offset(0, -30));
        await t.pump();
        expect(writes, hasLength(1));
        await gesture.moveBy(const Offset(0, -30));
        await t.pump();
        if (interrupt == 'disabled') {
          await show(false);
          await gesture.moveBy(const Offset(0, -30));
          await t.pump();
          await show(true);
        } else if (interrupt == 'background') {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await t.pump();
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pump();
          await gesture.moveBy(const Offset(0, -30));
          await t.pump();
        } else if (interrupt == 'pointer cancel') {
          await gesture.cancel();
          await t.pump();
        } else {
          await gesture.up();
          await t.pump();
        }
        firstWrite.complete();
        await t.pump();
        await t.pump();
        expect(writes, hasLength(interrupt == 'release' ? 2 : 1));
        if (interrupt != 'release') {
          expect(find.byKey(const Key('device-level-hint')), findsNothing);
        }
        if (interrupt == 'disabled' || interrupt == 'background') {
          await gesture.up();
        }
        await t.pumpWidget(const SizedBox());
        await controller.dispose();
      },
    );
  }

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
