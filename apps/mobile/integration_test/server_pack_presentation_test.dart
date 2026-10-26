import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real title and author presentation uses complete Chinese title and newest ranges',
    (t) async {
      final previousError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('PACK_PRESENTATION_ERROR:$details');
        previousError?.call(details);
      };
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
        FlutterError.onError = previousError;
      });
      await repo.connect(
        'http://10.0.2.2',
        8768,
        'prototype-fidelity-owned-only',
      );
      final initial = repo.catalogCounts.value;
      expect(initial, const MediaCatalogCounts(2, 4));
      final all = await repo.loadPacks(PackQuery());
      expect(all.items.map((p) => p.displayTitle).toList(), [
        '加藤惠 · 和服',
        '灵梦 · 新年快乐',
        '夏日祭',
        '原野上的浪漫',
      ]);
      expect(all.items.every((p) => p.author == '示例作者'), isTrue);
      final expectedIds = all.items.map((p) => p.id).toList();
      final pack = all.items.singleWhere((p) => p.name.contains('034'));
      Future<Map<String, dynamic>> progress() async =>
          Map<String, dynamic>.from(
            (await repo.api.json('GET', '/api/v1/packs/${pack.id}'))['progress']
                as Map,
          );
      final before = await progress();
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      Future<void> until(bool Function() condition, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            final page = find.byType(PackCatalogPage);
            if (page.evaluate().length == 1) {
              final state = t.state<PackCatalogPageState>(page);
              debugPrint(
                'COUNTS_TIMEOUT_STATE:${jsonEncode({'query': state.entry.query.toJson(), 'search': state.search.text, 'active': state.widget.active, 'loading': state.data.loading, 'total': state.data.total, 'error': state.data.error, 'generation': state.generation, 'continuationLoading': state.continuationLoading})}',
              );
            }
            fail('Pack presentation timeout: $reason');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder finder) async {
        await until(() => finder.evaluate().length == 1, 'one target $finder');
        if (finder.hitTestable().evaluate().isEmpty) {
          await t.ensureVisible(finder);
        }
        await until(
          () => finder.hitTestable().evaluate().length == 1,
          'visible $finder',
        );
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 350));
      }

      PackCatalogPageState catalog() => t.state(find.byType(PackCatalogPage));
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      void shown(int videos, int packs) {
        expect(
          t.widget<Text>(find.byKey(const Key('catalog-count-video'))).data,
          '$videos',
        );
        expect(
          t.widget<Text>(find.byKey(const Key('catalog-count-pack'))).data,
          '$packs',
        );
      }

      Future<void> decodedCovers() => until(
        () =>
            find
                .byType(RawImage)
                .evaluate()
                .where((e) => (e.widget as RawImage).image != null)
                .length >=
            2,
        'two decoded visible covers',
      );

      Future<void> capture(String name) async {
        await t.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        final readerPage = find.byType(PackReaderPage);
        final media = MediaQuery.of(
          t.element(
            readerPage.evaluate().isNotEmpty
                ? readerPage
                : find.byKey(const Key('app-shell')),
          ),
        );
        List<double> rectangle(Rect r) => [r.left, r.top, r.width, r.height];
        final texts = <Map<String, dynamic>>[];
        for (final element in find.byType(Text).evaluate()) {
          final widget = element.widget as Text, box = element.renderObject;
          if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
          final pos = box.localToGlobal(Offset.zero);
          if (pos.dy < 0 || pos.dy >= media.size.height) continue;
          texts.add({
            'text': widget.data ?? widget.textSpan?.toPlainText(),
            'rect': rectangle(pos & box.size),
            'fontSize': widget.style?.fontSize,
          });
        }
        final keys = <String, List<double>>{};
        for (final key in [
          'app-navigation',
          'catalog-count-video',
          'catalog-count-pack',
          'pack-search',
          'video-search',
          'pack-count',
        ]) {
          final finder = find.byKey(Key(key));
          if (finder.evaluate().length == 1) {
            keys[key] = rectangle(t.getRect(finder));
          }
        }
        debugPrint(
          'FIDELITY_METRICS:${jsonEncode({
            'state': name,
            'size': [media.size.width, media.size.height],
            'dpr': media.devicePixelRatio,
            'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
            'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
            'textScale': media.textScaler.scale(14) / 14,
            'keys': keys,
            'texts': texts,
            'counts': repo.catalogCounts.value == null ? null : {'video': repo.catalogCounts.value!.videos, 'pack': repo.catalogCounts.value!.packs},
          })}',
        );
        await control('/checkpoint/$name', post: true);
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Host did not capture $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      await until(
        () => find.byKey(const Key('kind-pack')).evaluate().length == 1,
        'library',
      );
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () => catalog().initialized && !catalog().data.loading,
        'pack list',
      );
      expect(catalog().data.items.map((p) => p.id).toList(), expectedIds);
      await decodedCovers();
      expect(await progress(), before);
      await capture('presentation-library');
      await t.enterText(find.byKey(const Key('pack-search')), '示例作者');
      await until(
        () =>
            !catalog().data.loading &&
            catalog().entry.query.search == '示例作者' &&
            catalog().data.total == 4,
        'author search',
      );
      shown(2, 4);
      await capture('presentation-author');
      await t.enterText(find.byKey(const Key('pack-search')), '夏日祭');
      await until(
        () => !catalog().data.loading && catalog().data.total == 1,
        'title search',
      );
      expect(catalog().data.items.single.id, pack.id);
      expect(find.text('在读 · 3'), findsOneWidget);
      expect(await progress(), before);
      FocusManager.instance.primaryFocus?.unfocus();
      await capture('presentation-title');
      await tap(find.byKey(Key('pack-tile-${pack.id}')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().length == 1 &&
            reader().session.opened &&
            !reader().session.busy,
        'actual title reader',
      );
      expect(reader().session.range!.candidateCount, 1);
      expect(reader().session.range!.pack!.displayTitle, '夏日祭');
      expect(find.text('示例作者 · 034'), findsOneWidget);
      final filteredRange = reader().session.range!.id;
      await capture('presentation-reader');
      await tap(find.byTooltip('图包更多'));
      await tap(find.text('图包详情'));
      expect(find.text(pack.path), findsOneWidget);
      expect(find.text('示例作者 · 034'), findsWidgets);
      await capture('presentation-details');
      await tap(find.byTooltip('关闭面板'));
      await tap(find.byTooltip('返回来源'));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isEmpty &&
            !catalog().data.loading,
        'return to title scope',
      );
      expect(catalog().entry.query.search, '夏日祭');
      expect(catalog().data.total, 1);
      await capture('presentation-return');
      await tap(find.text('清除'));
      await until(
        () => !catalog().data.loading && catalog().data.total == 4,
        'full library',
      );
      await tap(find.byTooltip('图包排序'));
      await tap(find.text('最近加入'));
      await until(
        () =>
            !catalog().data.loading &&
            catalog().entry.query.sort == PackSort.newest,
        'newest ordering',
      );
      final newest = await repo.loadPacks(PackQuery(sort: PackSort.newest));
      final newestIds = newest.items.map((p) => p.id).toList();
      expect(catalog().data.items.map((p) => p.id).toList(), newestIds);
      await capture('presentation-newest');
      await tap(find.byKey(Key('pack-tile-${newestIds.first}')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().length == 1 &&
            reader().session.opened &&
            !reader().session.busy,
        'complete newest reader',
      );
      expect(reader().session.range!.candidateCount, 4);
      final newestRange = reader().session.range!.id;
      await tap(find.byTooltip('图包更多'));
      await tap(find.text('本次图包范围'));
      await until(
        () =>
            reader().session.queuePage != null &&
            !reader().session.loadingQueue,
        'queue',
      );
      final queueIds = reader().session.queuePage!.entries
          .map((p) => p.pack.id)
          .toList();
      expect(queueIds, newestIds);
      await capture('presentation-queue');
      await tap(find.byTooltip('关闭面板'));
      await tap(find.byTooltip('返回来源'));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isEmpty &&
            !catalog().data.loading,
        'newest return',
      );
      expect(catalog().entry.query.sort, PackSort.newest);
      expect(catalog().data.items.map((p) => p.id).toList(), newestIds);
      await capture('presentation-back');
      await tap(find.byKey(const Key('nav-recent')));
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () =>
            catalog().initialized &&
            !catalog().data.loading &&
            catalog().data.total > 0,
        'recent',
      );
      expect(
        catalog().data.items.every(
          (p) => p.title != null && p.author == '示例作者',
        ),
        isTrue,
      );
      await capture('presentation-recent');
      debugPrint(
        'PACK_PRESENTATION_VERIFIED:${jsonEncode({'title_ids': expectedIds, 'titles': all.items.map((p) => p.displayTitle).toList(), 'raw_names': all.items.map((p) => p.name).toList(), 'authors': all.items.map((p) => p.author).toList(), 'newest_ids': newestIds, 'queue_ids': queueIds, 'filtered_range': filteredRange, 'newest_range': newestRange, 'before_read': before, 'recent_total': catalog().data.total})}',
      );
      debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
    },
  );
}
