import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';

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
    'library entry opens a secondary preview; end/restart/return retain the source search',
    (t) async {
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      expect(find.byType(MovieStage), findsNothing);
      expect(repo.snapshot.recentVideos, isEmpty);
      await t.enterText(find.byKey(const Key('video-search')), '花间微风');
      await frames(t);
      expect(find.text('1 个视频'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '预览此范围'),
            )
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
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      await t.tap(find.byKey(const Key('nav-tags')));
      await frames(t);
      await t.tap(find.text('花卉'));
      await frames(t);
      expect(find.text('3 个视频'), findsOneWidget);
      await t.tap(find.text('预览此范围'));
      await frames(t);
      final selected = repo.current!.id;
      expect(repo.snapshot.round, hasLength(3));
      await t.tap(find.text('视频标签'));
      await frames(t);
      await t.tap(find.widgetWithText(FilterChip, '花卉'));
      await frames(t);
      await t.tap(find.widgetWithText(FilledButton, '完成'));
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
