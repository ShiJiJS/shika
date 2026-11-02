import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';

const legacy = bool.fromEnvironment('LEGACY_CONTROLS');
const idle = Color(0xfffaf8f3), chosen = Color(0xff53664a);
Color? fill(WidgetTester t) =>
    (t
                .widget<Ink>(
                  find.descendant(
                    of: find.byType(RawChip),
                    matching: find.byType(Ink),
                  ),
                )
                .decoration
            as ShapeDecoration)
        .color;

void main() {
  for (final multiple in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'selection multi=$multiple reduced=$reduced preserves callback and ends at 140ms',
        (t) async {
          t.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
          var selected = false, calls = 0;
          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme.copyWith(
                chipTheme: const ChipThemeData(selectedColor: chosen),
              ),
              home: StatefulBuilder(
                builder: (context, change) {
                  void select(bool value) {
                    calls++;
                    change(() => selected = value);
                  }

                  final Widget chip = multiple
                      ? legacy
                            ? FilterChip(
                                label: const Text('tag'),
                                selected: selected,
                                onSelected: select,
                                backgroundColor: idle,
                              )
                            : PaperFilterChip(
                                label: const Text('tag'),
                                selected: selected,
                                onSelected: select,
                                backgroundColor: idle,
                              )
                      : legacy
                      ? ChoiceChip(
                          label: const Text('mode'),
                          selected: selected,
                          onSelected: select,
                          backgroundColor: idle,
                          selectedColor: chosen,
                        )
                      : PaperChoiceChip(
                          label: const Text('mode'),
                          selected: selected,
                          onSelected: select,
                          backgroundColor: idle,
                          selectedColor: chosen,
                        );
                  return Scaffold(body: Center(child: chip));
                },
              ),
            ),
          );
          expect(fill(t), idle);
          await t.tap(find.byType(RawChip));
          expect(calls, 1);
          expect(selected, isTrue);
          await t.pump();
          expect(t.widget<RawChip>(find.byType(RawChip)).selected, isTrue);
          if (reduced) {
            expect(
              fill(t),
              chosen,
              reason: 'No intermediate paint with reduced motion',
            );
          } else {
            await t.pump(const Duration(milliseconds: 70));
            expect(fill(t), isNot(anyOf(idle, chosen)));
            await t.pump(const Duration(milliseconds: 70));
            expect(
              fill(t),
              chosen,
              reason: 'Actual rendered fill reaches target at 140ms',
            );
          }
          await t.tap(find.byType(RawChip));
          await t.pump();
          expect(calls, 2);
          expect(selected, isFalse);
          if (!reduced) await t.pump(const Duration(milliseconds: 140));
          expect(fill(t), idle);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'live reduced motion completes an in-flight selection without remount or focus/callback loss multi=$multiple',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures();
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var selected = false, calls = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme.copyWith(
              chipTheme: const ChipThemeData(selectedColor: chosen),
            ),
            home: StatefulBuilder(
              builder: (context, change) {
                void select(bool value) {
                  calls++;
                  change(() => selected = value);
                }

                return Scaffold(
                  body: Center(
                    child: multiple
                        ? legacy
                              ? FilterChip(
                                  label: const Text('tag'),
                                  selected: selected,
                                  onSelected: select,
                                  focusNode: focus,
                                  backgroundColor: idle,
                                )
                              : PaperFilterChip(
                                  label: const Text('tag'),
                                  selected: selected,
                                  onSelected: select,
                                  focusNode: focus,
                                  backgroundColor: idle,
                                )
                        : legacy
                        ? ChoiceChip(
                            label: const Text('mode'),
                            selected: selected,
                            onSelected: select,
                            focusNode: focus,
                            backgroundColor: idle,
                            selectedColor: chosen,
                          )
                        : PaperChoiceChip(
                            label: const Text('mode'),
                            selected: selected,
                            onSelected: select,
                            focusNode: focus,
                            backgroundColor: idle,
                            selectedColor: chosen,
                          ),
                  ),
                );
              },
            ),
          ),
        );
        focus.requestFocus();
        await t.pump();
        expect(focus.hasFocus, isTrue);
        final mounted = t.state(find.byType(RawChip));
        await t.tap(find.byType(RawChip));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        expect(fill(t), isNot(anyOf(idle, chosen)));
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        await t.pump();
        expect(fill(t), chosen);
        expect(t.state(find.byType(RawChip)), same(mounted));
        expect(focus.hasFocus, isTrue);
        expect(calls, 1);
        await t.tap(find.byType(RawChip));
        await t.pump();
        expect(fill(t), idle);
        expect(calls, 2);
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures();
        await t.pump();
        await t.tap(find.byType(RawChip));
        await t.pump();
        await t.pump(const Duration(milliseconds: 70));
        expect(fill(t), isNot(anyOf(idle, chosen)));
        await t.pump(const Duration(milliseconds: 70));
        expect(fill(t), chosen);
        expect(calls, 3);
        expect(t.state(find.byType(RawChip)), same(mounted));
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'button real Material state timing reduced=$reduced, callback is immediate and disabled cannot submit twice',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        var calls = 0, enabled = true;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: StatefulBuilder(
              builder: (context, change) {
                final child = Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: enabled
                          ? () {
                              calls++;
                              change(() => enabled = false);
                            }
                          : null,
                      child: const Text('submit'),
                    ),
                  ),
                );
                return legacy ? child : PaperControlTheme(child: child);
              },
            ),
          ),
        );
        final material = find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(Material),
        );
        expect(
          t.widget<Material>(material).animationDuration,
          Duration(milliseconds: reduced ? 0 : 100),
        );
        await t.tap(find.text('submit'));
        expect(calls, 1);
        await t.pump();
        expect(
          t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await t.tap(find.text('submit'));
        expect(calls, 1);
        if (!reduced) await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
      },
    );
  }
}
