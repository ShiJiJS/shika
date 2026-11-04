import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';

Future<String?> openDialog(BuildContext context, WidgetBuilder builder) =>
    paperDialog<String>(context: context, builder: builder);

void main() {
  for (final sheet in [true, false]) {
    for (final entryReduced in [false, true]) {
      for (final exitReduced in [false, true]) {
        testWidgets(
          'overlay sheet=$sheet entry=$entryReduced exit=$exitReduced keeps result and draft',
          (t) async {
            t.platformDispatcher.accessibilityFeaturesTestValue =
                FakeAccessibilityFeatures(disableAnimations: entryReduced);
            addTearDown(
              t.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
            final source = TextEditingController(text: 'source search');
            final draft = TextEditingController(text: 'unsaved draft');
            addTearDown(source.dispose);
            addTearDown(draft.dispose);
            String? result;
            var returned = false;
            late ModalRoute<dynamic> route;
            Widget content(BuildContext context) {
              route = ModalRoute.of(context)!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: draft),
                  TextButton(
                    key: const Key('close-overlay'),
                    onPressed: () => Navigator.pop(context, 'confirmed'),
                    child: const Text('close'),
                  ),
                ],
              );
            }

            await t.pumpWidget(
              MaterialApp(
                theme: Paper.theme,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Column(
                      children: [
                        TextField(controller: source),
                        TextButton(
                          key: const Key('open-overlay'),
                          onPressed: () {
                            final future = sheet
                                ? paperSheet<String>(
                                    context,
                                    Builder(builder: content),
                                  )
                                : openDialog(
                                    context,
                                    (context) =>
                                        AlertDialog(content: content(context)),
                                  );
                            unawaited(
                              future.then((value) {
                                result = value;
                                returned = true;
                              }),
                            );
                          },
                          child: const Text('open'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await t.tap(find.byKey(const Key('open-overlay')));
            await t.pump();
            await t.pump();
            expect(
              route.transitionDuration,
              Duration(milliseconds: entryReduced ? 0 : 240),
            );
            if (entryReduced) {
              expect(route.animation!.value, 1);
            } else {
              await t.pump(const Duration(milliseconds: 120));
              expect(route.animation!.value, inExclusiveRange(0, 1));
              await t.pump(const Duration(milliseconds: 136));
            }
            t.platformDispatcher.accessibilityFeaturesTestValue =
                FakeAccessibilityFeatures(disableAnimations: exitReduced);
            await t.pump();
            expect(
              route.reverseTransitionDuration,
              Duration(milliseconds: exitReduced ? 0 : 160),
            );
            await t.tap(find.byKey(const Key('close-overlay')));
            expect(route.animation!.value, exitReduced ? 0 : 1);
            if (sheet && !exitReduced) expect(returned, isFalse);
            await t.pump();
            if (!exitReduced) {
              await t.pump(const Duration(milliseconds: 80));
              expect(route.animation!.value, inExclusiveRange(0, 1));
              await t.pump(const Duration(milliseconds: 96));
            }
            await t.pump();
            expect(returned, isTrue);
            expect(result, 'confirmed');
            expect(source.text, 'source search');
            expect(draft.text, 'unsaved draft');
            expect(find.byKey(const Key('close-overlay')), findsNothing);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
