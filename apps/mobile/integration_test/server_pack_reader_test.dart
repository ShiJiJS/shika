import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF5 real reader frames, vertical resume, overview and fixed next pack return',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '阅读图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final catalog = await repo.loadPacks(PackQuery());
      expect(catalog.total, 27);
      expect(catalog.items.length, 24);
      final first = catalog.items.first, second = catalog.items[1];
      await t.pumpWidget(VideoViewerApp(repository: repo));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
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
        await t.pump(const Duration(milliseconds: 180));
      }

      PackReaderPageState state() =>
          t.state<PackReaderPageState>(find.byType(PackReaderPage));
      Future<void> shot(String phase) async {
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/reader-$phase');
        await t.pump(const Duration(seconds: 1));
      }

      await until(() => find.text('图包').evaluate().isNotEmpty, 'type picker');
      await tap(find.text('图包'));
      await until(
        () => find.byKey(Key('pack-tile-${first.id}')).evaluate().isNotEmpty,
        'pack card',
      );
      expect(
        (await repo.api.json(
          'GET',
          '/api/v1/recent',
          query: {'kind': 'pack'},
        ))['total'],
        0,
      );
      await until(
        () => t
            .widgetList<RawImage>(
              find.descendant(
                of: find.byKey(Key('pack-tile-${first.id}')),
                matching: find.byType(RawImage),
              ),
            )
            .any((image) => image.image != null),
        'target pack cover decoded before card tap',
      );
      await tap(find.byKey(Key('pack-tile-${first.id}')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            state().session.opened &&
            !state().session.busy,
        'actual first image opened',
      );
      expect(state().session.range!.candidateCount, 27);
      expect(state().session.currentPage!.image, isNotNull);
      expect(
        (await repo.api.json(
          'GET',
          '/api/v1/recent',
          query: {'kind': 'pack'},
        ))['total'],
        1,
      );
      await shot('horizontal');
      await tap(find.byTooltip('下一张'));
      await until(
        () => state().session.index == 1 && state().session.unsaved,
        'second displayed image',
      );
      expect(await state().session.flush(), isTrue);
      await tap(find.byTooltip('阅读设置'));
      await tap(find.text('纵向拼接'));
      await until(
        () =>
            state().session.preferences.mode == ReaderMode.vertical &&
            !state().session.busy,
        'vertical saved',
      );
      await tap(find.text('继续阅读'));
      await until(
        () => find.byKey(const Key('reader-vertical')).evaluate().isNotEmpty,
        'vertical body',
      );
      await t.drag(
        find.byKey(const Key('reader-vertical')),
        const Offset(0, -100),
      );
      await t.pump(const Duration(milliseconds: 200));
      await until(
        () => state().session.index == 1 && state().session.offsetRatio > .05,
        'actual vertical row inset',
      );
      final ratio = state().session.offsetRatio,
          pageId = state().session.currentPage!.id;
      expect(await state().session.flush(), isTrue);
      await shot('vertical');
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'return library',
      );
      final stored =
          (await repo.api.json('GET', '/api/v1/packs/${first.id}'))['progress']
              as Map;
      expect(stored['page_id'], pageId);
      expect(stored['offset_ratio'], closeTo(ratio, .02));
      await until(
        () => t
            .widgetList<RawImage>(
              find.descendant(
                of: find.byKey(Key('pack-tile-${first.id}')),
                matching: find.byType(RawImage),
              ),
            )
            .any((image) => image.image != null),
        'target pack cover decoded before card tap',
      );
      await tap(find.byKey(Key('pack-tile-${first.id}')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            state().session.opened &&
            !state().session.busy,
        'reopen current image',
      );
      expect(state().session.index, 1);
      expect(state().session.preferences.mode, ReaderMode.vertical);
      expect(state().session.offsetRatio, closeTo(ratio, .02));
      await shot('reopen');
      await tap(find.text('总览'));
      await until(
        () => find.text('3').hitTestable().evaluate().isNotEmpty,
        'real overview third page',
      );
      await until(
        () =>
            t
                .widgetList<RawImage>(
                  find.descendant(
                    of: find.byKey(const Key('reader-overview-sheet')),
                    matching: find.byType(RawImage),
                  ),
                )
                .where((image) => image.image != null)
                .length >=
            3,
        'overview thumbnails decoded',
      );
      await shot('overview');
      await tap(find.text('3'));
      await until(
        () => state().session.index == 2 && state().session.unsaved,
        'overview jump actual current frame',
      );
      expect(await state().session.flush(), isTrue);
      final jumped =
          (await repo.api.json('GET', '/api/v1/packs/${first.id}'))['progress']
              as Map;
      expect(jumped['page_id'], state().session.currentPage!.id);
      final identity = state().session.range!.id;
      await tap(find.text('下一包').last);
      await until(
        () =>
            state().session.range?.pack?.id == second.id &&
            state().session.opened &&
            !state().session.busy,
        'manual next actual image',
      );
      expect(state().session.range!.id, identity);
      expect(state().session.range!.candidateCount, 27);
      expect(state().session.preferences.mode, ReaderMode.horizontal);
      expect(
        (await repo.api.json(
          'GET',
          '/api/v1/recent',
          query: {'kind': 'pack'},
        ))['total'],
        2,
      );
      await shot('next');
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'reader exit',
      );
      await shot('return');
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace
            .where(
              (r) =>
                  r['method'] == 'POST' && r['path'] == '/api/v1/pack-sessions',
            )
            .length,
        2,
      );
      expect(
        trace
            .where(
              (r) =>
                  r['method'] == 'POST' &&
                  (r['path'] as String).endsWith('/opened'),
            )
            .length,
        3,
      );
      final recent = await repo.api.json(
        'GET',
        '/api/v1/recent',
        query: {'kind': 'pack'},
      );
      expect((recent['items'] as List).map((p) => p['id']).toSet(), {
        first.id,
        second.id,
      });
    },
  );
}
