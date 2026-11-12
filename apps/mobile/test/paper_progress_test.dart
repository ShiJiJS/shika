import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper_progress.dart';

const _pixels = Key('progress-pixels');
const _indicator = Key('progress');

Widget indicator(bool circular, {double? value, bool native = false}) {
  if (circular) {
    return native
        ? CircularProgressIndicator(
            key: _indicator,
            value: value,
            color: Colors.green,
            backgroundColor: Colors.grey,
            strokeWidth: 2,
          )
        : PaperCircularProgressIndicator(
            key: _indicator,
            value: value,
            color: Colors.green,
            backgroundColor: Colors.grey,
            strokeWidth: 2,
          );
  }
  return native
      ? LinearProgressIndicator(
          key: _indicator,
          value: value,
          color: Colors.green,
          backgroundColor: Colors.grey,
          minHeight: 3,
          borderRadius: BorderRadius.circular(4),
        )
      : PaperLinearProgressIndicator(
          key: _indicator,
          value: value,
          color: Colors.green,
          backgroundColor: Colors.grey,
          minHeight: 3,
          borderRadius: BorderRadius.circular(4),
        );
}

Widget surface(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: _pixels,
        child: SizedBox(width: 180, height: 64, child: Center(child: child)),
      ),
    ),
  ),
);

Future<List<int>> pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_pixels),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  }))!;
}

class _RefreshList extends StatefulWidget {
  const _RefreshList({required this.controller});
  final ScrollController controller;

  @override
  State<_RefreshList> createState() => _RefreshListState();
}

class _RefreshListState extends State<_RefreshList> {
  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: widget.controller,
    physics: const AlwaysScrollableScrollPhysics(),
    itemExtent: 48,
    itemCount: 60,
    itemBuilder: (context, index) => Text('item $index'),
  );
}

Widget refreshSurface(ScrollController controller, RefreshCallback onRefresh) =>
    MaterialApp(
      home: Scaffold(
        body: PaperRefreshIndicator(
          onRefresh: onRefresh,
          child: _RefreshList(controller: controller),
        ),
      ),
    );

Finder nativeRefresh() => find.byWidgetPredicate((w) => w is RefreshIndicator);

void main() {
  for (final initialReduced in [false, true]) {
    testWidgets(
      'short pull cancels across live preference change; reduced=$initialReduced',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: initialReduced);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final controller = ScrollController();
        addTearDown(controller.dispose);
        var calls = 0;
        await tester.pumpWidget(
          refreshSurface(controller, () async => calls++),
        );
        final nativeState = tester.state(nativeRefresh());
        final childState = tester.state(find.byType(_RefreshList));
        final gesture = await tester.startGesture(const Offset(200, 200));
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
        if (initialReduced) expect(find.text('下拉刷新'), findsOneWidget);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: !initialReduced);
        await tester.pump();
        expect(tester.state(nativeRefresh()), same(nativeState));
        expect(tester.state(find.byType(_RefreshList)), same(childState));
        if (!initialReduced) expect(find.text('下拉刷新'), findsOneWidget);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(find.text('下拉刷新'), findsNothing);
        expect(find.text('正在刷新'), findsNothing);
        expect(controller.offset, 0);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'armed and pending refresh survive live changes once; reduced=$initialReduced',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: initialReduced);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final pending = Completer<void>();
        var calls = 0;
        await tester.pumpWidget(
          refreshSurface(controller, () {
            calls++;
            return pending.future;
          }),
        );
        final nativeState = tester.state(nativeRefresh());
        final childState = tester.state(find.byType(_RefreshList));
        final childElement = tester.element(find.byType(_RefreshList));
        final position = controller.position;
        final gesture = await tester.startGesture(const Offset(200, 150));
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 300));
        await tester.pump();
        if (initialReduced) expect(find.text('松开刷新'), findsOneWidget);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: !initialReduced);
        await tester.pump();
        if (!initialReduced) expect(find.text('松开刷新'), findsOneWidget);
        expect(tester.state(nativeRefresh()), same(nativeState));
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(calls, 1);
        controller.jumpTo(120);
        await tester.pump();

        for (final reduced in [true, false, true]) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          await tester.pump();
          expect(tester.state(nativeRefresh()), same(nativeState));
          expect(tester.state(find.byType(_RefreshList)), same(childState));
          expect(tester.element(find.byType(_RefreshList)), same(childElement));
          expect(controller.position, same(position));
          expect(controller.offset, 120);
          expect(calls, 1);
          if (reduced) {
            expect(find.text('正在刷新'), findsOneWidget);
            expect(find.byType(RefreshProgressIndicator), findsNothing);
            expect(tester.binding.transientCallbackCount, 0);
          } else {
            expect(find.byType(RefreshProgressIndicator), findsOneWidget);
            expect(tester.binding.transientCallbackCount, greaterThan(0));
          }
        }
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.text('正在刷新'), findsNothing);
        expect(calls, 1);
        expect(controller.offset, 120);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final circular in [false, true]) {
    testWidgets('busy marker stops and resumes live; circular=$circular', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures();
        await tester.pumpWidget(surface(indicator(circular)));
        final size = tester.getSize(find.byKey(_indicator));
        final first = await pixels(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(await pixels(tester), isNot(first));
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        await tester.pump();
        expect(tester.getSize(find.byKey(_indicator)), size);
        expect(tester.binding.transientCallbackCount, 0);
        final busy = tester.getSemantics(find.bySemanticsLabel('正在加载'));
        expect(busy.getSemanticsData().role, SemanticsRole.loadingSpinner);
        expect(busy.value, isEmpty);
        final still = await pixels(tester);
        await tester.pump(const Duration(seconds: 2));
        expect(await pixels(tester), still);
        expect(tester.binding.hasScheduledFrame, isFalse);

        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures();
        await tester.pump();
        final resumed = await pixels(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(await pixels(tester), isNot(resumed));
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await tester.pumpWidget(const SizedBox());
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'initial reduction has no repeating frames; circular=$circular',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(surface(indicator(circular)));
        final first = await pixels(tester);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(seconds: 2));
        expect(await pixels(tester), first);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );

    for (final reduced in [false, true]) {
      testWidgets(
        'known progress keeps native pixels and semantics; circular=$circular reduced=$reduced',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                FakeAccessibilityFeatures(disableAnimations: reduced);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
            for (final value in [0.0, .42, 1.0]) {
              await tester.pumpWidget(
                surface(indicator(circular, value: value, native: true)),
              );
              final nativePixels = await pixels(tester);
              final nativeSize = tester.getSize(find.byKey(_indicator));
              final nativeData = tester
                  .getSemantics(find.byKey(_indicator))
                  .getSemanticsData();
              await tester.pumpWidget(
                surface(indicator(circular, value: value)),
              );
              final data = tester
                  .getSemantics(find.byKey(_indicator))
                  .getSemanticsData();
              expect(tester.getSize(find.byKey(_indicator)), nativeSize);
              expect(await pixels(tester), nativePixels);
              expect(data.role, SemanticsRole.progressBar);
              expect(data.value, nativeData.value);
              expect(data.value, '${(value * 100).round()}');
              expect(find.bySemanticsLabel('正在加载'), findsNothing);
              expect(tester.binding.transientCallbackCount, 0);
            }
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
