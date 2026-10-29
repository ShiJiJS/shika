import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/paper_toggle.dart';
import 'package:video_viewer/ui/preference_switch.dart';

PaperTogglePainter painter(WidgetTester t) =>
    t
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(PaperToggle),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as PaperTogglePainter;
void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'toggle140 with immediate callback reduced=$reduced and live preference preserves the row',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        var value = false, calls = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (c, set) => PaperPreferenceSwitch(
                  icon: Icons.settings,
                  title: 'setting',
                  value: value,
                  onChanged: (v) => set(() {
                    value = v;
                    calls++;
                  }),
                ),
              ),
            ),
          ),
        );
        final state = t.state(find.byType(PaperToggle));
        await t.tap(find.byType(PaperToggle));
        expect(value, isTrue);
        expect(calls, 1);
        await t.pump();
        if (reduced) {
          expect(painter(t).position, 1);
          expect(painter(t).reaction, 0);
        } else {
          await t.pump(const Duration(milliseconds: 70));
          expect(painter(t).position, inExclusiveRange(0, 1));
          expect(
            painter(t).track,
            Color.lerp(Paper.line, Paper.olive, painter(t).position),
          );
          expect(painter(t).track, isNot(anyOf(Paper.line, Paper.olive)));
          await t.pump(const Duration(milliseconds: 70));
          expect(painter(t).position, 1);
        }
        expect(t.state(find.byType(PaperToggle)), same(state));
        await t.tap(find.byType(PaperToggle));
        await t.pump();
        if (!reduced) {
          await t.pump(const Duration(milliseconds: 40));
          expect(painter(t).position, inExclusiveRange(0, 1));
          t.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: true);
          await t.pump();
        }
        expect(painter(t).position, 0);
        expect(calls, 2);
        expect(t.state(find.byType(PaperToggle)), same(state));
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final rtl in [false, true]) {
    testWidgets(
      'drag follows finger and commits once with correct direction rtl=$rtl',
      (t) async {
        var value = false, calls = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (c, set) => PaperPreferenceSwitch(
                    icon: Icons.settings,
                    title: 'setting',
                    value: value,
                    onChanged: (v) => set(() {
                      value = v;
                      calls++;
                    }),
                  ),
                ),
              ),
            ),
          ),
        );
        final sign = rtl ? -1.0 : 1.0;
        final g = await t.startGesture(t.getCenter(find.byType(PaperToggle)));
        await g.moveBy(Offset(30 * sign, 0));
        await t.pump();
        await g.moveBy(Offset(8 * sign, 0));
        await t.pump();
        expect(painter(t).position, inExclusiveRange(0, 1));
        expect(calls, 0);
        await g.moveBy(Offset(20 * sign, 0));
        await t.pump();
        expect(painter(t).position, 1);
        await g.up();
        expect(calls, 1);
        expect(value, isTrue);
        await t.pumpAndSettle();
        expect(painter(t).position, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('cancel and disabling an active drag submit nothing', (t) async {
    var value = false, enabled = true, calls = 0;
    late StateSetter change;
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) {
              change = set;
              return PaperPreferenceSwitch(
                icon: Icons.settings,
                title: 'setting',
                value: value,
                onChanged: enabled
                    ? (v) => set(() {
                        value = v;
                        calls++;
                      })
                    : null,
              );
            },
          ),
        ),
      ),
    );
    for (final disable in [false, true]) {
      final g = await t.startGesture(t.getCenter(find.byType(PaperToggle)));
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(10, 0));
      await t.pump();
      expect(painter(t).position, inExclusiveRange(0, 1));
      if (disable) {
        change(() => enabled = false);
        await t.pump();
        await g.up();
      } else {
        await g.cancel();
      }
      await t.pumpAndSettle();
      expect(calls, 0);
      expect(value, isFalse);
      expect(painter(t).position, 0);
    }
    expect(t.takeException(), isNull);
  });
  testWidgets('pending or failed persistence never invents a committed value', (
    t,
  ) async {
    var value = false, calls = 0;
    bool? requested;
    late StateSetter change;
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) {
              change = set;
              return PaperPreferenceSwitch(
                icon: Icons.settings,
                title: 'setting',
                value: value,
                onChanged: (v) {
                  calls++;
                  requested = v;
                },
              );
            },
          ),
        ),
      ),
    );
    await t.tap(find.byType(PaperToggle));
    await t.pumpAndSettle();
    expect(requested, isTrue);
    expect(calls, 1);
    expect(painter(t).position, 0);
    change(() => value = requested!);
    await t.pumpAndSettle();
    expect(painter(t).position, 1);
    expect(calls, 1);
    await t.tap(find.byType(PaperToggle));
    await t.pumpAndSettle();
    expect(requested, isFalse);
    expect(calls, 2);
    change(() {});
    await t.pumpAndSettle();
    expect(value, isTrue);
    expect(painter(t).position, 1);
    expect(calls, 2);
  });
  testWidgets(
    'reduced motion during a drag retains direct manipulation until cancellation',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures();
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: PaperPreferenceSwitch(
              icon: Icons.settings,
              title: 'setting',
              value: false,
              onChanged: (_) => calls++,
            ),
          ),
        ),
      );
      final g = await t.startGesture(t.getCenter(find.byType(PaperToggle)));
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(4, 0));
      await t.pump();
      final position = painter(t).position;
      expect(position, inExclusiveRange(0, 1));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      expect(painter(t).position, position);
      await g.moveBy(const Offset(4, 0));
      await t.pump();
      expect(painter(t).position, greaterThan(position));
      await g.cancel();
      await t.pump();
      expect(painter(t).position, 0);
      expect(calls, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('removing a row during a held drag never commits a preference', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: Scaffold(
          body: PaperPreferenceSwitch(
            icon: Icons.settings,
            title: 'setting',
            value: false,
            onChanged: (_) => calls++,
          ),
        ),
      ),
    );
    final g = await t.startGesture(t.getCenter(find.byType(PaperToggle)));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(12, 0));
    await t.pump();
    expect(painter(t).position, greaterThan(.5));
    await t.pumpWidget(const SizedBox());
    await g.up();
    expect(calls, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'resting pixels and sizes match original compact Material3 in16 combinations',
    (t) async {
      var count = 0;
      for (final dark in [false, true]) {
        for (final value in [false, true]) {
          for (final enabled in [false, true]) {
            for (final rtl in [false, true]) {
              List<int>? baseline;
              Size? originalSize;
              for (final original in [true, false]) {
                await t.pumpWidget(
                  MaterialApp(
                    theme: dark ? Paper.darkTheme : Paper.theme,
                    home: Directionality(
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Scaffold(
                        body: Center(
                          child: Builder(
                            builder: (c) {
                              final p = Paper.of(c);
                              final ValueChanged<bool>? onChanged = enabled
                                  ? (_) {}
                                  : null;
                              return RepaintBoundary(
                                key: const Key('pixels'),
                                child: SizedBox(
                                  width: 48,
                                  height: 40,
                                  child: Transform.scale(
                                    scale: 10 / 13,
                                    alignment: Alignment.centerRight,
                                    child: original
                                        ? Switch(
                                            value: value,
                                            onChanged: onChanged,
                                            thumbColor: WidgetStatePropertyAll(
                                              p.background,
                                            ),
                                            trackColor: WidgetStatePropertyAll(
                                              value ? p.olive : p.line,
                                            ),
                                            trackOutlineColor:
                                                WidgetStatePropertyAll(
                                                  value ? p.olive : p.muted,
                                                ),
                                          )
                                        : PaperToggle(
                                            value: value,
                                            onChanged: onChanged,
                                            thumb: p.background,
                                            track: p.olive,
                                            outline: p.olive,
                                            inactiveTrack: p.line,
                                            inactiveOutline: p.muted,
                                            reaction: p.olive,
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await t.pumpAndSettle();
                final boundary = t.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('pixels')),
                );
                final pixels = (await t.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final bytes = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List().toList();
                  image.dispose();
                  return bytes;
                }))!;
                if (original) {
                  baseline = pixels;
                  originalSize = boundary.size;
                } else {
                  expect(boundary.size, originalSize);
                  expect(
                    pixels,
                    baseline,
                    reason: 'dark=$dark value=$value enabled=$enabled rtl=$rtl',
                  );
                  count++;
                }
              }
            }
          }
        }
      }
      expect(count, 16);
      expect(t.takeException(), isNull);
    },
  );
}
