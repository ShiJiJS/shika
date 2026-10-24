import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

class ReaderLifecycle extends WidgetsBindingObserver {
  final states = <AppLifecycleState>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF5 image failure, original receipts, background flush and fixed tag scope',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      final lifecycle = ReaderLifecycle();
      WidgetsBinding.instance.addObserver(lifecycle);
      addTearDown(() async {
        WidgetsBinding.instance.removeObserver(lifecycle);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '恢复图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final all = await repo.loadPacks(PackQuery(), limit: 100);
      expect(all.total, 27);
      final a = await repo.createPackTag('恢复范围一');
      final b = await repo.createPackTag('恢复范围二');
      final expected = all.items.take(25).map((p) => p.id).toSet();
      await repo.setPackTags(expected, {a.id, b.id});
      final first = all.items.first, second = all.items[1];
      final manifest = await repo.api.json(
        'GET',
        '/api/v1/packs/${first.id}/pages',
        query: {'v': '${first.contentVersion}'},
      );
      final pages = (manifest['items'] as List).cast<Map>();
      expect(pages.length, 3);
      await fixture(
        '/__fixture/reader/fail-page?pack_id=${first.id}&page_id=${pages.first['id']}',
      );
      await t.pumpWidget(VideoViewerApp(repository: repo));
      PackReaderPageState reader() =>
          t.state<PackReaderPageState>(find.byType(PackReaderPage));
      PackCatalogPageState catalog() =>
          t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      Future<Map<String, dynamic>> stats() =>
          fixture('/__fixture/reader/stats');
      Future<Map> stored() async =>
          (await repo.api.json('GET', '/api/v1/packs/${first.id}'))['progress']
              as Map;
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint('RECOVERY_TIMEOUT $why');
            if (find.byType(PackReaderPage).evaluate().isNotEmpty) {
              debugPrint(
                'RECOVERY_STATE index=${reader().session.index} busy=${reader().session.busy} pending=${reader().session.pendingKind} error=${reader().session.error}',
              );
            }
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        await t.pump(const Duration(milliseconds: 150));
        expect(t.takeException(), isNull);
      }

      Future<void> fixtureUntil(
        bool Function(Map<String, dynamic>) done,
        String why,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!done(await stats())) {
          if (DateTime.now().isAfter(deadline)) fail('Timed out: $why');
          await t.pump(const Duration(milliseconds: 80));
        }
      }

