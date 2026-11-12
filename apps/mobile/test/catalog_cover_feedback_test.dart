import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/library/video_catalog_page.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/media_layout.dart';
import 'package:shika/ui/paper.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary;

Future<List<int>> coverPixels(GlobalKey boundary, Rect rect) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 1);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final output = <int>[];
    for (var y = rect.top.ceil() + 5; y < rect.bottom.floor() - 5; y++) {
      for (var x = rect.left.ceil() + 5; x < rect.right.floor() - 5; x++) {
        final offset = (y * image.width + x) * 4;
        for (var channel = 0; channel < 4; channel++) {
          output.add(bytes.getUint8(offset + channel));
        }
      }
    }
    return output;
  } finally {
    image.dispose();
  }
}

int changes(List<int> before, List<int> after) =>
    Iterable<int>.generate(before.length)
        .where((i) => before[i] != after[i])
        .length;

void main() {
  for (final pack in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'opaque cover shows press feedback and cancels without opening pack=$pack reduced=$reduced',
        (t) async {
          t.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          final repo = WorkspaceLibrary();
          final boundary = GlobalKey();
          final semantics = t.ensureSemantics();
          addTearDown(() async {
            await t.pumpWidget(const SizedBox());
            repo.dispose();
            t.platformDispatcher.clearAccessibilityFeaturesTestValue();
          });
          await repo.initialize();
          await t.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: ShikaApp(repository: repo),
            ),
          );
          await t.pumpAndSettle();
          if (pack) {
            await t.tap(find.byKey(const Key('kind-pack')));
            await t.pumpAndSettle();
          }
          final dynamic page = pack
              ? t.state<PackCatalogPageState>(find.byType(PackCatalogPage))
              : t.state<VideoCatalogPageState>(find.byType(VideoCatalogPage));
          final id = page.data.items.first.id as String;
          final target = find.byKey(Key('${pack ? 'pack-tile' : 'tile'}-$id'));
          final rect = t.getRect(target);
          try {
            final semanticsData = t.getSemantics(target).getSemanticsData();
            expect(semanticsData.hasAction(ui.SemanticsAction.tap), isTrue);
            expect(
              semanticsData.hasAction(ui.SemanticsAction.longPress),
              isTrue,
            );
          } finally {
            semantics.dispose();
          }
          final offset = page.scroll.offset as double;
          // Asset decoding is asynchronous; settle the image before comparing ink.
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await t.pumpAndSettle();
          final images = t.elementList(find.byType(Image)).toList();
          final before = (await t.runAsync(() => coverPixels(boundary, rect)))!;
          await t.pump(const Duration(milliseconds: 200));
          final idle = (await t.runAsync(() => coverPixels(boundary, rect)))!;
          expect(
            changes(before, idle),
            0,
            reason: 'The decoded cover is stable before pressing',
          );
          final gesture = await t.startGesture(rect.center);
          await t.pump(kPressTimeout);
          await t.pump(const Duration(milliseconds: 100));
          final pressed = (await t.runAsync(
            () => coverPixels(boundary, rect),
          ))!;
          expect(
            changes(before, pressed),
            greaterThan(0),
            reason: 'The state layer must paint above the opaque image',
          );
          expect(t.getRect(target), rect);
          expect(page.scroll.offset, offset);
          expect(
            t.elementList(find.byType(Image)).toList(),
            images,
            reason: 'Press feedback does not remount or reload images',
          );
          await gesture.cancel();
          await t.pumpAndSettle();
          final cancelled = (await t.runAsync(
            () => coverPixels(boundary, rect),
          ))!;
          expect(changes(before, cancelled), 0);
          expect(page.selected, isEmpty);
          expect(page.selecting, isFalse);
          expect(page.scroll.offset, offset);
          expect(find.byKey(const Key('app-navigation')), findsOneWidget);
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'dragging from a cover scrolls without opening or selecting pack=$pack',
      (t) async {
        final repo = WorkspaceLibrary();
        t.view.physicalSize = const Size(390, 520);
        t.view.devicePixelRatio = 1;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await repo.initialize();
        await t.pumpWidget(ShikaApp(repository: repo));
        await t.pumpAndSettle();
        if (pack) {
          await t.tap(find.byKey(const Key('kind-pack')));
          await t.pumpAndSettle();
        }
        final dynamic page = pack
            ? t.state<PackCatalogPageState>(find.byType(PackCatalogPage))
            : t.state<VideoCatalogPageState>(find.byType(VideoCatalogPage));
        final id = page.data.items.first.id as String;
        final target = find.byKey(Key('${pack ? 'pack-tile' : 'tile'}-$id'));
        final viewport = find.byKey(Key(pack ? 'pack-grid' : 'video-grid'));
        final point = t.getRect(target).intersect(t.getRect(viewport)).center;
        await t.dragFrom(point, const Offset(0, -80));
        await t.pumpAndSettle();
        expect(page.scroll.offset, greaterThan(0));
        expect(page.selected, isEmpty);
        expect(page.selecting, isFalse);
        expect(find.byKey(const Key('app-navigation')), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('catalogue selection paints its endpoint on the first frame', (
    t,
  ) async {
    var selected = false;
    late StateSetter update;
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(body: MediaSelectionMark(selected));
          },
        ),
      ),
    );
    update(() => selected = true);
    await t.pump();
    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(MediaSelectionMark),
        matching: find.byType(Container),
      ),
    );
    expect((container.decoration as BoxDecoration).color, Paper.olive);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
