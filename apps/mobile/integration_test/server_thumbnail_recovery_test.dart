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

import 'native_workspace_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'overview bounded recovery, manual recovery, cancellation and unchanged reading',
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
        'client-ui-owned-only',
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
        await until(() => f.hitTestable().evaluate().length == 1, 'hit $f');
        await t.ensureVisible(f);
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
        if (name == 'thumb-hold') {
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
          'WORKSPACE_METRICS:${jsonEncode({
            'state': name,
            'size': [media.size.width, media.size.height],
            'dpr': media.devicePixelRatio,
            'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
            'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
            'textScale': media.textScaler.scale(14) / 14,
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
      await capture('thumb-reader');
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
      Future<void> open(String mode) async {
        await control('/thumbnail-failure/$mode', post: true);
        unawaited(reader().overview());
        await until(() => sheet.evaluate().length == 1, 'sheet');
      }

      Future<void> close() async {
        Navigator.of(t.element(sheet)).pop();
        await until(() => sheet.evaluate().isEmpty, 'sheet closed');
        await t.pumpAndSettle();
      }

      Future<void> counts(int expected, {int cells = 6}) async {
        await poll(() async {
          final attempts =
              (await control('/state'))['thumbnail_attempts'] as Map;
          return attempts.length == cells &&
              attempts.values.every((n) => n == expected);
        }, '$cells active thumbnail counts $expected');
      }

      await open('recover');
      await until(
        () => decoded() == 6 && retry.evaluate().isEmpty,
        'six auto-decoded thumbnails',
      );
      final recoveredAttempts =
          (await control('/state'))['thumbnail_attempts'] as Map;
      expect(recoveredAttempts.length, 6);
      expect(recoveredAttempts.values.every((n) => n >= 2 && n <= 3), isTrue);
      await capture('thumb-auto-recovered');
      await close();
      await open('bounded');
      await counts(3);
      await until(() => retry.evaluate().length == 6, 'bounded six retries');
      await waitReal(const Duration(seconds: 3));
      await counts(3);
      await capture('thumb-bounded');
      await control('/thumbnail-failure/off', post: true);
      final ids = find
          .descendant(of: sheet, matching: find.byType(ReaderImage))
          .evaluate()
          .map((e) => (e.widget as ReaderImage).page.id)
          .toList();
      expect(ids.length, 6);
      for (final id in ids) {
        await tap(
          find.descendant(
            of: sheet,
            matching: find.byKey(Key('reader-image-retry-$id')),
          ),
        );
      }
      await until(
        () => decoded() == 6 && retry.evaluate().isEmpty,
        'manual decoded six',
      );
      await capture('thumb-manual-recovered');
      await close();
      await open('hold');
      await counts(1, cells: 3);
      await until(() => decoded() == 0, 'pending bodies');
      await capture('thumb-hold');
      await counts(1, cells: 3);
      await control('/checkpoint/thumb-device-back', post: true);
      await poll(
        () async => (await control('/state'))['ack'] == true,
        'real Android back',
      );
      await until(() => sheet.evaluate().isEmpty, 'back closes sheet only');
      await poll(() async {
        final streams = (await control('/state'))['thumbnail_streams'] as List;
        return streams.length == 3 &&
            streams.every((s) => s['cancelled'] == true);
      }, 'three actual stream cancellations; three queued cells cancelled');
      await waitReal(const Duration(seconds: 3));
      await counts(1, cells: 3);
      await capture('thumb-cancelled');
      await open('off');
      await until(
        () => decoded() == 6 && retry.evaluate().isEmpty,
        'reopened real six frames',
      );
      await capture('thumb-reopened');
      await close();
      expect(reader().session.range!.id, rangeId);
      expect(reader().session.currentPage!.id, pageId);
      expect(reader().session.index, index);
      expect(reader().session.preferences.mode, mode);
      final detailAfter = await repo.api.json(
        'GET',
        '/api/v1/packs/${summer.id}',
      );
      expect(detailAfter, detailBefore);
      expect(writes(await control('/state')), writesBefore);
      debugPrint(
        'THUMBNAIL_READING_UNCHANGED:${jsonEncode({'range': rangeId, 'page': pageId, 'index': index, 'mode': mode.name, 'writes': writesBefore.length})}',
      );
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'source returned',
      );
      await capture('thumb-return');
      debugPrint('WORKSPACE_VERIFIED');
    },
  );
}