      Future<void> tap(Finder target) async {
        await t.ensureVisible(target);
        await until(
          () => target.hitTestable().evaluate().isNotEmpty,
          'hit target',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 200));
      }

      Future<void> shot(String name) async {
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/recovery-$name');
        await t.pump(const Duration(seconds: 1));
      }

      await until(
        () => find.byKey(const Key('nav-tags')).evaluate().isNotEmpty,
        'shell',
      );
      await tap(find.byKey(const Key('nav-tags')));
      await tap(find.byKey(const Key('kind-pack')));
      await tap(find.byKey(Key('pack-tag-${a.id}')));
      await tap(find.byKey(Key('pack-tag-${b.id}')));
      await tap(find.byKey(const Key('tag-view-results')));
      await until(
        () => find.byKey(const Key('pack-search')).evaluate().isNotEmpty,
        'tag result catalog',
      );
      await tap(find.byKey(const Key('pack-search')));
      await t.enterText(find.byKey(const Key('pack-search')), '图包');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await until(
        () =>
            t.view.viewInsets.bottom == 0 &&
            !catalog().data.loading &&
            catalog().data.total == 25,
        'full selected query',
      );
      final queryKey = catalog().entry.queryKey;
      expect(catalog().entry.source, BrowseSource.tags);
      expect(catalog().entry.query.tags, {a.id, b.id});
      expect(catalog().entry.query.search, '图包');
      expect(catalog().data.items.length, 24);
      final tile = find.byKey(Key('pack-tile-${first.id}'));
      await until(
        () => t
            .widgetList<RawImage>(
              find.descendant(of: tile, matching: find.byType(RawImage)),
            )
            .any((w) => w.image != null),
        'actual card cover',
      );
      await tap(tile);
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            !reader().session.busy,
        'reader created',
      );
      await fixtureUntil(
        (s) =>
            (s['images'] as List).where((r) => r['status'] == 503).length == 3,
        'bounded automatic image attempts',
      );
      expect(reader().session.opened, isFalse);
      expect(
        (await repo.api.json(
          'GET',
          '/api/v1/recent',
          query: {'kind': 'pack'},
        ))['total'],
        0,
      );
      expect(
        (await repo.api.json('GET', '/api/v1/packs/${first.id}'))['progress'],
        isNull,
      );
      final retry = find.byKey(Key('reader-image-retry-${pages.first['id']}'));
      await until(
        () => retry.hitTestable().evaluate().isNotEmpty,
        'failed page retry',
      );
      await shot('image-error');
      await tap(retry);
      await until(
        () => reader().session.opened && !reader().session.busy,
        'manual image retry actual first frame',
      );
      expect(reader().session.range!.candidateCount, 25);
      final identity = reader().session.range!.id;
      expect(reader().session.range!.source, BrowseSource.tags);
      expect(
        (await stats())['images'].take(4).map((r) => r['status']).toList(),
        [503, 503, 503, 200],
      );
      await shot('image-ready');

      // Unknown and NOT accepted: query only, then explicit resend of the same key.
      final initialRevision = (await stored())['revision'] as int;
      await fixture('/__fixture/reader/drop-progress?pack_id=${first.id}');
      await tap(find.byTooltip('下一张'));
      await until(
        () =>
            reader().session.pendingKind == 'progress' &&
            !reader().session.busy &&
            reader().session.error.isNotEmpty,
        'unknown unaccepted save',
      );
      expect(reader().session.index, 1);
      expect((await stored())['revision'], initialRevision);
      await tap(find.text('查询操作结果'));
      await until(
        () => reader().session.canResend && !reader().session.busy,
        'receipt absent permits explicit resend',
      );
      final dropped = (await stats())['progress'] as List;
      expect(dropped.length, 1);
      expect(dropped.single['mode'], 'before');
      expect(dropped.single['committed'], isFalse);
      await shot('unknown');
      expect(
        ((await stats())['progress'] as List).length,
        1,
        reason: 'unknown result cannot automatically resubmit',
      );
      await tap(find.text('再次提交原请求'));
      await until(
        () =>
            !reader().session.hasPending &&
            !reader().session.busy &&
            !reader().session.unsaved,
        'explicit same-command save',
      );
      final resent = (await stats())['progress'] as List;
      expect(resent.length, 2);
      expect(resent[0]['request_hash'], resent[1]['request_hash']);
      expect(resent[0]['expected_revision'], resent[1]['expected_revision']);
      expect((await stored())['revision'], initialRevision + 1);
      expect((await stored())['page_id'], pages[1]['id']);

      // Accepted but reply lost: the receipt resolves it without another PATCH.
      await fixture('/__fixture/reader/lose-progress?pack_id=${first.id}');
      await tap(find.byTooltip('下一张'));
      await until(
        () =>
            reader().session.pendingKind == 'progress' &&
            !reader().session.busy &&
            reader().session.error.isNotEmpty,
        'committed acknowledgement lost',
      );
      expect((await stored())['page_id'], pages[2]['id']);
      expect((await stored())['revision'], initialRevision + 2);
      final lost = (await stats())['progress'] as List;
      expect(lost.length, 3);
      expect(lost.last['mode'], 'after');
      expect(lost.last['committed'], isTrue);
      await tap(find.text('下一包').last);
      expect(reader().session.range!.pack!.id, first.id);
      expect(reader().session.range!.id, identity);
      await tap(find.text('查询操作结果'));
      await until(
        () =>
            !reader().session.hasPending &&
            !reader().session.busy &&
            !reader().session.unsaved,
        'accepted receipt recovered',
      );
      expect(((await stats())['progress'] as List).length, 3);
      expect(reader().session.cursor!.progressRevision, initialRevision + 2);
      await shot('receipt');

      await tap(find.byTooltip('上一张'));
      await until(
        () => reader().session.index == 1 && reader().session.unsaved,
        'second page before vertical mode',
      );
      await tap(find.byTooltip('阅读设置'));
      await tap(find.text('纵向拼接'));
      await until(
        () =>
            reader().session.preferences.mode == ReaderMode.vertical &&
            !reader().session.busy,
        'vertical saved',
      );
      await tap(find.text('继续阅读'));
      await until(
        () => find.byKey(const Key('reader-vertical')).evaluate().isNotEmpty,
        'vertical ready',
      );
      await t.drag(
        find.byKey(const Key('reader-vertical')),
        const Offset(0, -90),
      );
      await until(
        () =>
            reader().session.index == 1 &&
            reader().session.offsetRatio > .05 &&
            reader().session.unsaved,
        'unsaved actual vertical movement',
      );
      final ratio = reader().session.offsetRatio;
      final beforeBackground = (await stored())['revision'] as int;
      expect(
        reader().session.unsaved,
        isTrue,
        reason: 'background begins with unsaved movement',
      );
      await t.runAsync(() async {
        debugPrint('VV_E2E_DEVICE_BACKGROUND');
        try {
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while ((WidgetsBinding.instance.lifecycleState !=
                      AppLifecycleState.paused ||
                  reader().session.busy ||
                  reader().session.unsaved) &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(
            WidgetsBinding.instance.lifecycleState,
            AppLifecycleState.paused,
          );
          expect(reader().session.unsaved, isFalse);
          final saved = await stored();
          expect(saved['page_id'], pages[1]['id']);
          expect(saved['offset_ratio'], closeTo(ratio, .02));
          expect(saved['revision'], greaterThan(beforeBackground));
          debugPrint('READER_BACKGROUND_RESULT paused=true saved=true');
        } finally {
          debugPrint('VV_E2E_DEVICE_FOREGROUND');
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(
            WidgetsBinding.instance.lifecycleState,
            AppLifecycleState.resumed,
          );
        }
      });
      await t.pump(const Duration(milliseconds: 300));
      expect(
        lifecycle.states,
        containsAllInOrder([
          AppLifecycleState.paused,
          AppLifecycleState.resumed,
        ]),
      );
      expect(reader().session.range!.id, identity);
      expect(reader().session.index, 1);
      expect(reader().session.offsetRatio, closeTo(ratio, .02));
      await shot('background');

      await tap(find.text('整包标签'));
      await until(
        () => find
            .widgetWithText(FilterChip, '恢复范围二')
            .hitTestable()
            .evaluate()
            .isNotEmpty,
        'whole pack tag editor',
      );
      await tap(find.widgetWithText(FilterChip, '恢复范围二'));
      await tap(find.text('保存整包标签'));
      await until(
        () =>
            find.text('保存整包标签').evaluate().isEmpty &&
            reader().session.opened &&
            !reader().session.busy,
        'return to reader after editing tags',
      );
      expect(reader().session.range!.id, identity);
      expect(reader().session.range!.candidateCount, 25);
      expect(reader().session.range!.pack!.id, first.id);
      expect(reader().session.currentPage!.id, pages[1]['id']);
      expect(reader().session.offsetRatio, closeTo(ratio, .02));
      expect(
        (await repo.api.json('GET', '/api/v1/packs/${first.id}'))['tag_ids'],
        [a.id],
      );
      expect(
        (await repo.loadPacks(PackQuery(search: '图包', tags: {a.id, b.id})))
            .total,
        24,
      );
      await shot('tags');
      await tap(find.text(reader().sourceCaption));
      await until(
        () =>
            reader().session.queuePage != null &&
            !reader().session.loadingQueue,
        'full original queue',
      );
      expect(reader().session.queuePage!.total, 25);
      expect(
        reader().session.queuePage!.entries.map((e) => e.pack.id).toSet(),
        expected,
      );
      await shot('queue');
      await tap(find.byTooltip('关闭面板'));
      await tap(find.text('下一包').last);
      await until(
        () =>
            reader().session.range!.pack?.id == second.id &&
            reader().session.opened &&
            !reader().session.busy,
        'next remains inside frozen range',
      );
      expect(reader().session.range!.id, identity);
      expect(reader().session.range!.candidateCount, 25);
      expect(reader().session.preferences.mode, ReaderMode.horizontal);
      await tap(find.byTooltip('返回来源'));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isEmpty &&
            !catalog().data.loading &&
            catalog().pendingReturn == null,
        'filtered tag catalog restored',
      );
      expect(catalog().entry.queryKey, queryKey);
      expect(catalog().entry.source, BrowseSource.tags);
      expect(catalog().data.total, 24);
      expect(
        catalog().data.items.map((p) => p.id).toSet(),
        expected.difference({first.id}),
      );
      await shot('return');
      final recent = await repo.api.json(
        'GET',
        '/api/v1/recent',
        query: {'kind': 'pack'},
      );
      expect((recent['items'] as List).map((p) => p['id']).toSet(), {
        first.id,
        second.id,
      });
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace
            .where(
              (r) =>
                  r['method'] == 'POST' && r['path'] == '/api/v1/pack-sessions',
            )
            .length,
        1,
      );
      final receipts = trace
          .where(
            (r) =>
                r['method'] == 'GET' &&
                (r['path'] as String).contains(
                  '/pack-reading-requests/progress/',
                ),
          )
          .map((r) => r['status'])
          .toList();
      expect(receipts, [404, 200]);
      debugPrint(
        'READER_RECOVERY_RESULT image_retry=bounded_and_explicit missing_receipt=resend_same_key lost_ack=read_only background=actual_android tags=fixed_25 returned_results=24',
      );
    },
  );
}
