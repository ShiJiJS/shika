import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class CountedWorkspace extends WorkspaceLibrary {
  CountedWorkspace() {
    catalogCounts.value = const MediaCatalogCounts(270, 730);
  }
  bool countsSupported = true;
  int retries = 0;
  MediaCatalogCounts? next = const MediaCatalogCounts(0, 0);
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    if (countsSupported) 'media_catalog_counts',
  ]);
  @override
  Future<void> refreshCatalogCounts() async {
    retries++;
    catalogCounts.value = next;
  }
}

void main() {
  late CountedWorkspace repo;
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = CountedWorkspace();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> start(WidgetTester t) async {
    await repo.initialize();
    await t.pumpWidget(
      ShikaApp(repository: repo, initializeRepository: false),
    );
    await frames(t);
  }

  String total(WidgetTester t, String kind) =>
      t.widget<Text>(find.byKey(Key('catalog-count-$kind'))).data!;

  testWidgets(
    'both library totals survive searches, filters and type switching',
    (t) async {
      await start(t);
      expect(total(t, 'video'), '270');
      expect(total(t, 'pack'), '730');
      await t.tap(find.byKey(const Key('kind-pack')));
      await frames(t);
      await t.enterText(find.byKey(const Key('pack-search')), '春日');
      await frames(t);
      expect(
        t.state<PackCatalogPageState>(find.byType(PackCatalogPage)).data.total,
        1,
      );
      expect(total(t, 'pack'), '730');
      await t.tap(find.byKey(const Key('kind-video')));
      await frames(t);
      expect(total(t, 'video'), '270');
      expect(total(t, 'pack'), '730');
      expect(repo.retries, 0);
    },
  );

  testWidgets(
    'unknown is not zero, a type click retries; authoritative zero is shown',
    (t) async {
      await start(t);
      repo.catalogCounts.value = null;
      await frames(t);
      expect(total(t, 'video'), '—');
      expect(total(t, 'pack'), '—');
      await t.tap(find.byKey(const Key('catalog-count-pack')));
      await frames(t);
      expect(repo.retries, 1);
      expect(total(t, 'video'), '0');
      expect(total(t, 'pack'), '0');
      expect(find.byKey(const Key('pack-search')), findsOneWidget);
    },
  );

  testWidgets(
    'only library shows totals; returning sees a fresh pair and preserves search',
    (t) async {
      await start(t);
      await t.tap(find.byKey(const Key('kind-pack')));
      await frames(t);
      await t.enterText(find.byKey(const Key('pack-search')), '春日');
      await frames(t);
      for (final destination in ['tags', 'recent', 'settings']) {
        await t.tap(find.byKey(Key('nav-$destination')));
        await frames(t);
        expect(find.byKey(const Key('catalog-count-video')), findsNothing);
        expect(find.byKey(const Key('catalog-count-pack')), findsNothing);
      }
      repo.catalogCounts.value = const MediaCatalogCounts(269, 729);
      await t.tap(find.byKey(const Key('nav-library')));
      await frames(t);
      expect(total(t, 'pack'), '729');
      expect(total(t, 'video'), '269');
      expect(
        t
            .state<PackCatalogPageState>(find.byType(PackCatalogPage))
            .entry
            .query
            .search,
        '春日',
      );
    },
  );

  testWidgets('zero-result scope can be cleared after leaving and returning', (
    t,
  ) async {
    await start(t);
    await t.tap(find.byKey(const Key('kind-pack')));
    await frames(t);
    await t.enterText(find.byKey(const Key('pack-search')), 'no-pack-matches');
    await frames(t);
    expect(
      t.state<PackCatalogPageState>(find.byType(PackCatalogPage)).data.total,
      0,
    );
    for (final destination in ['tags', 'recent', 'library']) {
      await t.tap(find.byKey(Key('nav-$destination')));
      await frames(t);
    }
    await t.tap(find.byTooltip('清除搜索'));
    await frames(t);
    final page = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
    expect(page.data.total, 2);
    expect(page.entry.query.search, '');
    expect(total(t, 'pack'), '730');
    expect(t.takeException(), isNull);
  });

  testWidgets('older servers hide unknown badges and keep type actions', (
    t,
  ) async {
    repo.countsSupported = false;
    await start(t);
    expect(find.byKey(const Key('catalog-count-video')), findsNothing);
    expect(find.byKey(const Key('catalog-count-pack')), findsNothing);
    await t.tap(find.byKey(const Key('kind-pack')));
    await frames(t);
    expect(find.byKey(const Key('pack-search')), findsOneWidget);
  });

  testWidgets(
    'large exact totals remain reachable at double text scale without overflow',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 740);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        t.view.resetDevicePixelRatio();
        t.view.resetPhysicalSize();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      });
      repo.catalogCounts.value = const MediaCatalogCounts(999999999, 999999999);
      await start(t);
      final pack = find.byKey(const Key('kind-pack'));
      await Scrollable.ensureVisible(t.element(pack));
      await frames(t);
      expect(pack.hitTestable(), findsOneWidget);
      await t.tap(pack);
      await frames(t);
      expect(total(t, 'pack'), '999999999');
      expect(find.byKey(const Key('pack-search')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
