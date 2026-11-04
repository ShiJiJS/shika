import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/trash_layout.dart';

void main() {
  for (final mode in ['ordinary', 'reduced', 'live']) {
    testWidgets('actual trash checkbox motion contract $mode', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: mode == 'reduced');
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      var selected = false, calls = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          builder: (_, child) => PaperControlTheme(child: child!),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, change) {
                return TrashEntryRow(
                  title: 'Retained video',
                  path: '/fixture/retained.mp4',
                  selected: selected,
                  onToggle: () => change(() {
                    selected = !selected;
                    calls++;
                  }),
                  onRestore: null,
                  restoreKey: const Key('restore'),
                );
              },
            ),
          ),
        ),
      );
      final checkbox = find.byWidgetPredicate((w) => w is Checkbox);
      final state = t.state(checkbox) as ToggleableStateMixin;
      final paint = find.descendant(
        of: checkbox,
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is ToggleablePainter,
        ),
      );
      double actualPaint() =>
          (t.widget<CustomPaint>(paint).painter! as ToggleablePainter)
              .position
              .value;
      await t.tap(checkbox);
      expect(calls, 1);
      expect(selected, isTrue);
      await t.pump();
      expect(t.widget<Checkbox>(checkbox).value, isTrue);
      if (mode == 'ordinary') {
        await t.pump(const Duration(milliseconds: 70));
        expect(actualPaint(), inExclusiveRange(0, 1));
        await t.pump(const Duration(milliseconds: 70));
      } else if (mode == 'live') {
        await t.pump(const Duration(milliseconds: 40));
        expect(actualPaint(), inExclusiveRange(0, 1));
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        await t.pump();
      }
      debugPrint(
        'ACTUAL trash $mode duration=${state.positionController.duration}'
        ' progress=${state.positionController.value} paint=${actualPaint()} calls=$calls',
      );
      expect(
        actualPaint(),
        1,
        reason: mode == 'ordinary'
            ? 'Selection must finish at 140ms'
            : 'Reduced motion must paint the endpoint on the first new frame',
      );
      expect(calls, 1);
      await t.pumpWidget(const SizedBox());
    });
  }
}
