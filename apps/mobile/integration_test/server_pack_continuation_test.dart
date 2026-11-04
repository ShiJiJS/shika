import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real continuation stays read-only and opens the complete library range',
    (t) async {
      final previousError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('CONTINUATION_LAYOUT_ERROR:$details');
        previousError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousError);
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
      final all = await repo.loadPacks(PackQuery(), limit: 24);
      expect(all.total, 4);
      final summer = all.items.singleWhere((p) => p.name.contains('034'));
      final initial = Map<String, dynamic>.from(
        (await repo.api.json('GET', '/api/v1/packs/${summer.id}'))['progress']
            as Map,
      );
      expect(initial['page_index'], 2);
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      Future<void> until(bool Function() condition, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Continuation timeout: $label');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        await until(() => target.evaluate().length == 1, 'one target $target');
        if (target.hitTestable().evaluate().isEmpty) {
          await Scrollable.ensureVisible(
            t.element(target),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
        await until(
          () => target.hitTestable().evaluate().length == 1,
          'visible $target',
        );
        await t.tap(target.hitTestable());
        await t.pump(const Duration(milliseconds: 350));
      }

      PackCatalogPageState catalog() => t.state(find.byType(PackCatalogPage));
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      Future<Map<String, dynamic>> progress() async =>
          Map<String, dynamic>.from(
            (await repo.api.json(
                  'GET',
                  '/api/v1/packs/${summer.id}',
                ))['progress']
                as Map,
          );
      Future<void> capture(String name) async {
        await t.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        final root = find.byType(PackReaderPage).evaluate().isNotEmpty
            ? find.byType(PackReaderPage)
            : find.byKey(const Key('app-shell'));
        final media = MediaQuery.of(t.element(root));
        List<double> rect(Rect r) => [r.left, r.top, r.width, r.height];
        final texts = <Map<String, dynamic>>[];
        for (final element in find.byType(Text).evaluate()) {
          final widget = element.widget as Text, box = element.renderObject;
          if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
          final pos = box.localToGlobal(Offset.zero);
          if (pos.dy < 0 || pos.dy >= media.size.height) continue;
          texts.add({
            'text': widget.data ?? widget.textSpan?.toPlainText(),
            'rect': rect(pos & box.size),
            'fontSize': widget.style?.fontSize,
          });
        }
        final keys = <String, List<double>>{};
        for (final key in [
          'app-navigation',
          'pack-search',
          'pack-count',
          'pack-continuation',
          'pack-continuation-position',
        ]) {
          final f = find.byKey(Key(key));
          if (f.evaluate().length == 1) keys[key] = rect(t.getRect(f));
        }
        debugPrint(
          'FIDELITY_METRICS:${jsonEncode({
            'state': name,
            'size': [media.size.width, media.size.height],
            'dpr': media.devicePixelRatio,
            'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
            'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
            'textScale': media.textScaler.scale(14) / 14,
            'keys': keys,
            'texts': texts,
          })}',
        );
        await control('/checkpoint/$name', post: true);
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Missing screenshot $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () =>
            catalog().initialized &&
            !catalog().continuationLoading &&
            !catalog().data.loading,
        'fresh catalog and summary',
      );
      expect(catalog().data.total, 4);
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      expect(await progress(), initial);
      final trace = (await control('/state'))['requests'] as List;
      expect(
        trace.where(
          (r) => r['method'] == 'POST' && r['path'] == '/api/v1/pack-sessions',
        ),
        isEmpty,
      );
      await capture('continue-empty');
      await tap(find.byKey(Key('pack-tile-${summer.id}')));
      await until(
        () => reader().session.opened && !reader().session.busy,
        'actual resumed first frame',
      );
      expect(reader().session.index, 2);
      final origin = reader().widget.returnContext!;
      await tap(find.byTooltip('下一张'));
      await until(
        () => reader().session.index == 3 && !reader().session.busy,
        'fourth page frame',
      );
      expect(await reader().session.flush(), isTrue);
      final saveDeadline = DateTime.now().add(const Duration(seconds: 25));
      while ((await progress())['page_index'] != 3) {
        if (DateTime.now().isAfter(saveDeadline)) {
          fail('Fourth decoded frame did not persist');
        }
        await t.pump(const Duration(milliseconds: 100));
        expect(await reader().session.flush(), isTrue);
      }
      await capture('continue-read');
      await tap(find.byTooltip('返回来源'));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isEmpty &&
            catalog().hasContinuation &&
            !catalog().data.loading &&
            !catalog().continuationLoading,
        'real history appears',
      );
      await t.pumpAndSettle();
      final restoredIndex = catalog().data.items.indexWhere(
        (p) => p.id == origin.scrollAnchor,
      );
      expect(restoredIndex, greaterThanOrEqualTo(0));
      final expectedPixels = origin.scrollOffset == 0 && origin.scrollIndex == 0
          ? 0.0
          : catalog().listHeader +
                restoredIndex ~/ catalog().columns * catalog().stride +
                origin.scrollInset;
      final expectedReturn = expectedPixels.clamp(
        0.0,
        catalog().scroll.position.maxScrollExtent,
      );
      expect(
        catalog().scroll.offset,
        closeTo(expectedReturn, 1),
        reason: 'Return retains the actual card anchor, including large text',
      );
      final returnedOffset = catalog().scroll.offset;
      // Enlarged rows can place the summary outside the lazy viewport after
      // returning to a lower card. Reveal it with a real scroll, not a new load.
      final catalogScroll = find
          .descendant(
            of: find.byType(PackCatalogPage),
            matching: find.byType(Scrollable),
          )
          .last;
      await t.drag(catalogScroll, const Offset(0, 1400));
      await t.pumpAndSettle();
      expect(find.text('第 4 / 6 张'), findsOneWidget);
      expect(catalog().scroll.offset, 0);
      final before = await progress();
      await capture('continue-library');
      expect(
        await progress(),
        before,
        reason: 'Summary and cover are read-only',
      );
      await tap(find.byKey(const Key('pack-continuation')));
      await until(
        () => reader().session.opened && !reader().session.busy,
        'explicit continuation first frame',
      );
      expect(reader().session.index, 3);
      expect(reader().session.entry.source, BrowseSource.library);
      expect(reader().session.entry.query.source, BrowseSource.library);
      expect(reader().session.range!.candidateCount, 4);
      expect(reader().session.range!.pack!.id, summer.id);
      final range = reader().session.range!;
      await capture('continue-reader');
      await tap(find.byTooltip('返回来源'));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isEmpty &&
            find.byKey(const Key('pack-continuation')).evaluate().length == 1 &&
            !catalog().continuationLoading,
        'return to library',
      );
      expect(catalog().scroll.offset, 0);
      expect(catalog().entry.query.count, 0);
      await capture('continue-return');
      await t.enterText(find.byKey(const Key('pack-search')), '灵梦');
      await until(
        () => !catalog().data.loading && catalog().data.total == 1,
        'filtered one pack',
      );
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      await capture('continue-scope');
      await t.enterText(find.byKey(const Key('pack-search')), '');
      await until(
        () =>
            !catalog().data.loading &&
            !catalog().continuationLoading &&
            catalog().data.total == 4,
        'clear scope',
      );
      await tap(find.byTooltip('更多'));
      await tap(find.text('多选内容'));
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      await capture('continue-multi');
      await tap(find.byTooltip('更多'));
      await tap(find.text('多选内容'));
      await until(
        () => !catalog().data.loading && !catalog().continuationLoading,
        'exit selection revalidates summary',
      );
      final stable = await progress();
      await control('/continuation-failure/on', post: true);
      await repo.refresh();
      await until(
        () =>
            find.text('续读位置暂不可用').evaluate().length == 1 &&
            !catalog().data.loading &&
            !catalog().continuationLoading,
        'summary failure retains catalog',
      );
      expect(catalog().data.total, 4);
      expect(catalog().data.items, hasLength(4));
      expect(await progress(), stable);
      await capture('continue-error');
      await control('/continuation-failure/off', post: true);
      await tap(find.text('重试'));
      await until(
        () =>
            find.byKey(const Key('pack-continuation')).evaluate().length == 1 &&
            !catalog().continuationLoading,
        'read-only retry',
      );
      expect(await progress(), stable);
      expect(catalog().scroll.offset, 0);
      await capture('continue-retry');
      await tap(find.byKey(const Key('nav-recent')));
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () => !catalog().data.loading && catalog().data.total == 1,
        'recent has only actual opened pack',
      );
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      expect(catalog().data.items.single.id, summer.id);
      await capture('continue-recent');
      debugPrint(
        'PACK_CONTINUATION_VERIFIED:${jsonEncode({'pack': summer.id, 'seed_progress': initial, 'before_summary': before, 'after_summary': stable, 'final_progress': await progress(), 'range': range.id, 'source': range.source.name, 'candidate_count': range.candidateCount, 'return_anchor': origin.scrollAnchor, 'return_offset': returnedOffset, 'expected_return_offset': expectedReturn})}',
      );
      debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
      expect(t.takeException(), isNull);
    },
  );
}
