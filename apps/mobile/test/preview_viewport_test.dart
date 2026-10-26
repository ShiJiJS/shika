import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/features/preview/video_preview_route.dart';
import 'package:video_viewer/features/library/browse_context.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'player_lifecycle_test.dart' show ReadyVideo, frames;

void main() {
  for (final profile in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 2.0),
  ]) {
    testWidgets('preview controls and range remain usable at $profile', (
      t,
    ) async {
      final previousError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('PREVIEW_VIEWPORT_ERROR:$details');
        previousError?.call(details);
      };
      final oldPlatform = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = ReadyVideo();
      final repo = DemoLibraryRepository(
        MemoryStateStore(),
        latency: Duration.zero,
      );
      final prefs = UiPreferences(preloadAdjacent: false);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = profile.$1;
      t.platformDispatcher.textScaleFactorTestValue = profile.$2;
      addTearDown(() {
        FlutterError.onError = previousError;
        repo.dispose();
        prefs.dispose();
        VideoPlayerPlatform.instance = oldPlatform;
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo, preferences: prefs));
      await frames(t);
      await t.tap(find.text('预览此范围'));
      await frames(t);
      expect(find.byType(MovieStage), findsOneWidget);
      expect(t.takeException(), isNull);
      final controls = find.byKey(const Key('playback-controls'));
      final play = find
          .descendant(of: controls, matching: find.byType(TextButton))
          .first;
      await t.tap(play);
      await frames(t);
      expect(
        t
            .widget<MovieStage>(find.byType(MovieStage))
            .session!
            .debugPlayers
            .single
            .value
            .isPlaying,
        isFalse,
      );
      final center = find.byKey(const Key('inline-play'));
      if (center.evaluate().isNotEmpty) {
        expect(center.hitTestable(), findsOneWidget);
        expect(t.getRect(center).overlaps(t.getRect(controls)), isFalse);
      }
      expect(play.hitTestable(), findsOneWidget);
      await t.tap(play);
      await frames(t);
      final identity = repo.playbackIdentity;
      final current = repo.current!.id;
      await t.tap(find.byKey(const Key('preview-quick')));
      await frames(t);
      expect(
        find.byKey(const Key('preview-quick-delete')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('preview-quick')));
      await frames(t);
      await t.tap(find.byKey(const Key('preview-scope')));
      await frames(t);
      expect(find.byKey(const Key('preview-queue')), findsOneWidget);
      final coveredPlay = find
          .descendant(
            of: find.byKey(const Key('playback-controls')),
            matching: find.byType(TextButton),
          )
          .first;
      expect(t.widget<TextButton>(coveredPlay).onPressed, isNull);
      expect(
        t
            .widget<PopupMenuButton<double>>(
              find.descendant(
                of: find.byKey(const Key('playback-controls')),
                matching: find.byType(PopupMenuButton<double>),
              ),
            )
            .enabled,
        isFalse,
      );
      expect(t.takeException(), isNull);
      expect(repo.playbackIdentity, identity);
      expect(repo.current!.id, current);
      await t.tap(find.byTooltip('关闭面板'));
      await frames(t);
      await t.tap(find.byKey(const Key('preview-back')));
      await frames(t);
      expect(find.byKey(const Key('video-preview-route')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
    testWidgets(
      'long range context scrolls without hiding the current item at $profile',
      (t) async {
        final repo = DemoLibraryRepository(
          MemoryStateStore(),
          latency: Duration.zero,
        );
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = profile.$1;
        t.platformDispatcher.textScaleFactorTestValue = profile.$2;
        addTearDown(() {
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await repo.initialize();
        await t.runAsync(
          () =>
              repo.beginPreview(VideoEntryScope(), order: PlayOrder.sequential),
        );
        final last = repo.snapshot.round.last;
        await t.runAsync(
          () => repo.beginPreview(
            VideoEntryScope(),
            anchor: last,
            order: PlayOrder.sequential,
          ),
        );
        final round = repo.playbackIdentity;
        final members = [...repo.snapshot.round];
        final source = List.filled(
          8,
          '媒体库 · 很长的目录名称 · # 花卉风景 · “山间的花园”',
        ).join(' · ');
        String? picked;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => paperSheet(
                    context,
                    PreviewQueueSheet(
                      repository: repo,
                      sourceLabel: source,
                      onOrder: (order) => repo.changePreviewOrder(order),
                      onPick: (id) async {
                        picked = id;
                      },
                    ),
                  ),
                  child: const Text('打开范围'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('打开范围'));
        await frames(t);
        expect(t.takeException(), isNull);
        final current = find.byKey(Key('queue-video-$last'));
        expect(current.hitTestable(), findsOneWidget);
        final scroll = t.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('preview-queue')),
            matching: find.byType(Scrollable),
          ),
        );
        scroll.position.jumpTo(0);
        await frames(t);
        expect(find.text('$source · ${members.length} 个视频'), findsOneWidget);
        expect(find.byTooltip('关闭面板').hitTestable(), findsOneWidget);
        await Scrollable.ensureVisible(
          t.element(find.byKey(const Key('queue-order-sequential'))),
          alignment: .5,
        );
        await frames(t);
        await t.tap(find.byKey(const Key('queue-order-sequential')));
        await frames(t);
        expect(repo.playbackIdentity, round);
        expect(repo.snapshot.round, members);
        await Scrollable.ensureVisible(t.element(current), alignment: .5);
        await frames(t);
        await t.tap(current);
        await frames(t);
        expect(picked, last);
        expect(find.byKey(const Key('preview-queue')), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
  }
  for (final failSave in [false, true]) {
    testWidgets(
      'preview theme persists or preserves previous preference on failure=$failSave',
      (t) async {
        final previous = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = ReadyVideo();
        final directory = (await t.runAsync(
          () => Directory.systemTemp.createTemp('preview-theme-'),
        ))!;
        final file = File(
          failSave ? directory.path : '${directory.path}/appearance.json',
        );
        final preferences = UiPreferences(file: file, preloadAdjacent: false);
        final repo = DemoLibraryRepository(
          MemoryStateStore(),
          latency: Duration.zero,
        );
        addTearDown(() async {
          repo.dispose();
          preferences.dispose();
          VideoPlayerPlatform.instance = previous;
          await t.runAsync(() => directory.delete(recursive: true));
        });
        await repo.initialize();
        final origin = VideoBrowseContext(
          query: VideoQuery(
            orientation: 'landscape',
            duration: 'short',
            type: 'MP4',
          ),
        );
        await t.runAsync(
          () => repo.beginPreview(origin.entry, order: PlayOrder.sequential),
        );
        final round = repo.playbackIdentity,
            current = repo.current!.id,
            members = [...repo.snapshot.round];
        await t.pumpWidget(
          ListenableBuilder(
            listenable: preferences,
            builder: (context, _) => MaterialApp(
              theme: preferences.dark ? Paper.darkTheme : Paper.theme,
              home: VideoPreviewRoute(
                repository: repo,
                preferences: preferences,
                origin: origin,
              ),
            ),
          ),
        );
        await frames(t);
        expect(find.text('媒体库 · 横版 · 10 秒以内 · MP4'), findsOneWidget);
        await t.tap(find.byTooltip('视频操作'));
        await frames(t);
        await t.tap(find.text('切换暗黑模式'));
        await frames(t);
        expect(preferences.dark, !failSave);
        if (failSave) {
          expect(find.byKey(const Key('preview-error')), findsOneWidget);
        } else {
          final saved = await t.runAsync(() => UiPreferences.load(file: file));
          expect(saved!.dark, isTrue);
          saved.dispose();
          expect(
            Theme.of(t.element(find.byKey(const Key('video-preview-route'))))
                .brightness,
            Brightness.dark,
          );
        }
        expect(repo.playbackIdentity, round);
        expect(repo.current!.id, current);
        expect(repo.snapshot.round, members);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
  }
}
