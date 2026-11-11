import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/library/video_catalog_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';

import 'native_workspace_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real video and pack card geometry preserves readable captions and scope', (
    t,
  ) async {
    final previousError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('CATALOG_CARDS_ERROR:$details');
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
      'client-ui-owned-only',
    );
    final initial = repo.catalogCounts.value;
    expect(initial, const MediaCatalogCounts(2, 4));
    final all = await repo.loadPacks(PackQuery());
    final pack = all.items.singleWhere((p) => p.name.contains('034'));
    Future<Map<String, dynamic>> progress() async => Map<String, dynamic>.from(
      (await repo.api.json('GET', '/api/v1/packs/${pack.id}'))['progress']
          as Map,
    );
    final before = await progress();
    const expectedColumns = int.fromEnvironment(
      'GRID_COLUMNS',
      defaultValue: 2,
    );
    await t.pumpWidget(
      ShikaApp(
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
          fail('Catalog card timeout: $reason');
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
    VideoCatalogPageState videoCatalog() =>
        t.state(find.byType(VideoCatalogPage));
    Finder gridScroll(String kind) => find.descendant(
      of: find.byKey(Key('$kind-grid')),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    Future<void> tagsVisible(String kind, String id) async {
      final target = find.byKey(Key('$kind-tag-names-$id'));
      await t.scrollUntilVisible(target, 120, scrollable: gridScroll(kind));
      await t.pumpAndSettle();
      final text = t.widget<Text>(target);
      expect(text.style!.fontSize, 12);
      expect(text.style!.height, 1.6);
    }

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
      final media = MediaQuery.of(
        t.element(find.byKey(const Key('app-shell'))),
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
        'WORKSPACE_METRICS:${jsonEncode({
          'state': name,
          'size': [media.size.width, media.size.height],
          'dpr': media.devicePixelRatio,
          'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
          'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
          'textScale': media.textScaler.scale(14) / 14,
          'keys': keys,
          'texts': texts,
          'grids': {
            if (find.byType(VideoCatalogPage).evaluate().length == 1) 'video': {'columns': videoCatalog().columns, 'stride': videoCatalog().stride},
            if (find.byType(PackCatalogPage).evaluate().length == 1) 'pack': {'columns': catalog().columns, 'stride': catalog().stride},
          },
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
      () =>
          find.byKey(const Key('catalog-count-video')).evaluate().length == 1 &&
          videoCatalog().initialized &&
          !videoCatalog().data.loading,
      'video catalog',
    );
    final videos = videoCatalog().data.items;
    expect(videos.length, 2);
    expect(videoCatalog().columns, expectedColumns);
    await decodedCovers();
    shown(2, 4);
    await capture('cards-video');
    await tagsVisible('video', videos.last.id);
    await capture('cards-video-meta');
    await tap(find.byKey(const Key('kind-pack')));
    await until(
      () => catalog().initialized && !catalog().data.loading,
      'pack catalog',
    );
    expect(catalog().data.total, 4);
    expect(catalog().columns, expectedColumns);
    await until(
      () =>
          find
              .byType(RawImage)
              .evaluate()
              .where((e) => (e.widget as RawImage).image != null)
              .length >=
          4,
      'four decoded pack covers',
    );
    final identities = catalog().data.items.map((p) => p.id).toList();
    expect(await progress(), before);
    await capture('cards-packs');
    await tagsVisible('pack', identities.last);
    await capture('cards-pack-meta');
    await t.enterText(find.byKey(const Key('pack-search')), '夏日祭');
    await until(
      () => !catalog().data.loading && catalog().data.total == 1,
      'one filtered pack',
    );
    expect(catalog().data.items.single.id, pack.id);
    FocusManager.instance.primaryFocus?.unfocus();
    await tagsVisible('pack', pack.id);
    shown(2, 4);
    await capture('cards-filter');
    await t.scrollUntilVisible(
      find.text('清除'),
      -120,
      scrollable: gridScroll('pack'),
    );
    await tap(find.text('清除'));
    await until(
      () => !catalog().data.loading && catalog().data.total == 4,
      'clear scope',
    );
    expect(catalog().columns, expectedColumns);
    expect(catalog().data.items.map((p) => p.id).toList(), identities);
    expect(await progress(), before);
    await capture('cards-return');
    final recent = await repo.api.json(
      'GET',
      '/api/v1/recent',
      query: {'kind': 'pack'},
    );
    expect(recent['total'], 0);
    debugPrint(
      'CATALOG_CARDS_VERIFIED:${jsonEncode({'expected_columns': expectedColumns, 'video_ids': videos.map((v) => v.id).toList(), 'pack_ids': identities, 'before_progress': before, 'after_progress': await progress(), 'recent': recent['total']})}',
    );
    debugPrint('WORKSPACE_VERIFIED');
  });
}
