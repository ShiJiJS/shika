import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/models.dart';
import 'package:shika/ui/home.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/preferences.dart';

import 'expansion_motion_diagnostic_test.dart' show scanDetails, visibleHeight;
import 'support/scan_details_fixture.dart';

void main() {
  testWidgets(
    'actual scan attention replaces an animating summary without losing progress or errors',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      final repo = ScanDetailsLibrary();
      final preferences = UiPreferences();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        preferences.dispose();
        t.platformDispatcher.clearAccessibilityFeaturesTestValue();
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
      await t.ensureVisible(scanDetails());
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('root-scan-summary')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(visibleHeight(t), inExclusiveRange(0, 1));
      repo.libraryPreparation.value = const LibraryPreparation(
        scanning: true,
        phase: 'processing_media',
        discovered: 5,
        processed: 4,
      );
      await t.pump();
      expect(scanDetails(), findsNothing);
      expect(find.byKey(const Key('library-preparation')), findsOneWidget);
      expect(find.textContaining('4 / 5 个'), findsOneWidget);
      repo.libraryPreparation.value = const LibraryPreparation(
        phase: 'failed',
        failed: 1,
        failureReasons: {'probe_timeout': 1},
      );
      await t.pump();
      expect(find.text('读取媒体信息超时 1 个'), findsOneWidget);
      expect(scanDetails(), findsNothing);
      expect(find.byKey(const Key('library-preparation')), findsOneWidget);
      repo.libraryPreparation.value = const LibraryPreparation(
        phase: 'completed',
        discovered: 5,
        processed: 5,
      );
      await t.pump();
      expect(scanDetails(), findsOneWidget);
      expect(visibleHeight(t), 0);
      expect(find.byKey(const Key('library-preparation')), findsNothing);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      await t.ensureVisible(scanDetails());
      await t.pump();
      await t.tap(find.byKey(const Key('root-scan-summary')));
      await t.pump();
      expect(visibleHeight(t), 1);
      expect(find.byKey(const Key('library-preparation')), findsOneWidget);
      expect(find.textContaining('5 / 5 个'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    },
  );
}
