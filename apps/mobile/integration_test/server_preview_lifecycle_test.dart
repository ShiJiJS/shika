import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/device_controls.dart';
import 'package:video_viewer/ui/playback_session.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

class _LifecycleLog extends WidgetsBindingObserver {
  final events = <String>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    events.add(state.name);
    debugPrint('PREVIEW_NATIVE_LIFECYCLE:${state.name}');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'current preview owns native fullscreen, gestures and background resources',
    (t) async {
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
      final preferences = UiPreferences(videoOrder: PlayOrder.sequential);
      final lifecycle = _LifecycleLog();
      final device = PlaybackDeviceControls();
      final originalLevels = await device.levels();
      WidgetsBinding.instance.addObserver(lifecycle);
      PlaybackSession? session;
      var peakPlayers = 0, swipes = 0, homeCount = 0;
      final rounds = <String>[];
      void bounded() {
        final players = session?.debugPlayers ?? <VideoPlayerController>[];
        if (players.length > peakPlayers) peakPlayers = players.length;
        expect(players.length, lessThanOrEqualTo(3));
        expect(
          players.where((p) => p.value.isPlaying && p.value.volume > 0).length,
          lessThanOrEqualTo(1),
        );
      }

      Future<void> until(
        FutureOr<bool> Function() predicate,
        String reason,
      ) async {
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (!await predicate()) {
          bounded();
          if (DateTime.now().isAfter(end)) {
            debugPrint(
              'PREVIEW_LIFECYCLE_TIMEOUT:${jsonEncode({
                'reason': reason,
                'current': repo.current?.id,
                'players': session?.debugPlayers.map((p) => {'source': p.dataSource, 'initialized': p.value.isInitialized, 'playing': p.value.isPlaying, 'error': p.value.errorDescription}).toList(),
                'texts': t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList(),
              })}',
            );
            fail(reason);
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        await t.pump(const Duration(milliseconds: 100));
        bounded();
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder finder) async {
        await until(
          () => finder.hitTestable().evaluate().length == 1,
          'tap $finder',
        );
        await t.tap(finder.hitTestable());
        await t.pump(const Duration(milliseconds: 250));
      }

      Finder surface() =>
          find.byKey(const Key('video-gesture-surface')).hitTestable().last;
      VideoPlayerController player() =>
          t.widget<VideoPlayer>(find.byType(VideoPlayer).last).controller;
      bool controls() =>
          t
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.byKey(const Key('playback-controls')).last,
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity ==
          1;
      Future<void> reveal() async {
        if (!controls()) {
          final wasPlaying = player().value.isPlaying;
          await tap(surface());
          if (wasPlaying && !player().value.isPlaying) {
            await tap(find.widgetWithText(TextButton, '播放'));
          }
        }
        await until(controls, 'controls revealed');
      }

