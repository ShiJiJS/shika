import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/features/preview/video_preview_route.dart';
import 'package:shika/features/library/browse_context.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/media_layout.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';
import 'package:shika/ui/preferences.dart';

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
      await t.pumpWidget(ShikaApp(repository: repo, preferences: prefs));
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
      expect(
        t.widget<Text>(find.byKey(const Key('preview-queue-title'))).data,
        isIn(['本次预览范围', '本次预览\n范围']),
      );
      final queueCount = find.byKey(const Key('preview-queue-count'));
      expect(
        t.getSize(queueCount).height,
        closeTo(
          MediaLayout.line(
            t.element(queueCount),
            '${repo.playbackTotal} 个视频',
            DefaultTextStyle.of(t.element(queueCount)).style,
          ),
          .1,
        ),
      );
      expect(
        t.getSize(find.byKey(const Key('preview-queue-frame'))).width,
        profile.$1.width,
      );
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
                matching: find.bySubtype<PopupMenuButton<double>>(),
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
      for (
        var step = 0;
        step <= repo.playbackTotal &&
            find.byKey(const Key('preview-end-return')).evaluate().isEmpty;
        step++
      ) {
        await t.tap(find.byKey(const Key('preview-next')));
        await frames(t);
      }
      final count = find.text('共 ${repo.playbackTotal} 个视频');
      expect(count, findsOneWidget);
      expect(
        t.getSize(count).height,
        closeTo(
          MediaLayout.line(
            t.element(count),
            '共 ${repo.playbackTotal} 个视频',
            DefaultTextStyle.of(t.element(count)).style,
          ),
          .1,
        ),
      );
      await t.tap(find.byKey(const Key('preview-end-return')));
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
        expect(find.text(source), findsOneWidget);
        expect(find.text('${members.length} 个视频'), findsOneWidget);
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
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final total in [2, 5000]) {
      testWidgets('range fits $total entries without eager metadata at $size', (
        t,
      ) async {
        final repo = QueueWindowRepository(total);
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = size;
        addTearDown(() {
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await repo.initialize();
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
                      sourceLabel: '媒体库 · 全部视频',
                      onOrder: (_) async {},
                      onPick: (_) async {},
                    ),
                    constraints: const BoxConstraints(
                      maxWidth: double.infinity,
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
        final frame = t.getSize(find.byKey(const Key('preview-queue-frame')));
        expect(frame.width, size.width);
        expect(
          frame.height,
          lessThanOrEqualTo(size.height * (size.height <= 700 ? .92 : .88)),
        );
        expect(
          find.byKey(Key('queue-video-window-${total - 1}')).hitTestable(),
          findsOneWidget,
        );
        if (total == 2 && size.width == 390) {
          expect(frame.height, lessThan(520));
          expect(
            find.byKey(const Key('preview-queue-note')).hitTestable(),
            findsOneWidget,
          );
        }
        expect(repo.reads, isNotEmpty);
        expect(repo.reads.every((r) => r.$2 == 48), isTrue);
        expect(repo.reads.length, lessThanOrEqualTo(4));
        expect(find.byTooltip('关闭面板').hitTestable(), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      });
    }
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
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!(failSave
            ? find.byKey(const Key('preview-error')).evaluate().isNotEmpty
            : preferences.dark)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Theme preference save did not settle');
          }
          // File flush completes on real IO, independent of pumped frame time.
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await t.pump(const Duration(milliseconds: 16));
        }
        await t.pumpAndSettle();
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

class QueueWindowRepository extends DemoLibraryRepository {
  QueueWindowRepository(this.count)
    : super(MemoryStateStore(), latency: Duration.zero);
  final int count;
  final reads = <(int, int)>[];
  LibraryVideo video(int index) {
    final sample = snapshot.videos.first;
    return LibraryVideo(
      id: 'window-$index',
      path: '/videos/$index.mp4',
      rootId: sample.rootId,
      portrait: sample.portrait,
      source: sample.source,
      poster: sample.poster,
    );
  }

  @override
  LibraryVideo? get current => video(count - 1);
  @override
  int get playbackTotal => count;
  @override
  int get playbackPosition => count - 1;
  @override
  Future<VideoPage> loadPlaybackVideos({int offset = 0, int limit = 48}) async {
    reads.add((offset, limit));
    return VideoPage(
      items: [
        for (var i = offset; i < count && i < offset + limit; i++) video(i),
      ],
      total: count,
      offset: offset,
      limit: limit,
    );
  }
}
