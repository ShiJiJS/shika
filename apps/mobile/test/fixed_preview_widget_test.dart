import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';
import 'package:shika/ui/preferences.dart';

import 'nonblocking_widgets_test.dart' show UnreadyVideo;

Future<void> frames(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late DemoLibraryRepository repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = DemoLibraryRepository(MemoryStateStore(), latency: Duration.zero);
    await repo.initialize();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });

  testWidgets(
    'the default order only affects new previews and session order never overwrites it',
    (t) async {
      await t.runAsync(
        () => repo.beginPreview(VideoEntryScope(), order: PlayOrder.random),
      );
      final oldIdentity = repo.playbackIdentity;
      final preferences = UiPreferences();
      await t.pumpWidget(
        ShikaApp(repository: repo, preferences: preferences),
      );
      await frames(t);
      await t.tap(find.byKey(const Key('nav-settings')));
      await frames(t);
      await t.scrollUntilVisible(
        find.text('默认播放顺序'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await frames(t);
      await Scrollable.ensureVisible(
        t.element(find.text('默认播放顺序')),
        alignment: .5,
      );
      await frames(t);
      expect(find.text('默认播放顺序').hitTestable(), findsOneWidget);
      await t.tap(find.text('默认播放顺序'));
      await frames(t);
      await t.tap(find.text('顺序播放').last);
      await frames(t);
      expect(preferences.videoOrder, PlayOrder.sequential);
      expect(repo.playbackIdentity, oldIdentity);
      expect(repo.snapshot.order, PlayOrder.random);
      await t.tap(find.byKey(const Key('nav-library')));
      await frames(t);
      await t.tap(find.text('预览此范围'));
      await frames(t);
      expect(repo.playbackIdentity, isNot(oldIdentity));
      expect(repo.snapshot.order, PlayOrder.sequential);
      await t.tap(find.byKey(const Key('preview-scope')));
      await frames(t);
      await t.tap(find.byKey(const Key('queue-order-random')));
      await frames(t);
      expect(repo.snapshot.order, PlayOrder.random);
      expect(preferences.videoOrder, PlayOrder.sequential);
      await t.tap(find.byTooltip('关闭面板'));
      await frames(t);
      await t.tap(find.byKey(const Key('preview-back')));
      await frames(t);
      await t.tap(find.text('预览此范围'));
      await frames(t);
      expect(repo.snapshot.order, PlayOrder.sequential);
      await t.pumpWidget(const SizedBox());
      await frames(t);
      preferences.dispose();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'an expired connection closes the secondary preview and reveals login',
    (t) async {
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      await t.tap(find.text('预览此范围'));
      await frames(t);
      expect(find.byKey(const Key('video-preview-route')), findsOneWidget);
      await t.runAsync(() => repo.reset(scenario: DemoScenario.offline));
      await frames(t);
      expect(find.byKey(const Key('video-preview-route')), findsNothing);
      expect(find.byType(MovieStage), findsNothing);
      expect(find.text('连接拾刻媒体库'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await frames(t);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'reopening retains the saved tag scope without applying it to the independent library or autoplay',
    (t) async {
      await t.runAsync(
        () => repo.beginPreview(
          VideoEntryScope(
            search: '花间微风',
            sort: VideoSort.name,
            source: BrowseSource.tags,
          ),
          anchor: 'v1',
        ),
      );
      final identity = repo.playbackIdentity;
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      expect(find.byType(MovieStage), findsNothing);
      expect(find.text('6 个视频'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('video-search')))
            .controller!
            .text,
        '',
      );
      expect(repo.playbackIdentity, identity);
      expect(repo.snapshot.recentVideos, isEmpty);
      await t.enterText(find.byKey(const Key('video-search')), '蜻蜓');
      await frames(t);
      expect(repo.savedPreviewEntry!.search, '花间微风');
      expect(repo.playbackIdentity, identity);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );

  testWidgets(
    'library entry opens a secondary preview; end/restart/return retain the source search',
    (t) async {
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      expect(find.byType(MovieStage), findsNothing);
      expect(repo.snapshot.recentVideos, isEmpty);
      await t.enterText(find.byKey(const Key('video-search')), '花间微风');
      await frames(t);
      expect(find.text('1 个视频'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '预览此范围'))
            .onPressed,
        isNotNull,
      );
      await t.tap(find.text('预览此范围'));
      await frames(t);
      expect(
        find.byKey(const Key('video-preview-route')),
        findsOneWidget,
        reason: t.allWidgets
            .whereType<Text>()
            .map((text) => text.data)
            .join(' | '),
      );
      expect(find.byKey(const Key('app-navigation')), findsNothing);
      expect(repo.snapshot.preview!.entry.search, '花间微风');
      expect(repo.snapshot.round, ['v1']);
      expect(repo.snapshot.recentVideos.keys.toSet(), {'v1'});
      final identity = repo.playbackIdentity;
      await t.tap(find.byKey(const Key('preview-next')));
      await frames(t);
      expect(find.text('本次范围已到末尾'), findsOneWidget);
      await t.tap(find.byKey(const Key('preview-restart')));
      await frames(t);
      expect(repo.playbackIdentity, identity);
      expect(repo.snapshot.round, ['v1']);
      await t.tap(find.byKey(const Key('preview-next')));
      await frames(t);
      await t.tap(find.byKey(const Key('preview-end-return')));
      await frames(t);
      final exitDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (find
              .byKey(const Key('video-preview-route'))
              .evaluate()
              .isNotEmpty &&
          DateTime.now().isBefore(exitDeadline)) {
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('video-preview-route')), findsNothing);
      expect(find.byKey(const Key('video-grid')), findsOneWidget);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        '花间微风',
      );
      expect(find.text('1 个视频'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await frames(t);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'tag edits keep the fixed preview current; return updates source matches',
    (t) async {
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      await t.tap(find.byKey(const Key('nav-tags')));
      await frames(t);
      await t.tap(find.text('花卉'));
      await frames(t);
      await t.tap(find.byKey(const Key('tag-view-results')));
      await frames(t);
      expect(find.text('3 个视频'), findsOneWidget);
      await t.tap(find.text('预览此范围'));
      await frames(t);
      final selected = repo.current!.id;
      expect(repo.snapshot.round, hasLength(3));
      await t.tap(find.text('视频标签'));
      await frames(t);
      await t.tap(
        find.ancestor(
          of: find.text('花卉'),
          matching: find.bySubtype<FilterChip>(),
        ),
      );
      await frames(t);
      await t.tap(find.byKey(const Key('tag-assignment-save')));
      await frames(t);
      expect(repo.current!.id, selected);
      expect(repo.snapshot.round, hasLength(3));
      expect(repo.current!.tags, isNot(contains('花卉')));
      expect(find.text('标签 · # 花卉'), findsOneWidget);
      await t.tap(find.byKey(const Key('preview-scope')));
      await frames(t);
      expect(find.text('本次预览范围'), findsOneWidget);
      await t.tap(find.byKey(const Key('queue-order-sequential')));
      await frames(t);
      expect(repo.current!.id, selected);
      expect(repo.snapshot.round, hasLength(3));
      await t.tap(find.byTooltip('关闭面板'));
      await frames(t);
      await t.tap(find.byKey(const Key('preview-back')));
      await frames(t);
      expect(find.text('2 个视频'), findsOneWidget);
      expect(find.byKey(Key('tile-$selected')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await frames(t);
      expect(t.takeException(), isNull);
    },
  );
}
