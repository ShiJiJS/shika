import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/tag_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF4 real tag pagination, retained selection, retry and namespace',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final store = SecureCredentialStore(
        key: 'video_viewer.e2e.tag-catalog.v1',
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
      final ids = <String>[];
      for (var i = 0; i < 61; i++) {
        final result = await repo.api.json(
          'POST',
          '/api/v1/tags',
          body: {
            'request_id': 'tag-catalog-video-$i',
            'name': '分页${i.toString().padLeft(2, '0')}',
          },
        );
        ids.add(result['id'] as String);
      }
      await repo.api.json(
        'POST',
        '/api/v1/pack-tags',
        body: {'request_id': 'tag-catalog-pack', 'name': '分页60'},
      );
      expect(repo.snapshot.tags.any(ids.contains), isFalse);
      await t.pumpWidget(VideoViewerApp(repository: repo));

      Future<void> until(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
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
        await t.ensureVisible(finder);
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 300));
        await idle();
      }

      Future<void> shot(String phase) async {
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/tag-catalog-$phase');
        await t.pump(const Duration(seconds: 2));
      }

      await idle();
      await tap(find.byKey(const Key('nav-tags')));
      final state = t.state<TagCatalogPageState>(find.byType(TagCatalogPage));
      expect(state.total, greaterThanOrEqualTo(61));
      expect(state.tags.length, 50);
      await tap(find.byKey(Key('video-tag-${ids.first}')));
      final scroll = find.descendant(
        of: find.byType(TagCatalogPage),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await t.scrollUntilVisible(find.text('更多标签'), 500, scrollable: scroll);
      await fixture('/__fixture/actions/fail-tag-page');
      await tap(find.text('更多标签'));
      expect(
        find.byKey(const Key('tag-read-retry')).hitTestable(),
        findsOneWidget,
      );
      expect(state.selected, {ids.first});
      await shot('retry');
      await tap(find.byKey(const Key('tag-read-retry')));
      expect(state.tags.length, state.total);
      await t.scrollUntilVisible(
        find.byKey(Key('video-tag-${ids.last}')),
        300,
        scrollable: scroll,
      );
      await tap(find.byKey(Key('video-tag-${ids.last}')));
      expect(state.selected, {ids.first, ids.last});
      expect(state.matching, 0);
      await shot('paged');
      await tap(find.byTooltip('管理视频标签 分页60'));
      await t.enterText(find.byKey(const Key('tag-name')), '分页60改名');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tap(find.byKey(const Key('tag-definition-save')));
      expect(state.selected, {ids.first, ids.last});
      final renamed = await repo.loadVideoTags(search: '分页60改名');
      expect(renamed.items.single.id, ids.last);
      final pack = await repo.loadPackTags(search: '分页60');
      expect(pack.items.single.name, '分页60');
      // Search in the actual page after the rename refresh reset its first page.
      final input = find.byKey(const Key('video-tag-search'));
      await t.scrollUntilVisible(input, -500, scrollable: scroll);
      await tap(input);
      await t.enterText(input, '分页60改名');
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await idle();
      await until(() => state.tags.length == 1, 'renamed tag search');
      expect(
        find.descendant(
          of: find.byKey(Key('video-tag-${ids.last}')),
          matching: find.text('分页60改名'),
        ),
        findsOneWidget,
      );
      await shot('renamed');
      final trace = await fixture('/__fixture/trace', method: 'GET');
      final requests = (trace['items'] as List).cast<Map<String, dynamic>>();
      final pageRequests = requests.where(
        (r) =>
            r['method'] == 'GET' &&
            r['path'] == '/api/v1/tags' &&
            (r['query'] as Map)['offset'] == '50',
      );
      expect(
        pageRequests.map((r) => r['status']),
        containsAllInOrder([503, 200]),
      );
      expect(
        requests.where(
          (r) =>
              r['method'] == 'POST' &&
              (r['path'] as String).contains('playback'),
        ),
        isEmpty,
      );
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
