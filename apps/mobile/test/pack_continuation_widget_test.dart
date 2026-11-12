import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/main.dart';

import 'media_workspace_widget_test.dart' show frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_return_widget_test.dart' show DeepPacks;

class ContinuationLibrary extends DeepPacks {
  int summaryReads = 0, readers = 0;
  String latest = 'p58';
  bool failSummary = false, unknownPage = false;
  String failureMessage = '续读网络暂不可用';
  Completer<LibraryPack?>? gate;
  Object identity = Object();
  @override
  Object get connectionIdentity => identity;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    'image_packs',
    'pack_tags',
    'pack_reading_sessions',
  ]);
  LibraryPack get summary => LibraryPack(
    id: latest,
    rootId: 'pack-root',
    path: '/packs/$latest',
    name: '包${latest.substring(1).padLeft(3, '0')}',
    pageCount: 3,
    readableCount: 3,
    contentVersion: 1,
    status: 'available',
    createdAt: 0,
    cover: const MediaSource('assets/media/flower-portrait.jpg'),
    progress: PackProgress(
      pageId: unknownPage ? null : '$latest-1',
      pageIndex: unknownPage ? null : 1,
      offsetRatio: .2,
      completed: false,
      revision: 4,
      updatedAt: 123,
    ),
  );
  @override
  Future<LibraryPack?> loadPackContinuation() async {
    summaryReads++;
    if (failSummary) throw LibraryFailure(failureMessage);
    if (gate != null) return gate!.future;
    return summary;
  }

  @override
  PackReader createPackReader() {
    readers++;
    throw StateError('Reading must require an explicit action');
  }
}

void main() {
  late ContinuationLibrary repo;
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = ContinuationLibrary();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<PackCatalogPageState> start(WidgetTester t) async {
    await repo.initialize();
    await t.pumpWidget(ShikaApp(repository: repo));
    await frames(t);
    await t.tap(find.byKey(const Key('kind-pack')));
    await frames(t);
    return t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
  }

  Future<void> choose(WidgetTester t) async {
    final cancel = find.byKey(const Key('catalog-selection-cancel'));
    await t.tap(
      cancel.evaluate().isNotEmpty
          ? cancel
          : find.byKey(const Key('catalog-select')),
    );
    await frames(t);
  }

  testWidgets(
    'latest summary is outside first page, read-only, hidden in scopes and selection',
    (t) async {
      final page = await start(t);
      expect(find.byKey(const Key('pack-continuation')), findsOneWidget);
      expect(find.text('第 2 / 3 张'), findsOneWidget);
      expect(page.data.items.map((p) => p.id), isNot(contains('p58')));
      expect(page.data.total, 73);
      expect(repo.readers, 0);
      final read = repo.summaryReads;
      await t.enterText(find.byKey(const Key('pack-search')), '包001');
      await frames(t);
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      expect(page.data.total, 1);
      expect(repo.summaryReads, read);
      await t.enterText(find.byKey(const Key('pack-search')), '');
      await frames(t);
      expect(find.byKey(const Key('pack-continuation')), findsOneWidget);
      await choose(t);
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      repo.latest = 'p2';
      await choose(t);
      expect(
        t
            .state<PackCatalogPageState>(find.byType(PackCatalogPage))
            .continuation!
            .id,
        'p2',
      );
      expect(repo.readers, 0);
    },
  );

  testWidgets('selecting catalog contents releases search focus', (t) async {
    final page = await start(t);
    await t.showKeyboard(find.byKey(const Key('pack-search')));
    expect(t.testTextInput.isVisible, isTrue);
    await t.tap(find.byKey(const Key('catalog-select')));
    await frames(t);
    expect(t.testTextInput.isVisible, isFalse);
    expect(page.selecting, isTrue);
    expect(find.byKey(const Key('pack-continuation')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'summary failure retains catalog, retry is read-only, unknown page is not guessed',
    (t) async {
      repo.failSummary = true;
      final page = await start(t);
      expect(find.text('续读位置暂不可用'), findsOneWidget);
      expect(page.data.total, 73);
      expect(find.byKey(const Key('pack-tile-p0')), findsOneWidget);
      repo.failSummary = false;
      repo.unknownPage = true;
      await t.tap(find.text('重试'));
      await frames(t);
      expect(find.text('续读位置待确认 · 3 张'), findsOneWidget);
      expect(find.text('第 1 / 3 张'), findsNothing);
      expect(repo.readers, 0);
    },
  );

  testWidgets(
    'late unfiltered summary cannot replace a newer search or connection',
    (t) async {
      final first = Completer<LibraryPack?>();
      repo.gate = first;
      final page = await start(t);
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      final old = repo.summary;
      await t.enterText(find.byKey(const Key('pack-search')), '包001');
      await frames(t);
      first.complete(old);
      await frames(t);
      expect(page.entry.query.search, '包001');
      expect(page.data.total, 1);
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      final stale = Completer<LibraryPack?>();
      repo.gate = stale;
      await t.enterText(find.byKey(const Key('pack-search')), '');
      await frames(t);
      repo.gate = null;
      repo.latest = 'p2';
      repo.identity = Object();
      repo.notifyListeners();
      await frames(t);
      stale.complete(old);
      await frames(t);
      expect(find.byKey(const Key('pack-continuation')), findsNothing);
      await t.tap(find.byKey(const Key('kind-pack')));
      await frames(t);
      expect(
        t
            .state<PackCatalogPageState>(find.byType(PackCatalogPage))
            .continuation!
            .id,
        'p2',
      );
      expect(repo.readers, 0);
    },
  );

  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.6),
  ]) {
    testWidgets(
      'continuation geometry and deep anchor survive multi-select ${sample.$1}/${sample.$2}',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = sample.$1;
        t.platformDispatcher.textScaleFactorTestValue = sample.$2;
        addTearDown(() {
          t.view.resetDevicePixelRatio();
          t.view.resetPhysicalSize();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final page = await start(t);
        expect(find.byKey(const Key('pack-continuation')), findsOneWidget);
        page.scroll.jumpTo(800);
        await frames(t);
        final before = page.position().context;
        page.toggleSelection();
        await frames(t);
        expect(page.position().context.scrollAnchor, before.scrollAnchor);
        expect(
          (page.position().context.scrollInset - before.scrollInset).abs(),
          lessThan(2),
        );
        page.toggleSelection();
        await frames(t);
        expect(page.position().context.scrollAnchor, before.scrollAnchor);
        expect(
          (page.position().context.scrollInset - before.scrollInset).abs(),
          lessThan(2),
        );
        expect(t.takeException(), isNull);
        page.scroll.jumpTo(0);
        repo.failSummary = true;
        repo.failureMessage = '连接暂时中断，请检查服务器与网络连接后重试。' * 12;
        await page.load(restore: true);
        await frames(t);
        expect(find.text('重试').hitTestable(), findsOneWidget);
        expect(page.data.total, 73);
        expect(t.takeException(), isNull);
      },
    );
  }
}
