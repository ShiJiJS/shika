import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class DeepPacks extends WorkspaceLibrary {
  DeepPacks({int count = 73}) {
    packLinks
      ..clear()
      ..addAll({
        for (var i = 0; i < count; i++) 'p$i': {'自然', '收藏'},
      });
  }
  bool failLocation = false, cancelLocation = false;
  Completer<void>? locationGate, pageGate;
  int? heldOffset;
  final locations = <({List<String> anchors, int fallback})>[];
  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) async {
    final all =
        [
              for (final id in packLinks.keys)
                LibraryPack(
                  id: id,
                  rootId: 'pack-root',
                  path: '/packs/$id',
                  name: id == 'early'
                      ? '000包'
                      : '包${id.substring(1).padLeft(3, '0')}',
                  pageCount: 3,
                  readableCount: 3,
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
              (p) =>
                  p.tags.containsAll(query.tags) &&
                  p.name.contains(query.search),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final page = CatalogPage(
      items: all.skip(offset).take(limit),
      total: all.length,
      offset: offset,
      limit: limit,
    );
    if (offset == heldOffset && pageGate != null) await pageGate!.future;
    return page;
  }

  @override
  Future<CatalogPage<LibraryPack>> restorePackEntry(
    PackQuery query, {
    required List<String> anchors,
    required int fallbackIndex,
    int limit = 24,
  }) async {
    locations.add((anchors: [...anchors], fallback: fallbackIndex));
    if (cancelLocation) throw const RequestCancelled();
    if (failLocation) throw const LibraryFailure('定位暂时失败');
    final page = await super.restorePackEntry(
      query,
      anchors: anchors,
      fallbackIndex: fallbackIndex,
      limit: limit,
    );
    if (locationGate != null) await locationGate!.future;
    return page;
  }
}

void main() {
  late DeepPacks repo;
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> tap(WidgetTester t, Finder finder) async {
    if (finder.hitTestable().evaluate().isEmpty) await t.ensureVisible(finder);
    await t.tap(finder);
    await frames(t);
  }

  Future<PackCatalogPageState> start(
    WidgetTester t, {
    int count = 73,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    repo = DeepPacks(count: count);
    await repo.initialize();
    t.view.physicalSize = size;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(VideoViewerApp(repository: repo));
    await frames(t);
    await tap(t, find.byKey(const Key('kind-pack')));
    return t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
  }

  Future<void> close(WidgetTester t) async {
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await frames(t);
  }

  Finder tile(String id) => find.byKey(Key('pack-tile-$id'));

  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
  ]) {
    testWidgets(
      'deep tag edit retains failed location and returns to the matching neighbour at the same row inset ${sample.$1} / ${sample.$2}',
      (t) async {
        final state = await start(t, size: sample.$1, scale: sample.$2);
        await state.change(
          PackQuery(
            tags: {'自然', '收藏'},
            search: '包',
            readState: PackReadState.unread,
          ),
        );
        await frames(t);
        for (var i = 0; i < 3; i++) {
          await t.drag(
            find.byKey(const Key('pack-grid')),
            const Offset(0, -6000),
          );
          await frames(t);
        }
        expect(state.data.items.length, 73);
        state.scroll.jumpTo(state.listHeader + 29 * state.stride + 37);
        await frames(t);
        expect(state.position().ids.first, 'p58');
        final y = t.getTopLeft(tile('p58')).dy;
        await tap(t, tile('p58'));
        await tap(t, find.text('图包标签'));
        await tap(
          t,
          find.ancestor(
            of: find.text('收藏'),
            matching: find.bySubtype<FilterChip>(),
          ),
        );
        repo.failLocation = true;
        await tap(t, find.text('保存图包标签'));
        await tap(t, find.byTooltip('关闭面板'));
        expect(state.data.items.length, 73);
        expect(state.data.retryRestore, isTrue);
        expect(
          find.byKey(const Key('pack-list-retry')).hitTestable(),
          findsOneWidget,
        );
        expect(repo.locations.last.anchors.take(2), ['p58', 'p59']);
        expect(repo.locations.last.anchors[2], 'p57');
        repo.failLocation = false;
        await tap(t, find.byKey(const Key('pack-list-retry')));
        expect(state.data.total, 72);
        expect(state.data.offset, 48);
        expect(state.data.items.length, 24);
        expect(state.data.items.any((p) => p.id == 'p58'), isFalse);
        expect(t.getTopLeft(tile('p59')).dy, closeTo(y, 1));
        expect(state.position().context.scrollInset, closeTo(37, 1));
        final first = state.data.items.first.id;
        final beforeY =
            t.getTopLeft(find.byKey(const Key('pack-grid'))).dy - 37;
        state.scroll.jumpTo(state.listHeader + 37);
        await frames(t);
        expect(state.data.offset, 24);
        expect(t.getTopLeft(tile(first)).dy, closeTo(beforeY, 1));
        repo.packLinks['early'] = {'自然', '收藏'};
        repo.notifyListeners();
        await frames(t);
        expect(state.data.total, 73);
        expect(t.getTopLeft(tile(first)).dy, closeTo(beforeY, 1));
        expect(state.entry.query.tags, {'自然', '收藏'});
        await close(t);
      },
    );
  }

  testWidgets(
    'when the current and following packs leave the query, the previous neighbour is preferred',
    (t) async {
      final state = await start(t);
      await state.change(PackQuery(tags: {'自然', '收藏'}));
      await frames(t);
      for (var i = 0; i < 3; i++) {
        await t.drag(
          find.byKey(const Key('pack-grid')),
          const Offset(0, -6000),
        );
        await frames(t);
      }
      state.scroll.jumpTo(state.listHeader + 29 * state.stride + 37);
      await frames(t);
      for (var i = 58; i < 73; i++) {
        repo.packLinks['p$i'] = {'自然'};
      }
      repo.notifyListeners();
      await frames(t);
      expect(repo.locations.last.anchors.take(3), ['p58', 'p59', 'p57']);
      expect(state.data.anchorIndex, 57);
      expect(state.data.total, 58);
      expect(state.data.items.last.id, 'p57');
      expect(tile('p57').hitTestable(), findsOneWidget);
      await close(t);
    },
  );

  testWidgets(
    'an interrupted location keeps its old pixels and pending IDs until an explicit retry',
    (t) async {
      final state = await start(t);
      for (var i = 0; i < 3; i++) {
        await t.drag(
          find.byKey(const Key('pack-grid')),
          const Offset(0, -6000),
        );
        await frames(t);
      }
      final pixels = state.listHeader + 29 * state.stride + 37;
      state.scroll.jumpTo(pixels);
      await frames(t);
      final y = t.getTopLeft(tile('p58')).dy;
      repo.cancelLocation = true;
      repo.notifyListeners();
      await frames(t);
      expect(state.data.error, contains('已取消'));
      expect(state.pendingReturn!.scrollIndex, 58);
      expect(state.scroll.offset, closeTo(pixels, 1));
      repo.cancelLocation = false;
      await tap(t, find.byKey(const Key('pack-list-retry')));
      expect(state.data.offset, 48);
      expect(state.data.anchorIndex, 58);
      expect(t.getTopLeft(tile('p58')).dy, closeTo(y, 1));
      await close(t);
    },
  );

  testWidgets(
    'a late relocation cannot move the new search back to its previous window',
    (t) async {
      final state = await start(t);
      repo.locationGate = Completer();
      repo.notifyListeners();
      await frames(t);
      expect(repo.locations, isNotEmpty);
      await t.enterText(find.byKey(const Key('pack-search')), '包001');
      await frames(t);
      expect(state.data.items.single.id, 'p1');
      repo.locationGate!.complete();
      await frames(t);
      expect(state.entry.query.search, '包001');
      expect(state.data.items.single.id, 'p1');
      expect(state.scroll.offset, 0);
      expect(state.pendingReturn, isNull);
      await close(t);
    },
  );

  testWidgets(
    'discarding an old page on append keeps the visible pack in place',
    (t) async {
      final state = await start(t, count: 200);
      for (var i = 0; i < 4; i++) {
        await t.drag(
          find.byKey(const Key('pack-grid')),
          const Offset(0, -30000),
        );
        await frames(t);
      }
      expect(state.data.items.length, 120);
      repo.heldOffset = 120;
      repo.pageGate = Completer();
      final gridY = t.getTopLeft(find.byKey(const Key('pack-grid'))).dy;
      state.scroll.jumpTo(state.scroll.position.maxScrollExtent - 200);
      final id = state.position().ids.first;
      final y = gridY - state.position().context.scrollInset;
      repo.pageGate!.complete();
      await frames(t);
      expect(state.data.offset, 24);
      expect(state.data.items.length, 120);
      expect(t.getTopLeft(tile(id)).dy, closeTo(y, 1));
      await close(t);
    },
  );
}
