import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';

Finder get checkbox => find.byWidgetPredicate((w) => w is PaperCheckbox);
ToggleableStateMixin control(WidgetTester t) =>
    t.state(checkbox) as ToggleableStateMixin;

void _ignore(bool? value) {}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'row checkbox and text each activate once; keyboard and live preference retain focus reduced=$reduced',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var value = false, calls = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, set) => PaperCheckboxListTile(
                  title: const Text('Confirm only'),
                  value: value,
                  focusNode: focus,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (next) => set(() {
                    value = next!;
                    calls++;
                  }),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Confirm only'));
        await t.pump();
        expect(calls, 1);
        expect(value, isTrue);
        await t.pumpAndSettle();
        await t.tap(checkbox);
        await t.pump();
        expect(calls, 2);
        expect(value, isFalse);
        await t.pumpAndSettle();
        focus.requestFocus();
        await t.pump();
        final state = control(t);
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await t.pump();
        expect(calls, 3);
        expect(value, isTrue);
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        await t.pump();
        expect(identical(control(t), state), isTrue);
        expect(focus.hasFocus, isTrue);
        expect(control(t).positionController.value, 1);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(calls, 4);
        expect(value, isFalse);
        expect(control(t).positionController.value, 0);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'hold and pointer cancellation never change selection; reaction finishes reduced=$reduced',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        var calls = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: PaperCheckbox(value: false, onChanged: (_) => calls++),
            ),
          ),
        );
        final gesture = await t.startGesture(t.getCenter(checkbox));
        await t.pump(const Duration(milliseconds: 120));
        await t.pump(const Duration(milliseconds: 50));
        expect(calls, 0);
        expect(control(t).reactionController.value, greaterThan(0));
        await gesture.cancel();
        await t.pump();
        if (!reduced) await t.pump(const Duration(milliseconds: 100));
        expect(control(t).reactionController.value, 0);
        expect(calls, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'live reduced reaction completes a held press then releases with one value callback',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures();
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      var value = false, calls = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) => PaperCheckbox(
                value: value,
                onChanged: (v) {
                  calls++;
                  set(() => value = v!);
                },
              ),
            ),
          ),
        ),
      );
      final gesture = await t.startGesture(t.getCenter(checkbox));
      await t.pump(const Duration(milliseconds: 120));
      await t.pump(const Duration(milliseconds: 40));
      expect(control(t).reactionController.value, inExclusiveRange(0, 1));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      expect(control(t).reactionController.value, 1);
      expect(calls, 0);
      await gesture.up();
      await t.pump();
      expect(control(t).reactionController.value, 0);
      expect(control(t).positionController.value, 1);
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rapid reversal and disable while held keep authoritative value and cancel pending activation',
    (t) async {
      var value = false, enabled = true, calls = 0;
      late StateSetter update;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) {
                update = set;
                return PaperCheckbox(
                  value: value,
                  onChanged: enabled
                      ? (v) => set(() {
                          value = v!;
                          calls++;
                        })
                      : null,
                );
              },
            ),
          ),
        ),
      );
      await t.tap(checkbox);
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(checkbox);
      await t.pump();
      await t.pump(const Duration(milliseconds: 140));
      expect(calls, 2);
      expect(value, isFalse);
      expect(control(t).positionController.value, 0);
      final gesture = await t.startGesture(t.getCenter(checkbox));
      await t.pump(const Duration(milliseconds: 150));
      update(() => enabled = false);
      await t.pump();
      expect(control(t).reactionController.value, 0);
      await gesture.up();
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(value, isFalse);
      await t.tap(checkbox);
      await t.pumpAndSettle();
      expect(calls, 2);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'tristate endpoints activate once and restored row semantics match SDK',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final semantics = t.ensureSemantics();
      try {
        bool? value = false;
        var calls = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, set) => PaperCheckboxListTile(
                  title: const Text('Tristate confirmation'),
                  value: value,
                  tristate: true,
                  onChanged: (v) => set(() {
                    value = v;
                    calls++;
                  }),
                ),
              ),
            ),
          ),
        );
        for (final next in <bool?>[true, null, false]) {
          await t.tap(find.text('Tristate confirmation'));
          await t.pump();
          expect(value, next);
          expect(control(t).positionController.value, next == false ? 0 : 1);
        }
        expect(calls, 3);
        expect(find.byType(MergeSemantics), findsOneWidget);
        // Compare the native merged node representation rather than assuming
        // the parent alone reports every descendant checkbox flag.
        final adapted = t
            .getSemantics(find.byType(MergeSemantics))
            .getSemanticsData()
            .toString();
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: const Scaffold(
              body: CheckboxListTile(
                title: Text('Tristate confirmation'),
                value: false,
                tristate: true,
                onChanged: _ignore,
              ),
            ),
          ),
        );
        expect(
          t
              .getSemantics(find.byType(MergeSemantics))
              .getSemanticsData()
              .toString(),
          adapted,
        );
        await t.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
        await t.pump();
      }
    },
  );
}
