import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/features/packs/reader_images.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

void main() {
  late AssetReadingLibrary repo;
  late PackReaderPageState state;
  final strip = find.byKey(const Key('reader-vertical-gestures'));
  Future<void> settle(WidgetTester t, [bool Function()? ready]) async {
    for (var i = 0; i < 150; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      expect(t.takeException(), isNull);
      if (ready?.call() ?? i > 4) return;
    }
    fail('Reader did not reach its observable state');
  }

  Future<void> open(WidgetTester t, {int at = 235, int pages = 500}) async {
    repo = AssetReadingLibrary()..totalPages = pages;
    repo.pageDimensions = (i) => switch (i % 4) {
      0 => const Size(1200, 400),
      1 => const Size(400, 600),
      2 => const Size(400, 3000),
      _ => const Size(6000, 9000),
    };
    repo.marks['p0'] = ReaderMark('p0-$at', offsetRatio: .37);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: PackReaderPage(
          repository: repo,
          entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
          editTags: (_) async {},
        ),
      ),
    );
    state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
    await settle(t, () => state.session.opened && !state.session.busy);
    expect(await state.session.flush(), true);
  }

  ReaderImage image() => find
      .byType(ReaderImage)
      .evaluate()
      .map((e) => e.widget as ReaderImage)
      .firstWhere((w) => w.page.id == state.session.currentPage!.id);
  int getWrites() => repo.commands.whereType<WritePackProgress>().length;
  double zoom() => image().viewport.width / 390;

  Future<void> pinch(WidgetTester t, {bool keepOne = false}) async {
    final center = t.getCenter(strip);
    final left = await t.startGesture(center - const Offset(15, 0), pointer: 1);
    final right = await t.startGesture(
      center + const Offset(15, 0),
      pointer: 2,
    );
    for (var i = 1; i <= 6; i++) {
      await left.moveTo(center - Offset(15 + i * 25, 0));
      await right.moveTo(center + Offset(15 + i * 25, 0));
      await t.pump(const Duration(milliseconds: 30));
    }
    await left.up();
    if (keepOne) {
      for (var i = 0; i < 5; i++) {
        await right.moveBy(const Offset(-10, -55));
        await t.pump(const Duration(milliseconds: 40));
      }
    }
    await right.up();
    await settle(t);
  }

  Future<void> doubleTap(WidgetTester t) async {
    final center = t.getCenter(strip);
    await t.tapAt(center);
    await t.pump(const Duration(milliseconds: 70));
    await t.tapAt(center);
    await settle(t);
  }

  testWidgets(
    'pinch clamps at 4x, pans both axes, and Back resets before leaving',
    (t) async {
      await open(t);
      final mark = repo.marks['p0']!;
      final writes = getWrites();
      await pinch(t);
      expect(state.zoomed, true);
      expect(zoom(), closeTo(4, .001));
      expect(getWrites(), writes);
      expect(state.session.unsaved, false);
      expect(repo.marks['p0']!.pageId, mark.pageId);
      expect(repo.marks['p0']!.offsetRatio, mark.offsetRatio);
      final current = state.session.currentPage!.id;
      final transform = find.byKey(ValueKey('reader-strip-$current'));
      final initialX = t
          .widget<Transform>(transform)
          .transform
          .getTranslation()
          .x;
      await t.timedDrag(
        strip,
        const Offset(140, 0),
        const Duration(milliseconds: 500),
      );
      await settle(t);
      expect(
        t.widget<Transform>(transform).transform.getTranslation().x,
        greaterThan(initialX),
      );
      expect(
        getWrites(),
        writes,
        reason: 'horizontal pan must not save vertical progress',
      );
      await t.timedDrag(
        strip,
        const Offset(0, -220),
        const Duration(seconds: 1),
      );
      await settle(t);
      expect(state.session.unsaved || getWrites() > writes, true);
      expect(await state.session.flush(), true);
      final moved = repo.marks['p0']!;
      expect(moved.offsetRatio, isNot(mark.offsetRatio));
      final writesAfter = getWrites();
      await t.binding.handlePopRoute();
      await settle(t);
      expect(state.zoomed, false);
      expect(zoom(), closeTo(1, .001));
      expect(find.byType(PackReaderPage), findsOneWidget);
      expect(getWrites(), writesAfter);
      expect(repo.marks['p0']!.pageId, moved.pageId);
      expect(repo.marks['p0']!.offsetRatio, moved.offsetRatio);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: PackReaderPage(
            repository: repo,
            entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
            editTags: (_) async {},
          ),
        ),
      );
      state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
      await settle(t, () => state.session.opened && !state.session.busy);
      expect(state.session.currentPage!.id, moved.pageId);
      expect(state.session.offsetRatio, closeTo(moved.offsetRatio, .01));
      expect(state.zoomed, false);
    },
  );

  testWidgets(
    'double tap toggles 2x and fit without changing the saved position',
    (t) async {
      await open(t);
      final writes = getWrites();
      final ratio = state.session.offsetRatio;
      await doubleTap(t);
      expect(state.zoomed, true);
      expect(zoom(), closeTo(2, .001));
      expect(state.controls, true);
      await doubleTap(t);
      expect(state.zoomed, false);
      expect(zoom(), closeTo(1, .001));
      expect(state.session.index, 235);
      expect(state.session.offsetRatio, ratio);
      expect(getWrites(), writes);
    },
  );

  testWidgets(
    'a remaining finger keeps scrolling after pinch without another touch',
    (t) async {
      await open(t);
      final before = state.session.offsetRatio;
      await pinch(t, keepOne: true);
      expect(state.zoomed, true);
      expect(state.session.offsetRatio, isNot(before));
      expect(state.session.index, greaterThanOrEqualTo(235));
      expect(await state.session.flush(), true);
      expect(repo.marks['p0']!.offsetRatio, state.session.offsetRatio);
    },
  );

  testWidgets(
    'rotation retains visual page anchor while jump and mode changes reset zoom',
    (t) async {
      await open(t);
      await doubleTap(t);
      final writes = getWrites();
      final canvas = t.getRect(strip);
      final visible = find.byType(ReaderImage).evaluate().where((e) {
        final r = t.getRect(find.byWidget(e.widget));
        return r.top <= canvas.top + 1 && r.bottom > canvas.top + 1;
      }).single;
      final pageId = (visible.widget as ReaderImage).page.id;
      final rect = t.getRect(find.byWidget(visible.widget));
      final fraction = (canvas.top - rect.top) / rect.height;
      t.view.physicalSize = const Size(844, 390);
      await settle(t);
      expect(state.zoomed, false);
      final rotated = find.byWidgetPredicate(
        (w) => w is ReaderImage && w.page.id == pageId,
      );
      final after = t.getRect(rotated);
      final newCanvas = t.getRect(strip);
      expect(
        (newCanvas.top - after.top) / after.height,
        closeTo(fraction, .01),
      );
      expect(getWrites(), writes);
      t.view.physicalSize = const Size(390, 844);
      await settle(t);
      await doubleTap(t);
      expect(state.zoomed, true);
      state.jump(244);
      await settle(
        t,
        () =>
            state.session.currentPage?.id == 'p0-244' &&
            strip.evaluate().isNotEmpty,
      );
      await settle(t);
      expect(state.zoomed, false);
      expect(state.session.index, 244);
      expect(state.session.offsetRatio, 0);
      expect(image().viewport.width, 390);
      await doubleTap(t);
      expect(state.zoomed, true);
      await t.tap(find.byTooltip('阅读设置'));
      await t.pumpAndSettle();
      await settle(t);
      await t.tap(find.text('横向翻页').last);
      await settle(
        t,
        () =>
            state.session.preferences.mode == ReaderMode.horizontal &&
            !state.session.busy,
      );
      await t.tap(find.text('继续阅读'));
      await t.pumpAndSettle();
      await settle(t);
      expect(state.zoomed, false);
      expect(state.session.index, 244);
      expect(find.byKey(const Key('reader-horizontal')), findsOneWidget);
      await t.tap(find.byTooltip('阅读设置'));
      await t.pumpAndSettle();
      await settle(t);
      await t.tap(find.text('纵向拼接').last);
      await settle(
        t,
        () =>
            state.session.preferences.mode == ReaderMode.vertical &&
            !state.session.busy,
      );
      await t.tap(find.text('继续阅读'));
      await t.pumpAndSettle();
      await settle(t);
      expect(image().viewport.width, 390);
      expect(state.zoomed, false);
      expect(state.session.pages.length, lessThanOrEqualTo(120));
      expect(
        state.images.length,
        lessThanOrEqualTo(ReaderImages.maximumEntries),
      );
      expect(
        state.images.estimatedBytes,
        lessThanOrEqualTo(ReaderImages.maximumBytes),
      );
    },
  );

  testWidgets(
    'scaled scrolling extends and evicts a 500-page window with bounded image cache',
    (t) async {
      await open(t, at: 35);
      expect(repo.manifestRequests, [(offset: 0, limit: 40)]);
      await doubleTap(t);
      expect(repo.manifestRequests, [
        (offset: 0, limit: 40),
      ], reason: 'zoom alone must not fetch the rest of the pack');
      for (var i = 0; i < 5; i++) {
        await t.timedDrag(
          strip,
          const Offset(0, -60000),
          const Duration(seconds: 2),
        );
        await settle(t, () => !state.session.loadingPages);
        await settle(t);
        expect(state.session.pages.length, lessThanOrEqualTo(120));
        expect(state.images.length, lessThanOrEqualTo(6));
        expect(
          state.images.estimatedBytes,
          lessThanOrEqualTo(48 * 1024 * 1024),
        );
        expect(state.zoomed, true);
      }
      expect(state.session.index, greaterThan(120));
      expect(state.session.windowStart, greaterThan(0));
      expect(repo.manifestRequests.every((r) => r.limit == 40), true);
      expect(repo.manifestRequests.length, lessThan(13));
      expect(await state.session.flush(), true);
      expect(repo.marks['p0']!.pageId, state.session.currentPage!.id);
    },
  );
  testWidgets(
    'a moving single finger can become a pinch and shrink back to fit',
    (t) async {
      await open(t);
      final center = t.getCenter(strip);
      final left = await t.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      await left.moveBy(const Offset(0, -45));
      await t.pump(const Duration(milliseconds: 50));
      final right = await t.startGesture(
        center + const Offset(30, -45),
        pointer: 2,
      );
      for (var i = 1; i <= 5; i++) {
        await left.moveBy(const Offset(-25, 0));
        await right.moveBy(const Offset(25, 0));
        await t.pump(const Duration(milliseconds: 30));
      }
      await left.up();
      await right.up();
      await settle(t);
      expect(state.zoomed, true);
      expect(zoom(), greaterThan(2));
      expect(await state.session.flush(), true);
      final writes = getWrites();
      final ratio = state.session.offsetRatio;
      final a = await t.startGesture(center - const Offset(170, 0), pointer: 3);
      final b = await t.startGesture(center + const Offset(170, 0), pointer: 4);
      for (var i = 1; i <= 6; i++) {
        await a.moveTo(center - Offset(170 - i * 26, 0));
        await b.moveTo(center + Offset(170 - i * 26, 0));
        await t.pump(const Duration(milliseconds: 30));
      }
      await a.up();
      await b.up();
      await settle(t);
      expect(zoom(), closeTo(1, .001));
      expect(state.zoomed, false);
      expect(state.session.offsetRatio, ratio);
      expect(getWrites(), writes);
      await t.timedDrag(
        strip,
        const Offset(0, -100),
        const Duration(seconds: 1),
      );
      await settle(t);
      expect(state.session.offsetRatio, isNot(ratio));
    },
  );
  testWidgets(
    'resuming at a window edge loads neighbors without inventing new progress',
    (t) async {
      await open(t, at: 39);
      await settle(t, () => state.session.pages.containsKey(40));
      expect(repo.manifestRequests, [
        (offset: 0, limit: 40),
        (offset: 40, limit: 40),
      ]);
      expect(state.session.index, 39);
      expect(state.session.offsetRatio, .37);
      expect(repo.marks['p0']!.pageId, 'p0-39');
      expect(getWrites(), 0);
      await doubleTap(t);
      expect(state.zoomed, true);
      expect(repo.manifestRequests.length, 2);
      expect(getWrites(), 0);
    },
  );

  testWidgets(
    'zoom, reset and rotation on the last image cannot mark the pack read',
    (t) async {
      await open(t, at: 3, pages: 4);
      expect(repo.marks['p0']!.completed, false);
      final writes = getWrites();
      await pinch(t);
      expect(state.zoomed, true);
      await t.binding.handlePopRoute();
      await settle(t);
      t.view.physicalSize = const Size(844, 390);
      await settle(t);
      expect(await state.session.flush(), true);
      expect(state.session.currentPage!.id, 'p0-3');
      expect(repo.marks['p0']!.completed, false);
      expect(repo.marks['p0']!.offsetRatio, .37);
      expect(getWrites(), writes);
    },
  );
}
