import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';

Finder clip() => find.byWidgetPredicate(
  (w) =>
      w is ClipRect &&
      w.child is Align &&
      (w.child! as Align).heightFactor != null,
);
double height(WidgetTester t) =>
    (t.widget<ClipRect>(clip()).child! as Align).heightFactor!;
double turns(WidgetTester t) => t
    .widget<RotationTransition>(
      find.byWidgetPredicate(
        (w) =>
            w is RotationTransition &&
            w.child is Icon &&
            (w.child! as Icon).icon == Icons.expand_more,
      ),
    )
    .turns
    .value;

void main() {
  testWidgets(
    'in-flight summary update and reduced motion retain body draft and focus',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      final text = TextEditingController(text: 'Retained draft');
      final focus = FocusNode();
      late StateSetter change;
      var summary = 'Scan complete';
      final bodyKey = GlobalKey();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        focus.dispose();
        text.dispose();
        t.platformDispatcher.clearAccessibilityFeaturesTestValue();
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) {
                change = set;
                return PaperExpansionTile(
                  title: Text(summary),
                  children: [
                    TextField(key: bodyKey, controller: text, focusNode: focus),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await t.tap(find.text(summary));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      final first = height(t);
      expect(first, inExclusiveRange(0, 1));
      final body = bodyKey.currentState;
      focus.requestFocus();
      change(() => summary = 'New scan summary');
      await t.pump();
      expect(height(t), first);
      expect(bodyKey.currentState, same(body));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      expect(height(t), 1);
      expect(turns(t), .5);
      expect(focus.hasFocus, isTrue);
      expect(text.text, 'Retained draft');
      expect(bodyKey.currentState, same(body));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await t.pump();
      expect(height(t), 1);
      await t.tap(find.text(summary));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(height(t), inExclusiveRange(0, 1));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      expect(height(t), 0);
      expect(turns(t), 0);
      expect(bodyKey.currentState, isNull);
      expect(focus.hasFocus, isFalse);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'quick reversal and removal during expansion release body and ticker',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: const Scaffold(
            body: PaperExpansionTile(
              title: Text('Details'),
              children: [SizedBox(height: 180)],
            ),
          ),
        ),
      );
      await t.tap(find.text('Details'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      final forward = height(t);
      expect(forward, inExclusiveRange(0, 1));
      await t.tap(find.text('Details'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(height(t), inExclusiveRange(0, forward));
      await t.tap(find.text('Details'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 160));
      expect(height(t), 1);
      expect(turns(t), .5);
      await t.tap(find.text('Details'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 200));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Enter Space focus and PageStorage match the SDK without duplicate toggles',
    (t) async {
      for (final owned in [false, true]) {
        final bucket = PageStorageBucket();
        late StateSetter change;
        var visible = true;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, set) {
                  change = set;
                  final tile = owned
                      ? const PaperExpansionTile(
                          key: PageStorageKey('scan-details'),
                          title: Text('Details'),
                          children: [Text('Stored body')],
                        )
                      : const ExpansionTile(
                          key: PageStorageKey('scan-details'),
                          title: Text('Details'),
                          children: [Text('Stored body')],
                        );
                  return PageStorage(
                    bucket: bucket,
                    child: visible ? tile : const SizedBox(),
                  );
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        final focus = FocusManager.instance.primaryFocus;
        expect(focus, isNot(FocusManager.instance.rootScope));
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(height(t), 1);
        expect(FocusManager.instance.primaryFocus, same(focus));
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        await t.pumpAndSettle();
        expect(height(t), 0);
        expect(find.text('Stored body'), findsNothing);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(height(t), 1);
        change(() => visible = false);
        await t.pump();
        change(() => visible = true);
        await t.pump();
        expect(height(t), 1);
        expect(find.text('Stored body'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      }
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'Android header semantics at both endpoints match the SDK node representation',
    (t) async {
      final handle = t.ensureSemantics();
      try {
        for (final open in [false, true]) {
          String? original;
          for (final owned in [false, true]) {
            final tile = owned
                ? const PaperExpansionTile(
                    title: Text('Details'),
                    children: [Text('Body')],
                  )
                : const ExpansionTile(
                    title: Text('Details'),
                    children: [Text('Body')],
                  );
            await t.pumpWidget(
              MaterialApp(
                theme: Paper.theme,
                home: Scaffold(body: tile),
              ),
            );
            await t.pumpAndSettle();
            if (open) {
              await t.tap(find.text('Details'));
              await t.pumpAndSettle();
            }
            final data = t
                .getSemantics(find.byType(ListTile))
                .getSemanticsData()
                .toString();
            if (!owned) {
              original = data;
            } else {
              expect(data, original);
            }
            await t.pumpWidget(const SizedBox());
          }
        }
        expect(t.takeException(), isNull);
      } finally {
        handle.dispose();
        await t.pump();
      }
    },
  );
}
