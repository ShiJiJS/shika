import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mount lazy actions by actually scrolling, then place them inside their clip.
Future<void> revealAction(WidgetTester t, Finder target) async {
  for (final direction in [1, -1]) {
    for (var i = 0; target.evaluate().isEmpty && i < 60; i++) {
      final scrolls = find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                axisDirectionToAxis(w.axisDirection) == Axis.vertical,
          )
          .hitTestable();
      if (scrolls.evaluate().isEmpty) break;
      await t.drag(scrolls.first, Offset(0, -240.0 * direction));
      await t.pumpAndSettle();
    }
    if (target.evaluate().isNotEmpty) break;
  }
  expect(target, findsWidgets);
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await Scrollable.ensureVisible(t.element(target), alignment: .5);
  await t.pumpAndSettle();
  for (var i = 0; target.hitTestable().evaluate().isEmpty && i < 8; i++) {
    final ancestor = find.ancestor(
      of: target,
      matching: find.byType(Scrollable),
    );
    if (ancestor.evaluate().isEmpty) break;
    final scroll = ancestor.first;
    final above = t.getCenter(target).dy < t.getRect(scroll).center.dy;
    await t.drag(scroll, Offset(0, above ? 120 : -120));
    await t.pumpAndSettle();
  }
  expect(target.hitTestable(), findsWidgets);
}
