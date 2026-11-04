import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF5 recent packs: actual new frame, full past scope, paging, resume and isolated return',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/pack-anchor');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '最近图包夹具', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final all = await repo.loadPacks(PackQuery(), limit: 100);
      expect(all.total, 73);
      final target = all.items[50];
      // Historical data is fixture setup, not a claim that 27 frames were displayed.
      final historical = await fixture(
        '/__fixture/actions/recent-pack-history',
      );
      final expectedIds = {
        ...List<String>.from(historical['historical_ids']),
        target.id,
      };
      await t.pumpWidget(ShikaApp(repository: repo));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint(
              'UI ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).join(' | ')}',
            );
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder finder) async {
        await t.ensureVisible(finder);
        await until(
          () => finder.hitTestable().evaluate().isNotEmpty,
          'hit target',
        );
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 200));
      }

      Future<void> cover(Finder row) => until(
        () => t
            .widgetList<RawImage>(
              find.descendant(of: row, matching: find.byType(RawImage)),
            )
            .any((w) => w.image != null),
        'current row cover decoded',
      );
      PackReaderPageState reader() =>
          t.state<PackReaderPageState>(find.byType(PackReaderPage));
      PackCatalogPageState catalog() =>
          t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      Future<void> shot(String phase) async {
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/recent-$phase');
        await t.pump(const Duration(seconds: 1));
      }

      await until(
        () => find.byKey(const Key('kind-pack')).evaluate().isNotEmpty,
        'type picker',
      );
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () => find.byKey(const Key('pack-search')).evaluate().isNotEmpty,
        'library search',
      );
      await t.enterText(find.byKey(const Key('pack-search')), target.name);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await until(
        () => t.view.viewInsets.bottom == 0,
        'search keyboard dismissed',
      );
      await until(
        () =>
            !catalog().data.loading &&
            catalog().data.total == 1 &&
            catalog().data.items.single.id == target.id,
        'specific library query',
      );
      final card = find.byKey(Key('pack-tile-${target.id}'));
      await cover(card);
      await tap(card);
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            reader().session.opened &&
            !reader().session.busy,
        'new actual reader frame',
      );
      expect(reader().session.range!.candidateCount, 1);
      await tap(find.byTooltip('下一张'));
      await until(
        () => reader().session.index == 1 && reader().session.unsaved,
        'actual second image',
      );
      expect(await reader().session.flush(), isTrue);
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'return specific library query',
      );
      await until(() {
        final field = find.byKey(const Key('pack-search'));
        if (field.hitTestable().evaluate().isEmpty) return false;
        final route = ModalRoute.of(t.element(field));
        return route?.isCurrent == true &&
            route?.secondaryAnimation?.status == AnimationStatus.dismissed &&
            !catalog().data.loading &&
            catalog().pendingReturn == null;
      }, 'library transition and restore ready for editing');
      // Done closes the real IME connection. Re-tap as a user would before
      // editing the same retained TextField again.
      await tap(find.byKey(const Key('pack-search')));
      await t.enterText(find.byKey(const Key('pack-search')), '没有这个图包');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await until(
        () => t.view.viewInsets.bottom == 0,
        'empty-search keyboard dismissed',
      );
      await until(
        () =>
            !catalog().data.loading &&
            catalog().entry.query.search == '没有这个图包' &&
            catalog().data.total == 0,
        'library empty filter',
      );
      await tap(find.byKey(const Key('nav-recent')));
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () =>
            !catalog().data.loading &&
            catalog().entry.source == BrowseSource.recent &&
            catalog().data.total == 28,
        'recent independent scope',
      );
      expect(catalog().entry.query.search, isEmpty);
      expect(catalog().entry.query.sort, PackSort.recent);
      expect(catalog().data.items.first.id, target.id);
      expect(find.text('第 2 / 3 张'), findsWidgets);
      await shot('initial');
      for (
        var i = 0;
        i < 20 &&
            !find
                .byKey(Key('recent-pack-${all.items.first.id}'))
                .hitTestable()
                .evaluate()
                .isNotEmpty;
        i++
      ) {
        await t.drag(
          find.byKey(const Key('pack-grid')),
          const Offset(0, -1300),
        );
        await t.pump(const Duration(milliseconds: 200));
      }
      await until(
        () => catalog().data.items.length == 28 && !catalog().data.loading,
        'recent second page',
      );
      final last = all.items.first;
      final row = find.byKey(Key('recent-pack-${last.id}'));
      await until(
        () => row.hitTestable().evaluate().isNotEmpty,
        'historical tail visible',
      );
      await cover(row);
      expect((await repo.selectPackIds(catalog().entry.query)), expectedIds);
      await shot('tail');
      final savedViewport = catalog().position().context;
      final anchorRow = find.byKey(
        Key('recent-pack-${savedViewport.scrollAnchor}'),
      );
      final anchorY = t.getTopLeft(anchorRow).dy;
      await tap(row);
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            reader().session.opened &&
            !reader().session.busy,
        'historical current image resumed',
      );
      expect(reader().session.entry.source, BrowseSource.recent);
      expect(find.text('最近阅读'), findsOneWidget);
      expect(reader().session.range!.source, BrowseSource.recent);
      expect(reader().session.range!.candidateCount, 28);
      expect(reader().session.range!.cursor, 27);
      expect(reader().session.index, 1);
      final queue = await reader().session.reader.queue(
        reader().session.range!.id,
      );
      expect(queue.entries.map((e) => e.pack.id).toSet(), expectedIds);
      expect(queue.entries.last.pack.id, last.id);
      final history = await repo.api.json(
        'GET',
        '/api/v1/recent',
        query: {'kind': 'pack', 'limit': '100'},
      );
      expect(history['total'], 28);
      expect((history['items'] as List).first['id'], last.id);
      await shot('reading');
      await tap(find.byTooltip('返回来源'));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isEmpty &&
            !catalog().data.loading &&
            catalog().pendingReturn == null &&
            catalog().data.items.length == 28,
        'return complete recent viewport window',
      );
      expect(catalog().entry.source, BrowseSource.recent);
      expect(catalog().entry.query.search, isEmpty);
      expect(catalog().data.items.first.id, last.id);
      await until(
        () =>
            anchorRow.evaluate().isNotEmpty &&
            t
                .getRect(anchorRow)
                .overlaps(t.getRect(find.byKey(const Key('pack-grid')))),
        'original viewport anchor remains visible after reorder',
      );
      final delta = t.getTopLeft(anchorRow).dy - anchorY;
      expect(
        delta.abs() < 3 ||
            (catalog().scroll.position.extentAfter < 3 && delta >= 0),
        isTrue,
        reason: 'preserve the original row inset, or clamp only at the full-list bottom',
      );
      await shot('return');
      await tap(find.byKey(const Key('nav-library')));
      await until(
        () =>
            catalog().entry.query.search == '没有这个图包' && !catalog().data.loading,
        'independent library draft',
      );
      expect(catalog().data.total, 0);
      expect(catalog().entry.source, BrowseSource.library);
      await shot('library');
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      final creates = trace.where(
        (r) => r['method'] == 'POST' && r['path'] == '/api/v1/pack-sessions',
      );
      final opened = trace.where(
        (r) =>
            r['method'] == 'POST' && (r['path'] as String).endsWith('/opened'),
      );
      expect(creates.length, 2);
      expect(
        opened.length,
        2,
        reason: '27 historical rows were seeded; only these two current frames open now',
      );
      final recentReads = trace
          .where(
            (r) =>
                r['path'] == '/api/v1/packs' &&
                r['query']['source'] == 'recent',
          )
          .toList();
      expect(recentReads.any((r) => r['query']['offset'] == '24'), isTrue);
      expect(
        recentReads.any(
          (r) =>
              (r['query_lists']['anchor_ids'] as List?)?.contains(
                savedViewport.scrollAnchor,
              ) ==
              true,
        ),
        isTrue,
      );
      expect(
        recentReads.every(
          (r) => r['query']['search'] == '' && r['query']['sort'] == 'recent',
        ),
        isTrue,
      );
    },
  );
}
