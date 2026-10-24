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
  testWidgets('LF5 native swipes, zoom/back, immersion and per-pack preferences', (
    t,
  ) async {
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
      MediaRoot('', '阅读操作图包', seed['path'], kind: MediaKind.pack),
    );
    await repo.refresh();
    final catalog = await repo.loadPacks(PackQuery());
    final first = catalog.items.first, second = catalog.items[1];
    expect(catalog.total, 27);
    await t.pumpWidget(VideoViewerApp(repository: repo));
    PackReaderPageState state() =>
        t.state<PackReaderPageState>(find.byType(PackReaderPage));
    Future<void> until(bool Function() done, String why) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          debugPrint('CONTROLS_TIMEOUT $why');
          if (find.byType(PackReaderPage).evaluate().isNotEmpty) {
            debugPrint(
              'CONTROLS_STATE index=${state().session.index} busy=${state().session.busy} pending=${state().session.hasPending} prefs=${state().session.preferences.values} error=${state().session.error}',
            );
            debugPrint(
              'CONTROLS_SCALES ${t.widgetList<InteractiveViewer>(find.byType(InteractiveViewer)).map((v) => v.transformationController!.value.getMaxScaleOnAxis()).toList()}',
            );
          }
          await fixture('/__fixture/checkpoint/error');
          fail('Timed out: $why');
        }
        await t.pump(const Duration(milliseconds: 80));
      }
      await t.pump(const Duration(milliseconds: 200));
      expect(t.takeException(), isNull);
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
      await fixture('/__fixture/checkpoint/controls-$name');
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> nativeBack(bool Function() done, String why) async {
      // The host sends an actual Android KEYCODE_BACK, rather than calling leave.
      debugPrint('VV_E2E_DEVICE_BACK');
      await until(done, why);
    }

    final horizontal = find.byKey(const Key('reader-horizontal'));
    Future<void> swipe(double dx, int page) async {
      await t.drag(horizontal, Offset(dx, 0));
      await until(
        () => state().session.index == page && state().session.unsaved,
        'swipe displayed page $page',
      );
      expect(await state().session.flush(), isTrue);
      final stored = await repo.api.json('GET', '/api/v1/packs/${first.id}');
      expect(
        (stored['progress'] as Map)['page_id'],
        state().session.currentPage!.id,
      );
    }

    await until(() => find.text('图包').evaluate().isNotEmpty, 'type switch');
    await tap(find.text('图包'));
    final tile = find.byKey(Key('pack-tile-${first.id}'));
    Future<void> openFirst() async {
      await until(() => tile.evaluate().isNotEmpty, 'first pack card');
      await until(
        () => t
            .widgetList<RawImage>(
              find.descendant(of: tile, matching: find.byType(RawImage)),
            )
            .any((image) => image.image != null),
        'decoded cover',
      );
      await tap(tile);
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            state().session.opened &&
            !state().session.busy,
        'actual current image opened',
      );
    }

    await openFirst();
    expect(state().session.preferences.direction, ReaderDirection.ltr);
    expect(state().session.preferences.gap, isFalse);
    expect(state().session.index, 0);
    final hold = await t.startGesture(t.getCenter(horizontal));
    await hold.moveBy(const Offset(-100, 0));
    await t.pump(const Duration(milliseconds: 30));
    final pager = t.widget<PageView>(horizontal).controller!;
    expect(pager.page, greaterThan(.05));
    expect(pager.page, lessThan(.5));
    await hold.up();
    await until(
      () => (pager.page ?? 1).abs() < .001,
      'partial swipe snaps back',
    );
    expect(state().session.index, 0);
    await swipe(-260, 1);
    await swipe(260, 0);
    await swipe(-260, 1);
    final pageId = state().session.currentPage!.id;

    await tap(find.byTooltip('阅读设置'));
    await tap(find.byType(DropdownButtonFormField<ReaderDirection>));
    await tap(find.text('从右向左').last);
    await until(
      () =>
          state().session.preferences.direction == ReaderDirection.rtl &&
          !state().session.busy,
      'RTL preference acknowledged',
    );
    await tap(find.text('继续阅读'));
    expect(state().session.index, 1);
    expect(t.widget<PageView>(horizontal).reverse, isTrue);
    await swipe(-260, 0);
    await swipe(260, 1);
    await shot('rtl');

    final center = t.getCenter(horizontal);
    final left = await t.startGesture(center - const Offset(30, 0));
    final right = await t.startGesture(center + const Offset(30, 0));
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 4; i++) {
      await left.moveTo(center - Offset(30 + i * 15, 0));
      await right.moveTo(center + Offset(30 + i * 15, 0));
      await t.pump(const Duration(milliseconds: 30));
    }
    await until(() => state().zoomed, 'native two-finger pinch zoom');
    await left.up();
    await right.up();
    expect(state().session.index, 1);
    await t.tapAt(center);
    await t.pump(const Duration(milliseconds: 80));
    await t.tapAt(center);
    await until(() => !state().zoomed, 'double tap resets pinch zoom');
    await t.tapAt(center);
    await t.pump(const Duration(milliseconds: 80));
    await t.tapAt(center);
    await until(() => state().zoomed, 'double tap zoom');
    expect(state().controls, isTrue);
    await t.drag(horizontal, const Offset(140, 0));
    await t.pump(const Duration(milliseconds: 400));
    expect(state().session.index, 1, reason: 'zoom pan must not flip the page');
    final viewers = t.widgetList<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      viewers.any(
        (v) => v.transformationController!.value.getMaxScaleOnAxis() > 1.5,
      ),
      isTrue,
    );
    await shot('zoom');
    await nativeBack(() => !state().zoomed, 'native back resets zoom first');
    expect(find.byType(PackReaderPage), findsOneWidget);
    expect(state().session.currentPage!.id, pageId);
    expect(state().controls, isTrue);
    expect(
      t.widget<PageView>(horizontal).physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
    );

    await tap(find.text('沉浸'));
    await until(() => !state().controls, 'immersive controls hidden');
    expect(find.byTooltip('返回来源'), findsNothing);
    await shot('immersive');
    await nativeBack(() => state().controls, 'native back reveals tools first');
    expect(find.byType(PackReaderPage), findsOneWidget);
    expect(state().session.currentPage!.id, pageId);

    await tap(find.byTooltip('阅读设置'));
    await tap(find.byType(DropdownButtonFormField<ReaderFit>));
    await tap(find.text('铺满宽度').last);
    await until(
      () =>
          state().session.preferences.fit == ReaderFit.width &&
          !state().session.busy,
      'width preference acknowledged',
    );
    await tap(find.text('继续阅读'));
    expect(state().session.currentPage!.id, pageId);
    await t.drag(horizontal, const Offset(0, -80));
    await until(
      () => state().session.offsetRatio > .03,
      'width fit scroll position',
    );
    expect(state().session.index, 1);
    final ratio = state().session.offsetRatio;
    expect(await state().session.flush(), isTrue);
    await shot('width');
    await nativeBack(
      () => find.byType(PackReaderPage).evaluate().isEmpty,
      'native back returns to library after save',
    );
    final saved = await repo.api.json('GET', '/api/v1/packs/${first.id}');
    expect((saved['progress'] as Map)['page_id'], pageId);
    expect((saved['progress'] as Map)['offset_ratio'], closeTo(ratio, .02));
    await openFirst();
    expect(state().session.index, 1);
    expect(state().session.preferences.direction, ReaderDirection.rtl);
    expect(state().session.preferences.fit, ReaderFit.width);
    expect(state().session.offsetRatio, closeTo(ratio, .02));
    await shot('reopen');

    await tap(find.byTooltip('阅读设置'));
    await tap(find.text('纵向拼接'));
    await until(
      () =>
          state().session.preferences.mode == ReaderMode.vertical &&
          !state().session.busy,
      'vertical preference saved',
    );
    await tap(find.byType(SwitchListTile));
    await until(
      () => state().session.preferences.gap && !state().session.busy,
      'gap preference saved',
    );
    await tap(find.text('继续阅读'));
    await until(
      () => find.byKey(const Key('reader-vertical')).evaluate().isNotEmpty,
      'vertical positioned',
    );
    expect(state().session.currentPage!.id, pageId);
    expect(state().session.offsetRatio, closeTo(ratio, .02));
    expect(await state().session.flush(), isTrue);
    await shot('vertical');
    final identity = state().session.range!.id;
    await tap(find.text('下一包').last);
    await until(
      () =>
          state().session.range?.pack?.id == second.id &&
          state().session.opened &&
          !state().session.busy,
      'next pack actual image',
    );
    expect(state().session.range!.id, identity);
    expect(state().session.range!.candidateCount, 27);
    expect(state().session.preferences.mode, ReaderMode.horizontal);
    expect(state().session.preferences.direction, ReaderDirection.ltr);
    expect(state().session.preferences.fit, ReaderFit.contain);
    expect(state().session.preferences.gap, isFalse);
    await shot('next');
    await nativeBack(
      () => find.byType(PackReaderPage).evaluate().isEmpty,
      'final native back returns library',
    );
    await shot('return');
    final recent = await repo.api.json(
      'GET',
      '/api/v1/recent',
      query: {'kind': 'pack'},
    );
    expect(recent['total'], 2);
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
    debugPrint(
      'READER_CONTROLS_RESULT ltr_swipes=3 rtl_swipes=2 partial_snap=true pinch=true native_back=4 zoom_pan_kept_page=true width_resume=true preferences_isolated=true',
    );
  });
}
