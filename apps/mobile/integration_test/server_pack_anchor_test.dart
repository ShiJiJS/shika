import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF4 deep pack return keeps neighbour, row inset, filters, prepend and inserted membership',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/pack-anchor');
      expect(seed['pack_count'], 73);
      final store = SecureCredentialStore(
        key: 'video_viewer.e2e.pack-anchor.v1',
      );
      await store.clear();
      final repo = ServerLibraryRepository(store, port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
        await store.clear();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '深列表图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final a = await repo.createPackTag('范围一');
      final b = await repo.createPackTag('范围二');
      final ids = await repo.selectPackIds(PackQuery());
      expect(ids.length, 73);
      await repo.setPackTags(ids, {a.id, b.id});
      await t.pumpWidget(ShikaApp(repository: repo));

      Future<void> until(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            await fixture('/__fixture/checkpoint/error');
            await t.pump(const Duration(seconds: 2));
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 200));
      }

      Future<void> idle() => until(
        () =>
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        'catalog settled',
      );
      Future<void> tap(Finder finder) async {
        if (finder.hitTestable().evaluate().isEmpty) {
          await t.ensureVisible(finder);
          await until(
            () => finder.hitTestable().evaluate().isNotEmpty,
            'scrolled control accepts the next tap',
          );
        }
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 300));
        await idle();
      }

      Future<void> shot(String phase) async {
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/pack-anchor-$phase');
        await t.pump(const Duration(seconds: 2));
      }

      await idle();
      await tap(find.byKey(const Key('nav-tags')));
      await tap(find.byKey(const Key('kind-pack')));
      await tap(find.byKey(Key('pack-tag-${a.id}')));
      await tap(find.byKey(Key('pack-tag-${b.id}')));
      await tap(find.byKey(const Key('tag-view-results')));
      final state = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      expect(state.entry.source, BrowseSource.tags);
      await tap(find.byKey(const Key('pack-search')));
      await t.enterText(find.byKey(const Key('pack-search')), '图包');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await idle();
      await tap(find.byTooltip('选择文件夹'));
      await tap(find.text('深列表图包'));
      await tap(find.text('使用此目录'));
      await tap(find.byTooltip('筛选图包'));
      await tap(find.byType(DropdownButtonFormField<PackReadState>));
      await tap(find.text('未读').last);
      await tap(find.text('应用筛选'));
      final queryKey = state.entry.queryKey;
      expect(state.entry.query.tags, {a.id, b.id});
      expect(state.entry.query.folder, seed['path']);
      expect(state.entry.query.search, '图包');
      expect(state.entry.query.readState, PackReadState.unread);
      expect(state.data.total, 73);
      for (
        var attempt = 0;
        attempt < 5 && state.data.items.length < 73;
        attempt++
      ) {
        await t.drag(
          find.byKey(const Key('pack-grid')),
          const Offset(0, -6000),
        );
        await idle();
      }
      expect(state.data.items.length, 73);
      final original = state.data.items[58].id,
          neighbor = state.data.items[59].id;
      final previous = state.data.items[57].id;
      state.scroll.jumpTo(state.listHeader + 29 * state.stride + 37);
      await t.pump(const Duration(milliseconds: 300));
      await idle();
      Finder tile(String id) => find.byKey(Key('pack-tile-$id'));
      expect(state.position().ids.first, original);
      final y = t.getTopLeft(tile(original)).dy;
      await shot('before');
      await tap(tile(original));
      await tap(find.text('整包标签'));
      await tap(
        find.ancestor(
          of: find.text('范围二'),
          matching: find.bySubtype<FilterChip>(),
        ),
      );
      await fixture('/__fixture/actions/fail-pack-anchor');
      await tap(find.text('保存整包标签'));
      await tap(find.byTooltip('关闭面板'));
      expect(state.data.items.length, 73);
      expect(state.data.retryRestore, isTrue);
      expect(
        find.byKey(const Key('pack-list-retry')).hitTestable(),
        findsOneWidget,
      );
      await shot('error');
      for (var retry = 0; retry < 3 && state.data.error.isNotEmpty; retry++) {
        expect(state.data.items.length, 73);
        expect(state.pendingReturn!.scrollIndex, 58);
        await tap(find.byKey(const Key('pack-list-retry')));
      }
      expect(state.data.error, isEmpty);
      expect(state.data.total, 72);
      expect(state.data.offset, 48);
      expect(state.data.items.length, 24);
      expect(state.data.anchorIndex, 58);
      expect(state.data.items.any((pack) => pack.id == original), isFalse);
      expect(state.data.items[10].id, neighbor);
      expect(t.getTopLeft(tile(neighbor)).dy, closeTo(y, 2));
      expect(state.position().context.scrollInset, closeTo(37, 2));
      expect(state.entry.queryKey, queryKey);
      await shot('return');
      final first = state.data.items.first.id;
      final beforeY = t.getTopLeft(find.byKey(const Key('pack-grid'))).dy - 37;
      state.scroll.jumpTo(state.listHeader + 37);
      await idle();
      await until(
        () => state.data.offset == 24 && !state.data.loading,
        'earlier page prepended',
      );
      expect(t.getTopLeft(tile(first)).dy, closeTo(beforeY, 2));
      await shot('prepend');
      await fixture('/__fixture/actions/pack-anchor-prepend');
      await repo.refresh();
      await idle();
      final added = await repo.selectPackIds(PackQuery(search: '000新增图包'));
      expect(added.length, 1);
      await repo.setPackTags(added, {a.id, b.id});
      await idle();
      await until(
        () => state.data.total == 73 && !state.data.loading,
        'new matching pack inserted before anchor',
      );
      expect(t.getTopLeft(tile(first)).dy, closeTo(beforeY, 2));
      expect(state.entry.queryKey, queryKey);
      expect(state.entry.source, BrowseSource.tags);
      await shot('inserted');
      final trace = await fixture('/__fixture/trace', method: 'GET');
      final reads = (trace['items'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (r) =>
                r['path'] == '/api/v1/packs' &&
                (r['query_lists'] as Map).containsKey('anchor_ids'),
          )
          .toList();
      expect(reads.map((r) => r['status']), containsAllInOrder([503, 200]));
      final failed = reads.firstWhere((r) => r['status'] == 503);
      expect((failed['query_lists'] as Map)['anchor_ids'].take(2), [
        original,
        neighbor,
      ]);
      expect((failed['query_lists'] as Map)['anchor_ids'][2], previous);
      expect(((failed['query_lists'] as Map)['tag_ids'] as List).toSet(), {
        a.id,
        b.id,
      });
      expect((failed['query'] as Map)['read_state'], 'unread');
      expect((failed['query'] as Map)['search'], '图包');
      expect((failed['query'] as Map)['offset'], '58');
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
