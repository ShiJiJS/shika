import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';

void main() {
  for (final expand in [true, false]) {
    testWidgets('style-only live direction $expand', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ExpansionTile(
                key: const Key('style-only'),
                expansionAnimationStyle: AnimationStyle(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                ),
                title: const Text('Details'),
                children: const [SizedBox(height: 180)],
              ),
            ),
          ),
        ),
      );
      final clip = find.byWidgetPredicate(
        (w) =>
            w is ClipRect &&
            w.child is Align &&
            (w.child! as Align).heightFactor != null,
      );
      double height() =>
          (t.widget<ClipRect>(clip).child! as Align).heightFactor!;
      if (!expand) {
        await t.tap(find.text('Details'));
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Details'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(height(), inExclusiveRange(0, 1));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      debugPrint('STYLE ONLY expand=$expand firstReducedHeight=${height()}');
      expect(height(), expand ? 1 : 0);
      await t.pumpWidget(const SizedBox());
    });
  }
}
