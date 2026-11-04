import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/features/packs/reader_images.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '30-page overview: cancel queued cells and metadata, paginate, reopen and jump',
    (t) async {
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect(
        'http://10.0.2.2',
        8768,
        'prototype-fidelity-owned-only',
      );
      final packs = await repo.loadPacks(PackQuery());
      final summer = packs.items.singleWhere((p) => p.name.contains('034'));
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) fail('Thumbnail timeout: $why');
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> poll(Future<bool> Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!(await done())) {
          if (DateTime.now().isAfter(deadline)) fail('Thumbnail poll: $why');
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().length == 1, 'one $f');
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 100));
        await until(() => f.hitTestable().evaluate().length == 1, 'hit $f');
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 100));
      }

      Future<void> waitReal(Duration duration) async {
        final end = DateTime.now().add(duration);
        while (DateTime.now().isBefore(end)) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> capture(String name) async {
        if (name.contains('held') || name.contains('pending')) {
          // A deliberately pending image animates its spinner. Settling would
          // wait for the transport deadline and test a retry instead of close.
          await t.pump(const Duration(milliseconds: 100));
        } else {
          await t.pumpAndSettle(const Duration(milliseconds: 100));
        }
        final inReader = find.byType(PackReaderPage).evaluate().isNotEmpty;
        final media = MediaQuery.of(
          t.element(
            inReader
                ? find.byType(PackReaderPage)
                : find.byKey(const Key('app-shell')),
          ),
        );
        List<double> rectangle(Rect r) => [r.left, r.top, r.width, r.height];
        final keys = <String, List<double>>{};
        for (final key in [
          'reader-header',
          'reader-canvas',
          'reader-controls',
          'reader-tools',
          'reader-scope',
          'reader-horizontal',
          'reader-vertical',
          'reader-overview-sheet',
          'reader-trash-pack',
          'reader-settings-done',
          'reader-range-pagination',
          'reader-range-caption',
          'pack-search',
        ]) {
          final target = find.byKey(Key(key));
          if (target.evaluate().length == 1) {
            keys[key] = rectangle(t.getRect(target));
          }
        }
        final texts = <Map<String, dynamic>>[];
        for (final e in find.byType(Text).evaluate()) {
          final box = e.renderObject;
          if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
          final position = box.localToGlobal(Offset.zero);
          if (position.dy < 0 || position.dy >= media.size.height) continue;
          final w = e.widget as Text;
          texts.add({
            'text': w.data ?? w.textSpan?.toPlainText(),
            'rect': rectangle(position & box.size),
            'fontSize': w.style?.fontSize,
          });
        }
        debugPrint(
          'FIDELITY_METRICS:${jsonEncode({
            'state': name,
            'size': [media.size.width, media.size.height],
            'dpr': media.devicePixelRatio,
            'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
            'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
            'textScale': media.textScaler.scale(14) / 14,
            'overview_cells': find.descendant(of: find.byKey(const Key('reader-overview-sheet')), matching: find.byType(ReaderImage)).evaluate().map((e) => {'id': (e.widget as ReaderImage).page.id, 'ordinal': (e.widget as ReaderImage).page.ordinal, 'active': (e.widget as ReaderImage).active}).toList(),
            'keys': keys,
            'texts': texts,
            if (inReader) 'reading': {'pack': reader().session.range!.pack!.id, 'index': reader().session.index, 'page_id': reader().session.currentPage?.id, 'ratio': reader().session.offsetRatio, 'mode': reader().session.preferences.mode.name, 'controls': reader().controls, 'quick': reader().quick, 'range': reader().session.range!.id},
          })}',
        );
        await control('/checkpoint/$name', post: true);
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Host screenshot missing: $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      await until(
        () => find.byKey(const Key('kind-pack')).evaluate().length == 1,
        'switch',
      );
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () =>
            find.byType(PackCatalogPage).evaluate().isNotEmpty &&
            !t
                .state<PackCatalogPageState>(find.byType(PackCatalogPage))
                .data
                .loading,
        'pack library',
      );
      await t.ensureVisible(find.byKey(Key('pack-tile-${summer.id}')));
      await tap(find.byKey(Key('pack-tile-${summer.id}')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            reader().session.opened,
        'actual main decode/open',
      );
      await waitReal(const Duration(seconds: 2));
      await capture('pages-reader');
      final baseline = reader().session;
      final rangeId = baseline.range!.id,
          pageId = baseline.currentPage!.id,
          index = baseline.index,
          mode = baseline.preferences.mode;
      final detailBefore = await repo.api.json(
        'GET',
        '/api/v1/packs/${summer.id}',
      );
      List<Map> writes(Map<String, dynamic> state) =>
          (state['requests'] as List)
              .cast<Map>()
              .where((r) => r['method'] != 'GET')
              .toList();
      final writesBefore = writes(await control('/state'));
      final sheet = find.byKey(const Key('reader-overview-sheet'));
      final retry = find.descendant(of: sheet, matching: find.text('重试'));
      int decoded() => find
          .descendant(of: sheet, matching: find.byType(RawImage))
          .evaluate()
          .where((e) => (e.widget as RawImage).image != null)
          .length;
      Future<void> close() async {
        Navigator.of(t.element(sheet)).pop();
        await until(() => sheet.evaluate().isEmpty, 'sheet closed');
        await t.pumpAndSettle();
      }

      await control('/thumbnail-failure/hold', post: true);
      unawaited(reader().overview());
      await until(() => sheet.evaluate().isNotEmpty, 'first overview');
      await poll(
        () async =>
            ((await control('/state'))['thumbnail_streams'] as List).length ==
            3,
        'three active streams; others queued',
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(ReaderImage)),
        findsNWidgets(24),
      );
      await capture('pages-held');
      await control('/thumbnail-failure/off', post: true);
      await control('/thumbnail-manifest/hold-24', post: true);
      await tap(find.descendant(of: sheet, matching: find.text('下一页')));
      await poll(
        () async =>
            ((await control('/state'))['manifest_events'] as List).length == 1,
        'next manifest held',
      );
      await poll(
        () async => ((await control('/state'))['thumbnail_streams'] as List)
            .every((s) => s['cancelled'] == true),
        'old active requests cancelled before manifest response',
      );
      final heldState = await control('/state');
      expect((heldState['thumbnail_streams'] as List).length, 3);
      final oldIds = find
          .descendant(of: sheet, matching: find.byType(ReaderImage))
          .evaluate()
          .map((e) => (e.widget as ReaderImage).page.id)
          .toSet();
      expect(oldIds.length, 24);
      await capture('pages-next-pending');
      await control('/thumbnail-manifest/off', post: true);
      await until(
        () =>
            decoded() == 6 &&
            retry.evaluate().isEmpty &&
            find
                .byKey(const Key('reader-overview-page-24'))
                .evaluate()
                .isNotEmpty,
        'page 25-30 decoded',
      );
      final lastIds = find
          .descendant(of: sheet, matching: find.byType(ReaderImage))
          .evaluate()
          .map((e) => (e.widget as ReaderImage).page.id)
          .toList();
      expect(lastIds.length, 6);
      expect(lastIds.toSet().intersection(oldIds), isEmpty);
      await t.ensureVisible(find.byKey(const Key('reader-overview-page-24')));
      await capture('pages-second');
      await tap(find.descendant(of: sheet, matching: find.text('上一页')));
      await until(
        () =>
            decoded() == 24 &&
            retry.evaluate().isEmpty &&
            find
                .byKey(const Key('reader-overview-page-0'))
                .evaluate()
                .isNotEmpty,
        'all first 24 decoded',
      );
      await t.ensureVisible(find.byKey(const Key('reader-overview-page-0')));
      await capture('pages-first-return');
      await control('/thumbnail-manifest/hold-24', post: true);
      await tap(find.descendant(of: sheet, matching: find.text('下一页')));
      await poll(
        () async =>
            ((await control('/state'))['manifest_events'] as List).length == 2,
        'second metadata request held',
      );
      await capture('pages-close-pending');
      await control('/checkpoint/pages-device-back', post: true);
      await poll(
        () async => (await control('/state'))['ack'] == true,
        'real Android back',
      );
      await until(() => sheet.evaluate().isEmpty, 'sheet removed');
      await poll(
        () async =>
            ((await control('/state'))['manifest_events'] as List)
                .last['cancelled'] ==
            true,
        'metadata request cancelled',
      );
      await control('/thumbnail-manifest/off', post: true);
      await waitReal(const Duration(seconds: 2));
      await capture('pages-cancelled');
      unawaited(reader().overview());
      await until(
        () =>
            sheet.evaluate().isNotEmpty &&
            decoded() == 24 &&
            retry.evaluate().isEmpty,
        'reopened first page',
      );
      await capture('pages-reopened');
      await close();
      expect(reader().session.range!.id, rangeId);
      expect(reader().session.currentPage!.id, pageId);
      expect(reader().session.index, index);
      expect(reader().session.preferences.mode, mode);
      expect(
        await repo.api.json('GET', '/api/v1/packs/${summer.id}'),
        detailBefore,
      );
      expect(writes(await control('/state')), writesBefore);
      debugPrint(
        'PAGINATION_READING_UNCHANGED:${jsonEncode({'range': rangeId, 'page': pageId, 'index': index, 'mode': mode.name, 'writes': writesBefore.length})}',
      );
      unawaited(reader().overview());
      await until(
        () => sheet.evaluate().isNotEmpty && decoded() == 24,
        'jump overview',
      );
      await tap(find.descendant(of: sheet, matching: find.text('下一页')));
      await until(
        () =>
            decoded() == 6 &&
            retry.evaluate().isEmpty &&
            find
                .byKey(const Key('reader-overview-page-29'))
                .evaluate()
                .isNotEmpty,
        'jump last manifest',
      );
      await t.ensureVisible(find.byKey(const Key('reader-overview-page-29')));
      await capture('pages-jump-list');
      await tap(find.byKey(const Key('reader-overview-page-29')));
      await until(
        () =>
            sheet.evaluate().isEmpty &&
            reader().session.index == 29 &&
            reader().session.currentPage!.id == lastIds.last,
        'actual last page jump',
      );
      await waitReal(const Duration(seconds: 2));
      final detailAfter = await repo.api.json(
        'GET',
        '/api/v1/packs/${summer.id}',
      );
      expect((detailAfter['progress'] as Map)['page_id'], lastIds.last);
      expect(reader().session.range!.id, rangeId);
      expect(reader().session.preferences.mode, mode);
      await capture('pages-jump');
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'source returned',
      );
      await capture('pages-return');
      debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
    },
  );
}
