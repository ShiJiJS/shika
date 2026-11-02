import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/paper_toggle.dart';
import 'package:video_viewer/ui/preference_switch.dart';

void main() {
  testWidgets('whole-row pointer, switch and keyboard each toggle once', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    try {
      var value = false, changes = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => PaperPreferenceSwitch(
                key: const Key('preference'),
                icon: Icons.dark_mode_outlined,
                title: '暗黑模式',
                value: value,
                onChanged: (next) => setState(() {
                  value = next;
                  changes++;
                }),
              ),
            ),
          ),
        ),
      );
      final row = find.byKey(const Key('preference'));
      expect(
        t.getSemantics(row).getSemanticsData().flagsCollection.isToggled,
        Tristate.isFalse,
      );
      await t.tap(find.text('暗黑模式'));
      await t.pumpAndSettle();
      expect(value, isTrue);
      expect(changes, 1);
      expect(
        t.getSemantics(row).getSemanticsData().flagsCollection.isToggled,
        Tristate.isTrue,
      );
      await t.tap(find.byType(PaperToggle));
      await t.pumpAndSettle();
      expect(value, isFalse);
      expect(changes, 2);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(value, isTrue);
      expect(changes, 3);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'disabled preference has no semantic activation or pointer write',
    (t) async {
      final semantics = t.ensureSemantics();
      try {
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: const Scaffold(
              body: PaperPreferenceSwitch(
                key: Key('preference'),
                icon: Icons.dark_mode_outlined,
                title: '暗黑模式',
                value: false,
                onChanged: null,
              ),
            ),
          ),
        );
        final data = t
            .getSemantics(find.byKey(const Key('preference')))
            .getSemanticsData();
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        await t.tap(find.text('暗黑模式'));
        await t.pumpAndSettle();
        expect(t.widget<PaperToggle>(find.byType(PaperToggle)).value, isFalse);
      } finally {
        semantics.dispose();
      }
    },
  );
}
