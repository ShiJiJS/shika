import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class RecentLayoutLibrary extends WorkspaceLibrary {
  bool empty = false;
  final order = [for (var i = 0; i < 30; i++) i];
  void reorderHistory() {
    order.insert(0, order.removeLast());
    notifyListeners();
  }

  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    'image_packs',
    'pack_tags',
    'pack_reading_sessions',
  ]);
  void clearHistory() {
    empty = true;
    notifyListeners();
  }

  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) async {
    if (query.source != BrowseSource.recent) {
      return super.loadPacks(query, offset: offset, limit: limit);
    }
    packReads.add(query);
    return CatalogPage(
      items: [
        if (!empty)
          for (final i in order.skip(offset).take(limit))
            LibraryPack(
              id: 'recent-$i',
              rootId: 'r',
              path: '/packs/$i',
              name: '最近图包$i',
              pageCount: 3,
              readableCount: 3,
              contentVersion: 1,
              status: 'available',
              createdAt: 0,
              progress: PackProgress(
                pageId: 'page-$i',
                pageIndex: 1,
                offsetRatio: .2,
                completed: false,
                revision: 1,
                updatedAt: 1,
              ),
              cover: const MediaSource('assets/media/flower-portrait.jpg'),
            ),
      ],
      total: empty ? 0 : 30,
      offset: offset,
      limit: limit,
    );
  }
}

void main() {
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.6),
  ]) {
    testWidgets(
      'recent list paging, library isolation and empty state fit ${sample.$1} / ${sample.$2}',
      (t) async {
        final previous = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = UnreadyVideo();
        final repo = RecentLayoutLibrary();
        await repo.initialize();
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = sample.$1;
        t.platformDispatcher.textScaleFactorTestValue = sample.$2;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          repo.dispose();
          VideoPlayerPlatform.instance = previous;
          t.view.resetDevicePixelRatio();
          t.view.resetPhysicalSize();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        Future<void> until(bool Function() done) async {
          for (var i = 0; i < 150; i++) {
            await t.pump(const Duration(milliseconds: 40));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 3)),
            );
            expect(t.takeException(), isNull);
            if (done()) return;
          }
          fail('Recent UI did not reach expected state');
        }

        Future<void> tap(Finder finder) async {
          await t.pump(const Duration(milliseconds: 400));
          expect(finder.hitTestable(), findsOneWidget);
          await t.tap(finder);
          await t.pump(const Duration(milliseconds: 400));
        }

        await t.pumpWidget(ShikaApp(repository: repo));
        await until(
          () => find.byKey(const Key('kind-pack')).evaluate().isNotEmpty,
        );
        await tap(find.byKey(const Key('kind-pack')));
        await until(
          () => find.byKey(const Key('pack-search')).evaluate().isNotEmpty,
        );
        await t.enterText(find.byKey(const Key('pack-search')), '庭院');
        await until(
          () =>
              t
                  .state<PackCatalogPageState>(find.byType(PackCatalogPage))
                  .data
                  .total ==
              1,
        );
        await tap(find.byKey(const Key('nav-recent')));
        await tap(find.byKey(const Key('kind-pack')));
        await until(
          () =>
              find.text('最近阅读的图包').evaluate().isNotEmpty &&
              find.text('第 2 / 3 张').evaluate().isNotEmpty,
        );
        expect(find.text('30 包'), findsOneWidget);
        expect(find.byKey(const Key('pack-search')), findsNothing);
        expect(repo.packReads.last.source, BrowseSource.recent);
        expect(repo.packReads.last.search, isEmpty);
        await t.drag(
          find.byKey(const Key('pack-grid')),
          const Offset(0, -2400),
        );
        await until(
          () =>
              repo.packReads
                  .where((q) => q.source == BrowseSource.recent)
                  .length >=
              2,
        );
        PackCatalogPageState catalog() =>
            t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
        await until(
          () => !catalog().data.loading && catalog().data.items.length == 30,
        );
        await t.pump(const Duration(milliseconds: 500));
        final anchor = catalog().position().context.scrollAnchor;
        final row = find.byKey(Key('recent-pack-$anchor'));
        final oldY = t.getTopLeft(row).dy;
        repo.reorderHistory();
        await until(
          () =>
              !catalog().data.loading &&
              catalog().pendingReturn == null &&
              catalog().data.items.any((pack) => pack.id == anchor) &&
              row.evaluate().isNotEmpty,
        );
        await t.pump();
        await t.pump();
        final shift = t.getTopLeft(row).dy - oldY;
        expect(
          shift.abs() < 3 ||
              (catalog().scroll.position.extentAfter < 3 && shift >= 0),
          isTrue,
          reason:
              'full trailing window: shift=$shift, oldY=$oldY, anchor=$anchor, offset=${catalog().data.offset}, after=${catalog().scroll.position.extentAfter}',
        );
        repo.clearHistory();
        await until(() => find.text('还没有观看记录').evaluate().isNotEmpty);
        await tap(find.byKey(const Key('nav-library')));
        await until(
          () => find.byKey(const Key('pack-search')).evaluate().isNotEmpty,
        );
        expect(
          t
              .widget<TextField>(find.byKey(const Key('pack-search')))
              .controller!
              .text,
          '庭院',
        );
        expect(
          t
              .state<PackCatalogPageState>(find.byType(PackCatalogPage))
              .data
              .items
              .single
              .name,
          '庭院随拍',
        );
      },
    );
  }
}
