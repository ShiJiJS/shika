import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/library/tag_catalog_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class PagedLabels extends WorkspaceLibrary {
  final requests = <({String search, int offset})>[];
  final slow = Completer<void>();
  bool failMore = true, failSearch = true;
  int labelCount = 61;
  @override
  Future<CatalogPage<VideoTag>> loadVideoTags({
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    requests.add((search: search, offset: offset));
    if (search == '缓慢') await slow.future;
    if ((offset > 0 && failMore) || (search == '故障' && failSearch)) {
      throw const LibraryFailure('测试标签读取失败');
    }
    final matching = [
      for (var i = 0; i < labelCount; i++)
        VideoTag('v$i', '标签${i.toString().padLeft(2, '0')}', 0),
    ].where((tag) => tag.name.contains(search)).toList();
    return CatalogPage(
      items: matching.skip(offset).take(limit),
      total: matching.length,
      offset: offset,
      limit: limit,
    );
  }
}

void main() {
  late PagedLabels repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = PagedLabels();
    await repo.initialize();
  });
  tearDown(() {
    if (!repo.slow.isCompleted) repo.slow.complete();
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.tap(finder);
    await frames(t);
  }

  Finder tagScroll() => find.descendant(
    of: find.byType(TagCatalogPage),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  Future<void> start(WidgetTester t) async {
    await t.pumpWidget(VideoViewerApp(repository: repo));
    await frames(t);
    await tap(t, find.byKey(const Key('nav-tags')));
  }

  testWidgets(
    'labels beyond the legacy snapshot page, retain selection and retry page 50 from a visible error',
    (t) async {
      await start(t);
      expect(repo.snapshot.tags.contains('v0'), isFalse);
      await tap(t, find.byKey(const Key('video-tag-v0')));
      expect(find.text('同时包含 1 个标签'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('更多标签'),
        300,
        scrollable: tagScroll(),
      );
      await tap(t, find.text('更多标签'));
      expect(repo.requests.last.offset, 50);
      expect(
        find.byKey(const Key('tag-read-retry')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('同时包含 1 个标签'), findsOneWidget);
      repo.failMore = false;
      await tap(t, find.byKey(const Key('tag-read-retry')));
      expect(repo.requests.last.offset, 50);
      await t.scrollUntilVisible(
        find.byKey(const Key('video-tag-v60')),
        200,
        scrollable: tagScroll(),
      );
      await tap(t, find.byKey(const Key('video-tag-v60')));
      expect(find.text('同时包含 2 个标签'), findsOneWidget);
      expect(find.text('更多标签'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );

  testWidgets(
    'catalog changes between pages require a fresh read and retain selected tags',
    (t) async {
      repo.failMore = false;
      await start(t);
      await tap(t, find.byKey(const Key('video-tag-v0')));
      repo.labelCount = 62;
      await t.scrollUntilVisible(
        find.text('更多标签'),
        300,
        scrollable: tagScroll(),
      );
      await tap(t, find.text('更多标签'));
      expect(repo.requests.last.offset, 50);
      expect(find.textContaining('标签列表已变化'), findsOneWidget);
      expect(find.text('同时包含 1 个标签'), findsOneWidget);
      await tap(t, find.byKey(const Key('tag-read-retry')));
      expect(repo.requests.last.offset, 0);
      final state = t.state<TagCatalogPageState>(find.byType(TagCatalogPage));
      expect(state.total, 62);
      expect(state.tags.length, 50);
      expect(state.selected, {'v0'});
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );

  testWidgets(
    'a late search cannot replace the next query and a failed fresh query retries from zero',
    (t) async {
      await start(t);
      final input = find.byKey(const Key('video-tag-search'));
      await t.enterText(input, '缓慢');
      await frames(t);
      await t.enterText(input, '标签60');
      await frames(t);
      expect(find.byKey(const Key('video-tag-v60')), findsOneWidget);
      repo.slow.complete();
      await frames(t);
      expect(find.byKey(const Key('video-tag-v60')), findsOneWidget);
      await t.enterText(input, '故障');
      await frames(t);
      expect(find.byKey(const Key('video-tag-v60')), findsOneWidget);
      expect(find.byKey(const Key('tag-read-retry')), findsOneWidget);
      repo.failSearch = false;
      await tap(t, find.byKey(const Key('tag-read-retry')));
      expect(repo.requests.last, (search: '故障', offset: 0));
      expect(find.text('没有匹配的视频标签'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );
}
