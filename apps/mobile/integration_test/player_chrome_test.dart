import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/device_controls.dart';
import 'package:video_viewer/ui/preferences.dart';
import 'package:video_viewer/ui/player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late DemoLibraryRepository repo;
  final surface = find.byKey(const Key('video-gesture-surface')).last;
  final stage = find.byKey(const Key('video-stage'));
  VideoPlayerController player(WidgetTester t) =>
      t.widget<VideoPlayer>(find.byType(VideoPlayer).last).controller;
  bool controlsVisible(WidgetTester t) =>
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
  Future<void> until(
    WidgetTester t,
    bool Function() ready, [
    String reason = 'player UI',
  ]) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tap(WidgetTester t, Finder target) async {
    await until(t, () => target.hitTestable().evaluate().isNotEmpty);
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> start(
    WidgetTester t, {
    String? video,
    UiPreferences? preferences,
  }) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    repo = DemoLibraryRepository(MemoryStateStore());
    await repo.initialize();
    if (video != null) await repo.openVideo(video);
    await t.pumpWidget(
      VideoViewerApp(repository: repo, preferences: preferences),
    );
    await until(
      t,
      () =>
          find.byType(VideoPlayer).evaluate().isNotEmpty &&
          find
              .byWidgetPredicate(
                (w) => w is PlayerSurface && w.interactionsEnabled,
              )
              .evaluate()
              .isNotEmpty &&
          player(t).value.isPlaying,
    );
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 300));
      repo.dispose();
    });
  }

  Future<void> reveal(WidgetTester t) async {
    if (!controlsVisible(t)) {
      final progress = find.byKey(const Key('video-progress-touch')).last;
      await t.drag(progress, const Offset(35, 0));
      await until(t, () => controlsVisible(t));
    }
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
    'portrait hides progress, seeks both ways and overlays title and tags',
    (t) async {
      await start(t);
      final current = repo.current!.id;
      expect(controlsVisible(t), isFalse);
      final stageRect = t.getRect(stage);
      expect(
        stageRect.contains(
          t.getCenter(find.byKey(const Key('browse-video-name'))),
        ),
        isTrue,
      );
      expect(
        stageRect.contains(t.getCenter(find.byKey(const Key('filter-tag-自然')))),
        isTrue,
      );
      await tap(t, surface);
      expect(player(t).value.isPlaying, isFalse);
      expect(controlsVisible(t), isFalse);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      await player(t).seekTo(const Duration(milliseconds: 500));
      await t.drag(surface, const Offset(160, 0));
      await until(
        t,
        () =>
            controlsVisible(t) &&
            player(t).value.position.inMilliseconds > 1500,
      );
      expect(player(t).value.isPlaying, isFalse);
      final forward = player(t).value.position;
      await t.drag(surface, const Offset(-160, 0));
      await until(t, () => player(t).value.position < forward);
      expect(repo.current!.id, current);
      await until(t, () => !controlsVisible(t), 'portrait controls auto hide');
      await reveal(t);
      expect(controlsVisible(t), isTrue);
      await until(t, () => !controlsVisible(t));
      await tap(t, find.byKey(const Key('filter-tag-自然')));
      await until(t, () => repo.snapshot.query.tags.contains('自然'));
      expect(repo.query().every((v) => v.tags.contains('自然')), isTrue);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'landscape auto hides controls and changes native volume and window brightness',
    (t) async {
      final device = PlaybackDeviceControls();
      final original = await device.levels();
      addTearDown(() async {
        await device.setVolume(original['volume']!);
        await device.restoreBrightness();
      });
      await device.setVolume(.4);
      await device.setBrightness(.35);
      await start(t, video: 'v2');
      final controller = player(t);
      await tap(t, find.text('横屏'));
      await until(
        t,
        () => t.view.physicalSize.width > t.view.physicalSize.height,
      );
      await until(
        t,
        () => find.byKey(const Key('fullscreen-exit')).evaluate().isNotEmpty,
      );
      expect(controlsVisible(t), isTrue);
      expect(find.widgetWithText(FilledButton, '返回'), findsNothing);
      await until(t, () => !controlsVisible(t), 'landscape controls auto hide');
      final playing = controller.value.isPlaying;
      await tap(t, surface);
      expect(controlsVisible(t), isTrue);
      expect(controller.value.isPlaying, playing);
      await controller.pause();
      await controller.seekTo(const Duration(seconds: 1));
      await t.drag(surface, const Offset(170, 0));
      await until(t, () => controller.value.position.inMilliseconds > 1000);
      final before = controller.value.position;
      await t.drag(surface, const Offset(-170, 0));
      await until(t, () => controller.value.position < before);
      final rect = t.getRect(surface);
      final brightness = await device.levels();
      await t.dragFrom(
        Offset(rect.left + rect.width * .2, rect.center.dy),
        const Offset(0, -95),
      );
      await t.pump(const Duration(milliseconds: 300));
      final brighter = await device.levels();
      expect(brighter['brightness']!, greaterThan(brightness['brightness']!));
      expect(brighter['windowBrightness']!, greaterThanOrEqualTo(0));
      final volume = brighter['volume']!;
      await t.dragFrom(
        Offset(rect.left + rect.width * .8, rect.center.dy),
        const Offset(0, -95),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect((await device.levels())['volume']!, greaterThan(volume));
      await t.dragFrom(
        Offset(rect.left + rect.width * .8, rect.center.dy),
        const Offset(0, 95),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(
        (await device.levels())['volume']!,
        lessThanOrEqualTo(volume + .07),
      );
      if (!controlsVisible(t)) await tap(t, surface);
      await tap(t, find.byKey(const Key('fullscreen-exit')));
      await until(
        t,
        () => t.view.physicalSize.height > t.view.physicalSize.width,
      );
      expect(
        (await device.levels())['windowBrightness'],
        original['windowBrightness'],
      );
      expect(identical(player(t), controller), isTrue);
      expect(repo.current!.id, 'v2');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'dark mode menu and settings agree and the preference survives reopening',
    (t) async {
      final file = File(
        '${Directory.systemTemp.path}/video-viewer-theme-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      final preferences = UiPreferences(file: file);
      addTearDown(() async {
        preferences.dispose();
        if (await file.exists()) await file.delete();
      });
      await start(t, preferences: preferences);
      final controller = player(t);
      final first = repo.current!.id;
      await tap(t, find.byTooltip('更多'));
      await tap(t, find.text('切换暗黑模式'));
      await until(t, () => preferences.dark);
      await t.pump(const Duration(milliseconds: 300));
      expect(Theme.of(t.element(stage)).brightness, Brightness.dark);
      expect(identical(player(t), controller), isTrue);
      expect(repo.current!.id, first);
      await until(
        t,
        () => controller.value.isPlaying,
        'theme preserves requested playback',
      );
      expect(controller.value.isPlaying, isTrue);
      await tap(t, find.byKey(const Key('nav-settings')));
      expect(
        t
            .widget<SwitchListTile>(find.byKey(const Key('dark-mode-setting')))
            .value,
        isTrue,
      );
      final reopened = await UiPreferences.load(file: file);
      expect(reopened.dark, isTrue);
      reopened.dispose();
      await tap(t, find.byKey(const Key('dark-mode-setting')));
      await until(t, () => !preferences.dark);
      await tap(t, find.byTooltip('更多'));
      expect(find.text('切换暗黑模式'), findsOneWidget);
      await tap(t, find.text('切换暗黑模式'));
      await until(t, () => preferences.dark);
      for (final tab in ['library', 'tags', 'settings']) {
        await tap(t, find.byKey(Key('nav-$tab')));
        expect(
          Theme.of(t.element(find.byKey(Key('nav-$tab')))).brightness,
          Brightness.dark,
        );
      }
      expect(t.takeException(), isNull);
    },
  );
}
