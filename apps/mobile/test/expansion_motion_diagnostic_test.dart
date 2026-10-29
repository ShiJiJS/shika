import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/home.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'support/scan_details_fixture.dart';

Finder scanDetails() => find.byKey(const Key('root-scan-details'));

double visibleHeight(WidgetTester t) {
  final clip = find.descendant(
    of: scanDetails(),
    matching: find.byWidgetPredicate(
      (w) =>
          w is ClipRect &&
          w.child is Align &&
          (w.child! as Align).heightFactor != null,
    ),
  );
  return (t.widget<ClipRect>(clip).child! as Align).heightFactor!;
}

void main() {
  for (final mode in ['ordinary', 'reduced', 'live']) {
    for (final expand in [true, false]) {
      testWidgets(
        'actual scan details $mode ${expand ? "expand" : "collapse"}',
        (t) async {
          t.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures();
          t.view.physicalSize = const Size(390, 844);
          t.view.devicePixelRatio = 1;
          final repo = ScanDetailsLibrary();
          final preferences = UiPreferences();
          addTearDown(() async {
            await t.pumpWidget(const SizedBox());
            repo.dispose();
            preferences.dispose();
            t.platformDispatcher.clearAccessibilityFeaturesTestValue();
            t.view.resetPhysicalSize();
            t.view.resetDevicePixelRatio();
          });
          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme,
              home: LibraryHome(repository: repo, preferences: preferences),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('nav-settings')));
          await t.pumpAndSettle();
          await t.tap(find.text('媒体目录'));
          await t.pumpAndSettle();
          expect(scanDetails(), findsOneWidget);
          await t.ensureVisible(scanDetails());
          await t.pumpAndSettle();
          final summary = find.byKey(const Key('root-scan-summary'));
          if (!expand) {
            await t.tap(summary);
            await t.pumpAndSettle();
            expect(visibleHeight(t), 1);
          }
          if (mode == 'reduced') {
            t.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            await t.pump();
          }
          await t.tap(summary);
          await t.pump();
          if (mode == 'ordinary') {
            await t.pump(const Duration(milliseconds: 80));
            expect(visibleHeight(t), inExclusiveRange(0, 1));
            await t.pump(const Duration(milliseconds: 80));
          } else if (mode == 'live') {
            await t.pump(const Duration(milliseconds: 40));
            expect(visibleHeight(t), inExclusiveRange(0, 1));
            t.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            await t.pump();
          }
          debugPrint(
            'ACTUAL scan $mode expand=$expand visibleHeight=${visibleHeight(t)}',
          );
          expect(
            visibleHeight(t),
            expand ? 1 : 0,
            reason: mode == 'ordinary'
                ? 'Expansion layer finishes at160ms'
                : 'First reduced frame reaches target',
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
