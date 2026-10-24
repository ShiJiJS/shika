import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class WorkspaceLibrary extends DemoLibraryRepository {
  WorkspaceLibrary() : super(MemoryStateStore(), latency: Duration.zero);
  final packNames = <String, String>{'自然': '自然', '收藏': '收藏'};
  final packLinks = <String, Set<String>>{
    'p1': {'自然'},
    'p2': {'收藏'},
  };
  final packReads = <PackQuery>[];
  @override
  ServiceCapabilities get capabilities =>
      ServiceCapabilities(['image_packs', 'pack_tags']);
  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) async {
    packReads.add(query);
    final items =
        [
              for (final id in packLinks.keys)
                LibraryPack(
                  id: id,
                  rootId: 'pack-root',
                  path: '/packs/${id == 'p1' ? '春日合集' : '庭院随拍'}',
                  name: id == 'p1' ? '春日合集' : '庭院随拍',
                  pageCount: id == 'p1' ? 500 : 37,
                  readableCount: id == 'p1' ? 499 : 37,
                  contentVersion: 1,
                  status: 'available',
                  createdAt: 0,
                  tags: packLinks[id]!,
                  tagNames: {
                    for (final tag in packLinks[id]!) tag: packNames[tag]!,
                  },
                  cover: const MediaSource('assets/media/flower-portrait.jpg'),
                ),
            ]
            .where(
              (pack) =>
                  pack.name.contains(query.search) &&
                  pack.tags.containsAll(query.tags) &&
                  (query.folder.isEmpty || under(pack.path, query.folder)) &&
                  (query.readState == PackReadState.all ||
                      query.readState == PackReadState.unread),
            )
            .toList();
    return CatalogPage(
      items: items.skip(offset).take(limit),
      total: items.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<PackTagNames> resolvePackTags(Set<String> ids) async => PackTagNames(
    names: {
      for (final id in ids)
        if (packNames.containsKey(id)) id: packNames[id]!,
    },
    missing: ids.where((id) => !packNames.containsKey(id)),
  );

  @override
  Future<CatalogPage<PackTag>> loadPackTags({
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final items = packNames.entries
        .where((tag) => tag.value.contains(search))
        .map(
          (tag) => PackTag(
            tag.key,
            tag.value,
            packLinks.values.where((tags) => tags.contains(tag.key)).length,
          ),
        )
        .toList();
    return CatalogPage(
      items: items.skip(offset).take(limit),
      total: items.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<void> editPackTag({
    String? original,
    String? name,
    bool delete = false,
  }) async {
    if (delete) {
      packNames.remove(original);
      for (final tags in packLinks.values) {
        tags.remove(original);
      }
    } else {
      packNames[original ?? 'created-pack-tag'] = name!.trim();
    }
    notifyListeners();
  }

  @override
  Future<PackTag> createPackTag(String name) async {
    await editPackTag(name: name);
    return PackTag('created-pack-tag', name.trim(), 0);
  }

  @override
  Future<void> setPackTags(
    Set<String> ids,
    Set<String> tags, {
    bool replace = false,
  }) async {
    for (final id in ids) {
      packLinks[id] = replace ? {...tags} : {...packLinks[id]!, ...tags};
    }
    notifyListeners();
  }
}

Future<void> frames(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late WorkspaceLibrary repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = WorkspaceLibrary();
    await repo.initialize();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.tap(finder);
    await frames(t);
  }

  Future<void> nav(WidgetTester t, String tab) =>
      tap(t, find.byKey(Key('nav-$tab')));

  testWidgets(
    'four destinations keep library, tag results and actual recent video scopes independent',
    (t) async {
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      expect(find.byKey(const Key('nav-browse')), findsNothing);
      for (final tab in ['library', 'tags', 'recent', 'settings']) {
        expect(find.byKey(Key('nav-$tab')), findsOneWidget);
      }
      expect(find.byType(MovieStage), findsNothing);
      await t.enterText(find.byKey(const Key('video-search')), '花间微风');
      await frames(t);
      expect(find.text('1 个视频'), findsOneWidget);
      await nav(t, 'tags');
      await tap(t, find.byKey(const Key('video-tag-自然')));
      await tap(t, find.byKey(const Key('video-tag-花卉')));
      expect(find.text('匹配 3 个视频'), findsOneWidget);
      await tap(t, find.byKey(const Key('tag-view-results')));
      expect(find.text('3 个视频'), findsOneWidget);
      await tap(t, find.text('预览此范围'));
      expect(repo.savedPreviewEntry!.source, BrowseSource.tags);
      expect(repo.savedPreviewEntry!.query.tags, {'自然', '花卉'});
      expect(find.byKey(const Key('app-navigation')), findsNothing);
      await tap(t, find.byKey(const Key('preview-back')));
      await nav(t, 'library');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('video-search')))
            .controller!
            .text,
        '花间微风',
      );
      expect(find.text('1 个视频'), findsOneWidget);
      await nav(t, 'recent');
      expect(find.byKey(const Key('video-search')), findsNothing);
      expect(find.text('1 个视频'), findsOneWidget);
      await tap(t, find.text('预览此范围'));
      expect(repo.savedPreviewEntry!.source, BrowseSource.recent);
      expect(repo.savedPreviewEntry!.query.tags, isEmpty);
      expect(repo.savedPreviewEntry!.search, isEmpty);
      await tap(t, find.byKey(const Key('preview-back')));
      await nav(t, 'library');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('video-search')))
            .controller!
            .text,
        '花间微风',
      );
      await t.pumpWidget(const SizedBox());
      await frames(t);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'pack cards, per-type queries and same-name tag management stay separate from video',
    (t) async {
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      await t.enterText(find.byKey(const Key('video-search')), '花间微风');
      await frames(t);
      await tap(t, find.byKey(const Key('kind-pack')));
      expect(find.text('2 个图包'), findsOneWidget);
      expect(find.text('500 张'), findsOneWidget);
      await t.enterText(find.byKey(const Key('pack-search')), '春日');
      await frames(t);
      expect(find.text('1 个图包'), findsOneWidget);
      await nav(t, 'tags');
      await tap(t, find.byKey(const Key('kind-pack')));
      await tap(t, find.byKey(const Key('pack-tag-自然')));
      await tap(t, find.byKey(const Key('tag-view-results')));
      expect(find.text('1 个图包'), findsOneWidget);
      await tap(t, find.byTooltip('返回标签选择'));
      await tap(t, find.byTooltip('管理图包标签 自然'));
      await t.enterText(find.byKey(const Key('tag-name')), '图包自然');
      await tap(t, find.text('保存'));
      expect(repo.packNames['自然'], '图包自然');
      expect(repo.tagName('自然'), '自然');
      await nav(t, 'library');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('pack-search')))
            .controller!
            .text,
        '春日',
      );
      await tap(t, find.byKey(const Key('kind-video')));
      expect(
        t
            .widget<TextField>(find.byKey(const Key('video-search')))
            .controller!
            .text,
        '花间微风',
      );
      expect(find.text('1 个视频'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await frames(t);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'tag dock opens the complete intersection directly and returns to its own results',
    (t) async {
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      await t.enterText(find.byKey(const Key('video-search')), '花间微风');
      await frames(t);
      await nav(t, 'tags');
      await tap(t, find.byKey(const Key('video-tag-自然')));
      await tap(t, find.byKey(const Key('video-tag-花卉')));
      expect(find.text('同时包含 2 个标签'), findsOneWidget);
      expect(find.text('匹配 3 个视频'), findsOneWidget);
      await tap(t, find.byKey(const Key('tag-preview-results')));
      expect(find.byType(MovieStage), findsOneWidget);
      expect(repo.savedPreviewEntry!.source, BrowseSource.tags);
      expect(repo.savedPreviewEntry!.query.tags, {'自然', '花卉'});
      expect(repo.playbackTotal, 3);
      await tap(t, find.byKey(const Key('preview-back')));
      expect(find.byTooltip('返回标签选择'), findsOneWidget);
      expect(find.text('3 个视频'), findsOneWidget);
      await nav(t, 'library');
      expect(find.text('1 个视频'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('video-search')))
            .controller!
            .text,
        '花间微风',
      );
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );

  testWidgets(
    'changing appearance preserves pack source and the next search still reaches the repository',
    (t) async {
      final preferences = UiPreferences();
      addTearDown(preferences.dispose);
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );
      await frames(t);
      await tap(t, find.byKey(const Key('kind-pack')));
      await t.enterText(find.byKey(const Key('pack-search')), '春日');
      await frames(t);
      expect(find.text('1 个图包'), findsOneWidget);
      await nav(t, 'settings');
      await preferences.setDark(true);
      await frames(t);
      await nav(t, 'library');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('pack-search')))
            .controller!
            .text,
        '春日',
      );
      await t.enterText(find.byKey(const Key('pack-search')), '');
      await frames(t);
      expect(repo.packReads.last.search, '');
      expect(find.text('2 个图包'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );

  testWidgets(
    'pack label search remains usable with a narrow keyboard and large system text',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 740);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        t.view.resetDevicePixelRatio();
        t.view.resetPhysicalSize();
        t.view.resetViewInsets();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      await nav(t, 'tags');
      await tap(t, find.byKey(const Key('kind-pack')));
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      await t.enterText(find.byKey(const Key('pack-tag-search')), '自然');
      await frames(t);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('pack-tag-自然')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );

  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.6),
  ]) {
    testWidgets(
      'library surfaces fit ${sample.$1} at text scale ${sample.$2}',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = sample.$1;
        t.platformDispatcher.textScaleFactorTestValue = sample.$2;
        addTearDown(() {
          t.view.resetDevicePixelRatio();
          t.view.resetPhysicalSize();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await t.pumpWidget(VideoViewerApp(repository: repo));
        await frames(t);
        expect(t.takeException(), isNull);
        await tap(t, find.byKey(const Key('kind-pack')));
        expect(t.takeException(), isNull);
        await nav(t, 'tags');
        expect(t.takeException(), isNull);
        await tap(t, find.byKey(const Key('kind-pack')));
        expect(t.takeException(), isNull);
        await nav(t, 'settings');
        expect(find.text('服务连接'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
  }
}