      Future<void> ready({bool playing = true}) => until(() {
        if (find.byType(VideoPlayer).evaluate().isEmpty) return false;
        final p = player();
        return p.value.isInitialized &&
            !p.value.size.isEmpty &&
            p.value.isPlaying == playing &&
            p.dataSource == repo.current?.source.location;
      }, 'visible native player, playing=$playing');
      Future<void> capture(String name) async {
        bounded();
        final view = t.view;
        final players = session?.debugPlayers ?? <VideoPlayerController>[];
        debugPrint(
          'FIDELITY_METRICS:${jsonEncode({
            'state': name,
            'physical': [view.physicalSize.width, view.physicalSize.height],
            'dpr': view.devicePixelRatio,
            'round': repo.playbackIdentity,
            'current': repo.current?.id,
            'position': repo.playbackPosition,
            'total': repo.playbackTotal,
            'preload': preferences.preloadAdjacent,
            'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
            'events': lifecycle.events,
            'levels': await device.levels(),
            'players': players.map((p) => {
              'source': p.dataSource,
              'initialized': p.value.isInitialized,
              'size': [p.value.size.width, p.value.size.height],
              'playing': p.value.isPlaying,
              'volume': p.value.volume,
              'speed': p.value.playbackSpeed,
              'position_ms': p.value.position.inMilliseconds,
            }).toList(),
          })}',
        );
        await control('/checkpoint/$name', post: true);
        await until(
          () async => (await control('/state'))['ack'] == true,
          'host capture $name',
        );
      }

      Future<void> nativeAction(String name) async {
        await control('/checkpoint/$name', post: true);
        final end = DateTime.now().add(const Duration(seconds: 20));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(end)) fail('Host action $name');
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }

      Future<void> background() async {
        await t.runAsync(() async {
          try {
            await nativeAction('lifecycle-device-home');
            final end = DateTime.now().add(const Duration(seconds: 15));
            while ((WidgetsBinding.instance.lifecycleState !=
                        AppLifecycleState.paused ||
                    session!.debugPlayers.isNotEmpty) &&
                DateTime.now().isBefore(end)) {
              await Future<void>.delayed(const Duration(milliseconds: 80));
            }
            expect(
              WidgetsBinding.instance.lifecycleState,
              AppLifecycleState.paused,
            );
            expect(session!.debugPlayers, isEmpty);
            debugPrint(
              'PREVIEW_BACKGROUND_RELEASED:${jsonEncode({'round': repo.playbackIdentity, 'current': repo.current!.id, 'events': lifecycle.events})}',
            );
          } finally {
            await nativeAction('lifecycle-device-foreground');
            final end = DateTime.now().add(const Duration(seconds: 15));
            while (WidgetsBinding.instance.lifecycleState !=
                    AppLifecycleState.resumed &&
                DateTime.now().isBefore(end)) {
              await Future<void>.delayed(const Duration(milliseconds: 80));
            }
            expect(
              WidgetsBinding.instance.lifecycleState,
              AppLifecycleState.resumed,
            );
          }
        });
        homeCount++;
        await t.pump(const Duration(milliseconds: 250));
        await ready(playing: false);
      }

      Future<void> enter() async {
        await tap(find.text('预览此范围'));
        await until(
          () => find.byType(MovieStage).evaluate().length == 1,
          'preview stage',
        );
        session = t.widget<MovieStage>(find.byType(MovieStage)).session!;
        rounds.add(repo.playbackIdentity);
        await ready();
        expect(repo.playbackTotal, 2);
        expect(repo.playbackPosition, 0);
      }

      Future<void> backToLibrary() async {
        final old = session!;
        await tap(find.byKey(const Key('preview-back')));
        await until(
          () =>
              find.byType(MovieStage).evaluate().isEmpty &&
              old.debugPlayers.isEmpty &&
              find.byType(VideoCatalogPage).evaluate().isNotEmpty,
          'library return releases all native players',
        );
      }

      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 250));
        await session?.close();
        await device.setVolume(originalLevels['volume']!);
        await device.restoreBrightness();
        WidgetsBinding.instance.removeObserver(lifecycle);
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect(
        'http://10.0.2.2',
        8768,
        'prototype-fidelity-owned-only',
      );
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      await until(
        () =>
            repo.libraryPreparation.value.ready &&
            find.text('预览此范围').hitTestable().evaluate().length == 1,
        'library ready',
      );
      expect(find.byType(MovieStage), findsNothing);
      expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 0);
      await capture('lifecycle-library');
      await enter();
      final identity = repo.playbackIdentity, first = repo.current!.id;
      await until(
        () => session!.debugPlayers.length == 2,
        'current and adjacent native controllers',
      );
      await capture('lifecycle-playing');
      await reveal();
      await tap(find.widgetWithText(TextButton, '暂停'));
      await ready(playing: false);
      final progress = t.getRect(find.byKey(const Key('video-progress-touch')));
      await t.dragFrom(
        Offset(progress.left + 20, progress.center.dy),
        Offset(progress.width * .55, 0),
      );
      await until(
        () => player().value.position.inMilliseconds > 1000,
        'paused native seek via track',
      );
      await tap(find.byTooltip('播放速度'));
      await tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<double> && w.value == 1.5,
        ),
      );
      await until(() => player().value.playbackSpeed == 1.5, 'base speed');
      expect(player().value.isPlaying, isFalse);
      await capture('lifecycle-paused');
      final beforeRotation = player(), pausedPosition = player().value.position;
      await tap(find.text('横向全屏'));
      await until(
        () =>
            t.view.physicalSize.width > t.view.physicalSize.height &&
            find.byKey(const Key('fullscreen-exit')).evaluate().isNotEmpty,
        'real landscape',
      );
      await ready(playing: false);
      expect(identical(player(), beforeRotation), isTrue);
      expect(player().value.position, pausedPosition);
      expect(player().value.playbackSpeed, 1.5);
      await capture('lifecycle-fullscreen-paused');
      await tap(find.widgetWithText(TextButton, '播放'));
      await ready();
      await capture('lifecycle-fullscreen-playing');
      await device.setBrightness(.35);
      await device.setVolume(.6);
      // Read the actual platform levels before each touch; no mocked channel.
      final levelsBefore = await device.levels();
      final rect = t.getRect(surface());
      await t.dragFrom(
        Offset(rect.left + rect.width * .2, rect.center.dy),
        const Offset(0, -70),
      );
      await until(
        () async =>
            (await device.levels())['brightness']! >
            levelsBefore['brightness']!,
        'native left brightness',
      );
      await t.dragFrom(
        Offset(rect.left + rect.width * .8, rect.center.dy),
        const Offset(0, 70),
      );
      await until(
        () async =>
            (await device.levels())['volume']! < levelsBefore['volume']!,
        'native right volume',
      );
      await capture('lifecycle-device-levels');
      final hold = await t.startGesture(
        Offset(rect.left + rect.width * .4, rect.top + rect.height * .3),
      );
      await until(() => player().value.playbackSpeed == 2, 'temporary 2x');
      await capture('lifecycle-boost');
      await background();
      await hold.cancel();
      expect(repo.playbackIdentity, identity);
      expect(repo.current!.id, first);
      expect(player().value.playbackSpeed, 1.5);
      expect(
        (await device.levels())['windowBrightness'],
        originalLevels['windowBrightness'],
      );
      await capture('lifecycle-fullscreen-recovered');
      await t.runAsync(() => nativeAction('lifecycle-device-back'));
      await until(
        () =>
            t.view.physicalSize.height > t.view.physicalSize.width &&
            find.byKey(const Key('fullscreen-exit')).evaluate().isEmpty,
        'native back exits only fullscreen',
      );
      await ready(playing: false);
      expect(repo.playbackIdentity, identity);
      expect(find.byType(MovieStage), findsOneWidget);
      await capture('lifecycle-inline-restored');
      await reveal();
      await tap(find.widgetWithText(TextButton, '播放'));
      await ready();
      await background();
      expect(repo.current!.id, first);
      expect(repo.playbackIdentity, identity);
      await capture('lifecycle-inline-recovered');
      await reveal();
      await tap(find.widgetWithText(TextButton, '播放'));
      await ready();
      for (var i = 0; i < 6; i++) {
        final next = i.isEven;
        await t.fling(surface(), Offset(0, next ? -400 : 400), 1600);
        await until(
          () => repo.playbackPosition == (next ? 1 : 0),
          'swipe committed',
        );
        await ready();
        swipes++;
        expect(repo.playbackIdentity, identity);
      }
      expect(repo.current!.id, first);
      await capture('lifecycle-swipes');
      await backToLibrary();
      await tap(find.byKey(const Key('nav-settings')));
      final preload = find.byKey(const Key('preload-setting'));
      await t.ensureVisible(preload);
      await tap(preload);
      await until(
        () => !preferences.preloadAdjacent,
        'UI disables adjacent preparation',
      );
      await capture('lifecycle-preload-off');
      await tap(find.byKey(const Key('nav-library')));
      await enter();
      expect(repo.playbackIdentity, isNot(identity));
      await until(
        () => session!.debugPlayers.length == 1,
        'preload off keeps one decoder',
      );
      await capture('lifecycle-single-decoder');
      await t.fling(surface(), const Offset(0, -400), 1600);
      await until(() => repo.playbackPosition == 1, 'single decoder swipe');
      await ready();
      swipes++;
      expect(session!.debugPlayers.length, 1);
      await capture('lifecycle-single-swiped');
      await backToLibrary();
      expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 2);
      await capture('lifecycle-return');
      debugPrint(
        'PREVIEW_LIFECYCLE_RESULT:${jsonEncode({'rounds': rounds, 'peak_players': peakPlayers, 'swipes': swipes, 'home_count': homeCount, 'events': lifecycle.events, 'original_levels': originalLevels})}',
      );
      debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
    },
  );
}
