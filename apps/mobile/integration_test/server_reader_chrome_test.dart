import 'dart:convert';

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
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real reading canvas, tools, saved strip and source return', (
    t,
  ) async {
    final previousError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('READER_CHROME_ERROR:$details');
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
    final catalog = await repo.loadPacks(PackQuery());
    final summer = catalog.items.singleWhere((p) => p.name.contains('034'));
    final expectedIds = catalog.items.map((p) => p.id).toList();
    Future<Map<String, dynamic>> saved() async => Map<String, dynamic>.from(
      (await repo.api.json('GET', '/api/v1/packs/${summer.id}'))['progress']
          as Map,
    );
    final initial = await saved();
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: preferences,
        initializeRepository: false,
      ),
    );
    PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
    PackCatalogPageState library() => t.state(find.byType(PackCatalogPage));
    Future<void> until(bool Function() done, String why) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Reader chrome timeout: $why');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().length == 1, 'one target $target');
      await t.ensureVisible(target);
      await t.pumpAndSettle(const Duration(milliseconds: 100));
      await until(
        () => target.hitTestable().evaluate().length == 1,
        'hit $target',
      );
      await t.tap(target);
      await t.pumpAndSettle(const Duration(milliseconds: 100));
    }

    Future<void> more(String text) async {
      await tap(find.byTooltip('图包更多'));
      await tap(find.text(text));
    }

    Future<void> capture(String name) async {
      await t.pumpAndSettle(const Duration(milliseconds: 100));
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
      'type switch',
    );
    await tap(find.byKey(const Key('kind-pack')));
    await until(
      () =>
          library().initialized &&
          !library().data.loading &&
          !library().continuationLoading,
      'library',
    );
    final target = find.byKey(Key('pack-tile-${summer.id}'));
    final catalogScroll = find
        .descendant(
          of: find.byType(PackCatalogPage),
          matching: find.byType(Scrollable),
        )
        .last;
    await t.scrollUntilVisible(target, 160, scrollable: catalogScroll);
    await tap(target);
    await until(
      () =>
          find.byType(PackReaderPage).evaluate().length == 1 &&
          reader().session.opened &&
          !reader().session.busy,
      'actual saved image',
    );
    expect(reader().session.index, 2);
    final origin = reader().widget.returnContext!;
    final range = reader().session.range!;
    expect(range.candidateCount, 4);
    final rangeReader = repo.createPackReader();
    addTearDown(rangeReader.dispose);
    final queue = await rangeReader.queue(range.id, offset: 0, limit: 40);
    expect(queue.entries.map((e) => e.pack.id).toList(), expectedIds);
    final window = MediaQuery.sizeOf(t.element(find.byType(PackReaderPage)));
    final compact = window.width > window.height && window.height <= 500;
    if (compact) {
      final canvas = t.getRect(find.byKey(const Key('reader-canvas')));
      final media = MediaQuery.of(t.element(find.byType(PackReaderPage)));
      expect(
        canvas.height,
        closeTo(window.height - media.padding.vertical, .1),
      );
      expect(find.byKey(const Key('reader-tools')), findsNothing);
      expect(find.byKey(const Key('reader-scope')), findsNothing);
    }
    await capture('reader-paged');
    if (compact) {
      await more('页码总览');
    } else {
      await tap(find.text('总览'));
    }
    await until(
      () =>
          find.byKey(const Key('reader-overview-page-3')).evaluate().length ==
          1,
      'overview loaded',
    );
    await until(
      () => [0, 1, 2].every(
        (index) => find
            .descendant(
              of: find.byKey(Key('reader-overview-page-$index')),
              matching: find.byType(RawImage),
            )
            .evaluate()
            .any((e) => (e.widget as RawImage).image != null),
      ),
      'visible overview thumbnail frames',
    );
    await capture('reader-overview');
    await tap(find.byKey(const Key('reader-overview-page-3')));
    debugPrint(
      'READER_CHROME_JUMP:${jsonEncode({'index': reader().session.index, 'busy': reader().session.busy, 'pending': reader().session.hasPending, 'sheet': find.byKey(const Key('reader-overview-sheet')).evaluate().length})}',
    );
    await until(
      () =>
          reader().session.index == 3 &&
          !reader().session.busy &&
          find.byKey(const Key('reader-overview-sheet')).evaluate().isEmpty,
      'overview fourth page',
    );
    expect(await reader().session.flush(), isTrue);
    await capture('reader-jump');
    await tap(find.byTooltip('阅读设置'));
    await capture('reader-settings');
    await tap(find.widgetWithText(ChoiceChip, '纵向拼接'));
    await until(
      () =>
          reader().session.preferences.mode == ReaderMode.vertical &&
          !reader().session.busy,
      'saved vertical preference',
    );
    await tap(find.text('继续阅读'));
    await until(
      () =>
          find.byKey(const Key('reader-vertical')).evaluate().length == 1 &&
          reader().session.index == 3,
      'same page in strip',
    );
    await capture('reader-vertical');
    await t.drag(
      find.byKey(const Key('reader-vertical')),
      const Offset(0, -80),
    );
    await t.pumpAndSettle();
    await until(
      () => reader().session.index == 3 && reader().session.offsetRatio > .03,
      'partly read current page',
    );
    expect(await reader().session.flush(), isTrue);
    final partial = await saved();
    await capture('reader-strip-scroll');
    final pageId = reader().session.currentPage!.id,
        ratio = reader().session.offsetRatio;
    if (compact) {
      await more('沉浸阅读');
    } else {
      await tap(find.text('沉浸'));
    }
    await until(() => !reader().controls, 'immersive');
    expect(find.byKey(const Key('reader-header')), findsNothing);
    expect(find.byKey(const Key('reader-controls')), findsNothing);
    expect(reader().session.currentPage!.id, pageId);
    expect(reader().session.offsetRatio, closeTo(ratio, .02));
    await capture('reader-immersive');
    await t.tapAt(t.getCenter(find.byKey(const Key('reader-canvas'))));
    await until(() => reader().controls, 'restore tools');
    await t.pumpAndSettle();
    expect(reader().session.currentPage!.id, pageId);
    expect(reader().session.offsetRatio, closeTo(ratio, .02));
    await capture('reader-restored');
    if (compact) {
      await more('本次图包范围');
    } else {
      await tap(find.byKey(const Key('reader-scope')));
    }
    await until(
      () =>
          reader().session.queuePage?.entries.length == 4 &&
          !reader().session.loadingQueue,
      'full range',
    );
    final afterPanels = await saved();
    expect(
      afterPanels,
      partial,
      reason: 'Tool and read-only range inspection do not change progress',
    );
    await capture('reader-range');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await more('快速整理当前范围');
    await until(() => reader().quick, 'quick mode');
    expect(find.byKey(const Key('reader-trash-pack')), findsOneWidget);
    await capture('reader-quick');
    await tap(find.text('完成'));
    await until(() => !reader().quick, 'exit explicit mode');
    expect(reader().session.currentPage!.id, pageId);
    await capture('reader-quick-exit');
    final finalPosition = await saved();
    expect(finalPosition, partial);
    await tap(find.byTooltip('返回来源'));
    await until(
      () =>
          find.byType(PackReaderPage).evaluate().isEmpty &&
          !library().data.loading &&
          !library().continuationLoading,
      'source return',
    );
    expect(library().data.total, 4);
    expect(library().entry.query.source, BrowseSource.library);
    expect(library().entry.query.count, 0);
    final restoredIndex = library().data.items.indexWhere(
      (p) => p.id == origin.scrollAnchor,
    );
    expect(restoredIndex, greaterThanOrEqualTo(0));
    final expectedOffset =
        (origin.scrollOffset == 0 && origin.scrollIndex == 0
                ? 0.0
                : library().listHeader +
                      restoredIndex ~/ library().columns * library().stride +
                      origin.scrollInset)
            .clamp(0.0, library().scroll.position.maxScrollExtent);
    expect(library().scroll.offset, closeTo(expectedOffset, 1));
    final returnedOffset = library().scroll.offset;
    await capture('reader-return');
    await t.scrollUntilVisible(target, 160, scrollable: catalogScroll);
    await tap(find.byKey(Key('pack-tile-${summer.id}')));
    await until(
      () =>
          find.byType(PackReaderPage).evaluate().length == 1 &&
          reader().session.opened &&
          !reader().session.busy,
      'real reopened saved strip',
    );
    expect(reader().session.preferences.mode, ReaderMode.vertical);
    expect(reader().session.currentPage!.id, pageId);
    expect(reader().session.offsetRatio, closeTo(ratio, .02));
    await capture('reader-reopen');
    debugPrint(
      'READER_CHROME_VERIFIED:${jsonEncode({'pack': summer.id, 'range': range.id, 'candidate_count': range.candidateCount, 'expected_ids': expectedIds, 'seed_progress': initial, 'partial': partial, 'after_panels': afterPanels, 'before_return': finalPosition, 'final_progress': await saved(), 'page_id': pageId, 'ratio': ratio, 'compact': compact, 'return_anchor': origin.scrollAnchor, 'expected_return_offset': expectedOffset, 'return_offset': returnedOffset})}',
    );
    debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
    expect(t.takeException(), isNull);
  });
}
