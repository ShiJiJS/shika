import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/paper_press.dart';

class CaptureFactory extends InteractiveInkFeatureFactory {
  CaptureFactory(this.original);
  final InteractiveInkFeatureFactory original;
  final features = <PaperPressInk>[];
  int removals = 0;
  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    final feature = original.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: () {
        removals++;
        onRemoved?.call();
      },
    );
    features.add(feature as PaperPressInk);
    return feature;
  }
}

void main() {
  for (final reduced in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'actual button ink reduced=$reduced cancel=$cancel preserves gesture and disposes once',
        (t) async {
          t.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
          CaptureFactory? captured;
          var calls = 0;
          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme,
              home: PaperControlTheme(
                child: Builder(
                  builder: (context) {
                    captured ??= CaptureFactory(
                      Theme.of(context).splashFactory,
                    );
                    return Theme(
                      data: Theme.of(context).copyWith(splashFactory: captured),
                      child: Scaffold(
                        body: Center(
                          child: FilledButton(
                            onPressed: () => calls++,
                            child: const Text('action'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          final gesture = await t.startGesture(
            t.getCenter(find.text('action')),
          );
          await t.pump(kPressTimeout);
          expect(captured!.features, hasLength(1));
          final ink = captured!.features.single;
          if (reduced) {
            expect(ink.animation.value, 1);
          } else {
            await t.pump(const Duration(milliseconds: 50));
            expect(ink.animation.value, inExclusiveRange(0, 1));
            await t.pump(const Duration(milliseconds: 50));
            expect(ink.animation.value, 1);
          }
          expect(calls, 0);
          if (cancel) {
            await gesture.cancel();
          } else {
            await gesture.up();
          }
          expect(calls, cancel ? 0 : 1);
          if (reduced) {
            expect(
              captured!.removals,
              1,
              reason:
                  "ink value=${ink.animation.value} status=${ink.animation.status}",
            );
          } else {
            await t.pump();
            await t.pump(const Duration(milliseconds: 50));
            expect(ink.animation.value, inExclusiveRange(0, 1));
            await t.pump(const Duration(milliseconds: 50));
            expect(
              ink.animation.value,
              0,
              reason: 'Paint has reached its 100ms exit target',
            );
            // Controller completion is delivered on the next scheduler frame.
            await t.pump(const Duration(milliseconds: 16));
            expect(
              captured!.removals,
              1,
              reason:
                  "ink value=${ink.animation.value} status=${ink.animation.status}",
            );
          }
          await t.pumpWidget(const SizedBox());
          expect(
            captured!.removals,
            1,
            reason:
                "ink value=${ink.animation.value} status=${ink.animation.status}",
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final closing in [false, true]) {
    testWidgets(
      'live preference completes active actual ink closing=$closing without gesture duplication',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures();
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        CaptureFactory? captured;
        var calls = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: PaperControlTheme(
              child: Builder(
                builder: (context) {
                  captured ??= CaptureFactory(Theme.of(context).splashFactory);
                  return Theme(
                    data: Theme.of(context).copyWith(splashFactory: captured),
                    child: Scaffold(
                      body: Center(
                        child: FilledButton(
                          onPressed: () => calls++,
                          child: const Text('action'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final gesture = await t.startGesture(t.getCenter(find.text('action')));
        await t.pump(kPressTimeout);
        final ink = captured!.features.single;
        if (closing) {
          await t.pump(const Duration(milliseconds: 100));
          await gesture.up();
          await t.pump();
        }
        await t.pump(const Duration(milliseconds: 40));
        expect(ink.animation.value, inExclusiveRange(0, 1));
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        await t.pump();
        if (closing) {
          expect(
            captured!.removals,
            1,
            reason:
                "ink value=${ink.animation.value} status=${ink.animation.status}",
          );
          expect(calls, 1);
        } else {
          expect(ink.animation.value, 1);
          expect(calls, 0);
          await gesture.up();
          expect(calls, 1);
          expect(
            captured!.removals,
            1,
            reason:
                "ink value=${ink.animation.value} status=${ink.animation.status}",
          );
        }
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final reduced in [false, true]) {
    for (final keyboard in [false, true]) {
      testWidgets(
        'quick activation remains visible without delaying callback reduced=$reduced keyboard=$keyboard',
        (t) async {
          t.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
          final focus = FocusNode();
          addTearDown(focus.dispose);
          CaptureFactory? captured;
          var calls = 0;
          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme,
              home: PaperControlTheme(
                child: Builder(
                  builder: (context) {
                    captured ??= CaptureFactory(
                      Theme.of(context).splashFactory,
                    );
                    return Theme(
                      data: Theme.of(context).copyWith(splashFactory: captured),
                      child: Scaffold(
                        body: Center(
                          child: FilledButton(
                            focusNode: focus,
                            onPressed: () => calls++,
                            child: const Text('quick'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          if (keyboard) {
            focus.requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            await t.tap(find.text('quick'));
          }
          expect(calls, 1);
          expect(captured!.features, hasLength(1));
          final ink = captured!.features.single;
          if (reduced) {
            expect(captured!.removals, 1);
          } else {
            expect(
              ink.animation.value,
              1,
              reason: 'Quick tap/key activation must leave a visible 100ms acknowledgement',
            );
            expect(captured!.removals, 0);
            await t.pump();
            await t.pump(const Duration(milliseconds: 50));
            expect(ink.animation.value, inExclusiveRange(0, 1));
            await t.pump(const Duration(milliseconds: 50));
            expect(ink.animation.value, 0);
            await t.pump(const Duration(milliseconds: 16));
            expect(captured!.removals, 1);
          }
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
