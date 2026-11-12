import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';

void main() {
  for (final target in [0.0, 1.0]) {
    testWidgets(
      'live reduced fade reaches $target without replacing child state',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures();
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final opacity = ValueNotifier(1 - target);
        final text = TextEditingController(text: 'kept draft');
        addTearDown(opacity.dispose);
        addTearDown(text.dispose);
        await t.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<double>(
              valueListenable: opacity,
              builder: (context, value, _) => PaperAnimatedOpacity(
                opacity: value,
                duration: PaperMotion.transition,
                child: Material(
                  child: TextField(
                    key: const Key('kept-input'),
                    controller: text,
                  ),
                ),
              ),
            ),
          ),
        );
        final field = t.element(find.byKey(const Key('kept-input')));
        opacity.value = target;
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        Finder fade() => find.descendant(
          of: find.byType(PaperAnimatedOpacity),
          matching: find.byType(FadeTransition),
        );
        expect(
          t.widget<FadeTransition>(fade()).opacity.value,
          inExclusiveRange(0, 1),
        );
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        await t.pump();
        expect(t.widget<FadeTransition>(fade()).opacity.value, target);
        expect(t.element(find.byKey(const Key('kept-input'))), same(field));
        expect(text.text, 'kept draft');
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final kind in ['page', 'fade', 'sheet', 'dialog']) {
    for (final exiting in [false, true]) {
      testWidgets(
        'live reduce finishes $kind ${exiting ? "exit" : "entry"} without losing result',
        (t) async {
          t.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures();
          addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
          late BuildContext source;
          late ModalRoute<dynamic> route;
          String? result;
          Widget content(BuildContext context) {
            route = ModalRoute.of(context)!;
            return const SizedBox(height: 100, child: Text('destination'));
          }

          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme,
              home: Builder(
                builder: (context) {
                  source = context;
                  return const Scaffold(body: Text('source'));
                },
              ),
            ),
          );
          final Future<String?> future;
          if (kind == 'sheet') {
            future = paperSheet<String>(source, Builder(builder: content));
          } else if (kind == 'dialog') {
            future = paperDialog<String>(
              context: source,
              builder: (c) => AlertDialog(content: content(c)),
            );
          } else {
            future = Navigator.of(source).push<String>(
              kind == 'fade'
                  ? PaperPageRoute<String>.fade(
                      builder: (c) => Scaffold(body: content(c)),
                    )
                  : PaperPageRoute<String>(
                      builder: (c) => Scaffold(body: content(c)),
                    ),
            );
          }
          unawaited(future.then((v) => result = v));
          await t.pump();
          if (exiting) {
            await t.pumpAndSettle();
            Navigator.of(source).pop('retained');
            await t.pump();
          }
          await t.pump(const Duration(milliseconds: 40));
          expect(route.animation!.value, inExclusiveRange(0, 1));
          t.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          await t.pump();
          expect(route.animation!.value, exiting ? 0 : 1);
          if (!exiting) Navigator.of(source).pop('retained');
          await t.pumpAndSettle();
          expect(result, 'retained');
          expect(find.text('source'), findsOneWidget);
          expect(find.text('destination'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('live reduced notice exit preserves queue, reasons and undo', (
    t,
  ) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late BuildContext source;
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: Builder(
          builder: (c) {
            source = c;
            return const Scaffold(body: Text('source'));
          },
        ),
      ),
    );
    final messenger = ScaffoldMessenger.of(source);
    final first = messenger.showSnackBar(
      PaperSnackBar(context: source, content: const Text('first')),
    );
    await t.pumpAndSettle();
    SnackBarClosedReason? firstClosed, nextClosed;
    unawaited(first.closed.then((v) => firstClosed = v));
    var undone = 0;
    final next = messenger.showSnackBar(
      PaperSnackBar(
        context: source,
        content: const Text('second'),
        action: SnackBarAction(label: 'undo', onPressed: () => undone++),
      ),
    );
    unawaited(next.closed.then((v) => nextClosed = v));
    messenger.hideCurrentSnackBar();
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    final motion = t.widget<SnackBar>(find.byType(SnackBar)).animation!;
    expect(motion.value, inExclusiveRange(0, 1));
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await t.pump();
    await t.pump();
    expect(firstClosed, SnackBarClosedReason.hide);
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    await t.tap(find.text('undo'));
    await t.pumpAndSettle();
    expect(undone, 1);
    expect(nextClosed, SnackBarClosedReason.action);
    expect(t.takeException(), isNull);
  });
}
