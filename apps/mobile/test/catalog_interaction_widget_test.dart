import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/library/video_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/main.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'catalog_selection_widget_test.dart' show TrackingSelectionWorkspace;
import 'media_workspace_widget_test.dart' show frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class InteractionLibrary extends TrackingSelectionWorkspace {
  bool rejectTrash = false;
  final removals = <Set<String>>[];
  @override
  Future<void> deleteVideos(
    Set<String> ids, {
    required String requestId,
  }) async {
    if (rejectTrash) throw const LibraryFailure('服务暂时不可用');
    removals.add({...ids});
    await super.deleteVideos(ids, requestId: requestId);
  }
}

void main() {
  late InteractionLibrary repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = InteractionLibrary();
    await repo.initialize();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> start(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.pumpWidget(ShikaApp(repository: repo));
    await frames(t);
  }

  Future<void> tap(WidgetTester t, Finder target) async {
    await t.ensureVisible(target);
    await t.tap(target);
    await frames(t);
    expect(t.takeException(), isNull);
  }

  for (final kind in MediaKind.values) {
    testWidgets(
      '${kind.name} back exits selection before leaving the library',
      (t) async {
        await start(t);
        final pack = kind == MediaKind.pack;
        if (pack) await tap(t, find.byKey(const Key('kind-pack')));
        final dynamic page = pack
            ? t.state<PackCatalogPageState>(find.byType(PackCatalogPage))
            : t.state<VideoCatalogPageState>(find.byType(VideoCatalogPage));
        final id = page.data.items.first.id as String;
        final tile = find.byKey(Key('${pack ? 'pack-tile' : 'tile'}-$id'));
        await t.longPress(tile);
        await frames(t);
        expect(page.selected, {id});
        expect(find.byKey(const Key('app-navigation')), findsNothing);
        await t.binding.handlePopRoute();
        await frames(t);
        expect(page.selecting, isFalse);
        expect(page.selected, isEmpty);
        expect(find.byKey(const Key('app-navigation')), findsOneWidget);
        expect(find.byKey(const Key('catalog-select')), findsOneWidget);
        expect(tile.hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'clearing reading status preserves search, folder, tags and sort',
    (t) async {
      await start(t);
      await tap(t, find.byKey(const Key('kind-pack')));
      final page = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      await page.change(
        PackQuery(
          folder: '/packs',
          tags: {'自然'},
          search: '春日',
          readState: PackReadState.reading,
          sort: PackSort.newest,
        ),
      );
      page.search.text = '春日';
      await frames(t);
      expect(page.data.items, isEmpty);
      await tap(t, find.byTooltip('取消在读'));
      expect(page.entry.query.readState, PackReadState.all);
      expect(page.entry.query.folder, '/packs');
      expect(page.entry.query.tags, {'自然'});
      expect(page.entry.query.search, '春日');
      expect(page.entry.query.sort, PackSort.newest);
      expect(page.data.items.map((p) => p.id), ['p1']);
    },
  );

  testWidgets(
    'failed video trash keeps selection; retry and undo change only selected videos',
    (t) async {
      await start(t);
      final page = t.state<VideoCatalogPageState>(
        find.byType(VideoCatalogPage),
      );
      final before = page.data.total;
      final id = page.data.items.first.id;
      await t.longPress(find.byKey(Key('tile-$id')));
      await frames(t);
      repo.rejectTrash = true;
      await tap(t, find.byKey(const Key('video-delete-selected')));
      expect(page.selected, {id});
      expect(page.data.total, before);
      expect(page.error, contains('服务暂时不可用'));
      repo.rejectTrash = false;
      await tap(t, find.byKey(const Key('video-delete-selected')));
      expect(repo.removals, [
        {id},
      ]);
      expect(page.data.total, before - 1);
      expect(page.selected, isEmpty);
      expect(repo.packLinks.keys, containsAll(['p1', 'p2']));
      await tap(t, find.text('撤销'));
      expect(page.data.total, before);
      expect(page.data.items.map((v) => v.id), contains(id));
    },
  );
}
