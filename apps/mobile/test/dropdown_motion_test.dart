import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/settings/default_settings_sheet.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'default_settings_widget_test.dart' show DefaultDraftLibrary;

class ProbeObserver extends NavigatorObserver {
  TransitionRoute<dynamic>? dropdown;
  Duration? poppedDuration;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) dropdown = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) {
      poppedDuration = route.reverseTransitionDuration;
    }
  }
}

void main() {
  for (final reduced in [false, true, null]) {
    testWidgets('actual reading preferences dropdown motion reduced=$reduced', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduced ?? false);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = DefaultDraftLibrary();
      final local = UiPreferences();
      final observer = ProbeObserver();
      await repo.initialize();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        local.dispose();
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          navigatorObservers: [observer],
          builder: (_, child) => PaperControlTheme(child: child!),
          home: Scaffold(
            body: DefaultSettingsSheet(
              repository: repo,
              local: local,
              video: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final field = find.byKey(const Key('default-reader-direction'));
      await Scrollable.ensureVisible(t.element(field), alignment: .5);
      await t.pumpAndSettle();
      await t.tap(field);
      await t.pump();
      final route = observer.dropdown!;
      debugPrint(
        'ACTUAL dropdown reduced=$reduced forward=${route.transitionDuration.inMilliseconds} reverse=${route.reverseTransitionDuration.inMilliseconds}',
      );
      if (reduced == null) {
        await t.pump(const Duration(milliseconds: 60));
        expect(route.animation!.value, inExclusiveRange(0, 1));
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        await t.pump();
        debugPrint(
          'ACTUAL live dropdown native=${t.platformDispatcher.accessibilityFeatures.disableAnimations} progress=${route.animation!.value}',
        );
        expect(route.animation!.value, 1);
      } else {
        expect(
          route.transitionDuration,
          Duration(milliseconds: reduced ? 0 : 240),
        );
        expect(
          route.reverseTransitionDuration,
          Duration(milliseconds: reduced ? 0 : 160),
        );
      }
    });
  }

  for (final reduced in [false, true]) {
    testWidgets('selection updates once before a full exit reduced=$reduced', (
      t,
    ) async {
      setReduced(t, reduced);
      final observer = ProbeObserver();
      var changes = 0;
      await host(t, observer, dropdown(onChanged: (_) => changes++));
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      final route = observer.dropdown!;
      await t.tap(find.text('two').hitTestable().last);
      await t.pump();
      expect(changes, 1);
      if (reduced) {
        expect(route.animation!.value, 0);
      } else {
        expect(route.animation!.status, AnimationStatus.reverse);
        expect(menuOpacity(t), 1);
        await t.pump(const Duration(milliseconds: 80));
        expect(route.animation!.value, closeTo(.5, .001));
        expect(menuOpacity(t), closeTo(.5, .001));
        await t.pump(const Duration(milliseconds: 80));
        expect(route.animation!.value, 0);
      }
      await t.pumpAndSettle();
      expect(menuFinder, findsNothing);
      expect(changes, 1);
    });
  }
  testWidgets(
    'live reduced motion completes the visible exit at its next frame',
    (t) async {
      setReduced(t, false);
      final observer = ProbeObserver();
      var changes = 0;
      await host(t, observer, dropdown(onChanged: (_) => changes++));
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      final route = observer.dropdown!;
      await t.tap(find.text('two').hitTestable().last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(route.animation!.value, inExclusiveRange(0, 1));
      expect(menuOpacity(t), inExclusiveRange(0, 1));
      expect(changes, 1);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      expect(route.animation!.value, 0);
      expect(changes, 1);
      await t.pumpAndSettle();
      expect(menuFinder, findsNothing);
    },
  );
  testWidgets('exit reads reduced motion enabled after the menu opened', (
    t,
  ) async {
    setReduced(t, false);
    final observer = ProbeObserver();
    await host(t, observer, dropdown());
    await t.tap(find.byKey(const Key('dropdown')));
    await t.pumpAndSettle();
    final route = observer.dropdown!;
    t.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    await t.pump();
    Navigator.of(t.element(menuFinder)).pop();
    await t.pump();
    expect(observer.poppedDuration, Duration.zero);
    expect(route.animation!.value, 0);
    await t.pumpAndSettle();
    expect(menuFinder, findsNothing);
  });
  testWidgets(
    'real null selection differs from barrier and Escape cancellation',
    (t) async {
      final observer = ProbeObserver();
      final changes = <int?>[];
      await host(
        t,
        observer,
        PaperDropdownButton<int>(
          key: const Key('dropdown'),
          value: 1,
          items: const [
            DropdownMenuItem(value: 1, child: Text('one')),
            DropdownMenuItem<int>(value: null, child: Text('unset')),
          ],
          onChanged: changes.add,
        ),
      );
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(changes, isEmpty);
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(changes, isEmpty);
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      await t.tap(find.text('unset').hitTestable().last);
      await t.pump();
      expect(changes, [null]);
      await t.pumpAndSettle();
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'long menu aligns its selection and keyboard skips disabled rows reduced=$reduced',
      (t) async {
        setReduced(t, reduced);
        final observer = ProbeObserver();
        int? selected;
        await host(
          t,
          observer,
          PaperDropdownButton<int>(
            key: const Key('dropdown'),
            value: 28,
            menuMaxHeight: 160,
            items: [
              for (var n = 0; n < 40; n++)
                DropdownMenuItem(
                  value: n,
                  enabled: n != 29,
                  child: Text('row $n'),
                ),
            ],
            onChanged: (v) => selected = v,
          ),
        );
        await t.tap(find.byKey(const Key('dropdown')));
        await t.pumpAndSettle();
        expect(find.text('row 28').hitTestable().last, findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
        expect(find.text('row 30').hitTestable(), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        expect(selected, 30);
        await t.pumpAndSettle();
        expect(menuFinder, findsNothing);
      },
    );
  }
  testWidgets(
    'live reduce completes requested focus scrolling without a later drift',
    (t) async {
      final previousStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy = previousStrategy,
      );
      setReduced(t, false);
      final observer = ProbeObserver();
      await host(
        t,
        observer,
        PaperDropdownButton<int>(
          key: const Key('dropdown'),
          value: 28,
          menuMaxHeight: 160,
          items: [
            for (var n = 0; n < 40; n++)
              DropdownMenuItem(
                value: n,
                enabled: n != 29,
                child: Text('row $n'),
              ),
          ],
          onChanged: (_) {},
        ),
      );
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      final scroll = t.state<ScrollableState>(
        find.descendant(of: menuFinder, matching: find.byType(Scrollable)),
      );
      Focus.of(t.element(find.text('row 27'))).requestFocus();
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      final inFlightOffset = scroll.position.pixels;
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      expect(find.text('row 27').hitTestable(), findsOneWidget);
      final offset = scroll.position.pixels;
      expect(offset, lessThan(inFlightOffset));
      await t.pump(const Duration(milliseconds: 200));
      expect(scroll.position.pixels, offset);
    },
  );
  testWidgets(
    'form validation save reset and changed initial value retain their contract',
    (t) async {
      final observer = ProbeObserver();
      final form = GlobalKey<FormState>();
      final field = GlobalKey<FormFieldState<int>>();
      int? saved;
      final changes = <int?>[];
      var initial = 1;
      late StateSetter update;
      await host(
        t,
        observer,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return Form(
              key: form,
              child: PaperDropdownButtonFormField<int>(
                key: field,
                initialValue: initial,
                decoration: const InputDecoration(labelText: 'choice'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('one')),
                  DropdownMenuItem(value: 2, child: Text('two')),
                ],
                validator: (v) => v == 2 ? 'choose one' : null,
                onSaved: (v) => saved = v,
                onChanged: changes.add,
              ),
            );
          },
        ),
      );
      await t.tap(find.byKey(field));
      await t.pumpAndSettle();
      await t.tap(find.text('two').hitTestable().last);
      await t.pumpAndSettle();
      expect(field.currentState!.value, 2);
      expect(changes, [2]);
      expect(form.currentState!.validate(), false);
      await t.pump();
      expect(find.text('choose one'), findsOneWidget);
      form.currentState!.reset();
      await t.pumpAndSettle();
      expect(field.currentState!.value, 1);
      expect(changes, [2, 1]);
      expect(find.text('choose one'), findsNothing);
      form.currentState!.save();
      expect(saved, 1);
      update(() => initial = 2);
      await t.pump();
      expect(field.currentState!.value, 2);
      expect(changes, [2, 1]);
    },
  );
  testWidgets(
    'disabled empty and invalidated dropdowns do not invoke callbacks',
    (t) async {
      final observer = ProbeObserver();
      var enabled = false, empty = false, changes = 0;
      late StateSetter update;
      await host(
        t,
        observer,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return PaperDropdownButton<int>(
              key: const Key('dropdown'),
              value: empty ? null : 1,
              items: empty
                  ? []
                  : const [
                      DropdownMenuItem(value: 1, child: Text('one')),
                      DropdownMenuItem(value: 2, child: Text('two')),
                    ],
              onChanged: enabled ? (_) => changes++ : null,
            );
          },
        ),
      );
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      expect(observer.dropdown, isNull);
      update(() {
        enabled = true;
        empty = true;
      });
      await t.pump();
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      expect(observer.dropdown, isNull);
      update(() => empty = false);
      await t.pump();
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      expect(menuFinder, findsOneWidget);
      update(() => enabled = false);
      await t.pumpAndSettle();
      expect(menuFinder, findsNothing);
      expect(changes, 0);
    },
  );
  testWidgets(
    'removing the anchor or rotating while open closes without a stale callback',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final observer = ProbeObserver();
      var show = true, changes = 0;
      late StateSetter update;
      await host(
        t,
        observer,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return show
                ? dropdown(onChanged: (_) => changes++)
                : const SizedBox();
          },
        ),
      );
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(844, 390);
      await t.pumpAndSettle();
      expect(menuFinder, findsNothing);
      expect(changes, 0);
      await t.tap(find.byKey(const Key('dropdown')));
      await t.pumpAndSettle();
      update(() => show = false);
      await t.pumpAndSettle();
      expect(menuFinder, findsNothing);
      expect(changes, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'resting button and menu pixels match SDK in 16 form theme direction and anchor combinations',
    (t) async {
      var comparisons = 0;
      for (final form in [false, true]) {
        for (final dark in [false, true]) {
          for (final rtl in [false, true]) {
            for (final bottom in [false, true]) {
              List<int>? before;
              Size? size;
              for (final original in [true, false]) {
                final items = const [
                  DropdownMenuItem(value: 1, child: Text('one')),
                  DropdownMenuItem(value: 2, child: Text('chosen')),
                  DropdownMenuItem(
                    value: 3,
                    enabled: false,
                    child: Text('disabled'),
                  ),
                ];
                final Widget button;
                if (form) {
                  button = original
                      ? DropdownButtonFormField<int>(
                          key: const Key('dropdown'),
                          initialValue: 2,
                          items: items,
                          decoration: const InputDecoration(
                            labelText: 'choice',
                            filled: true,
                          ),
                          onChanged: (_) {},
                        )
                      : PaperDropdownButtonFormField<int>(
                          key: const Key('dropdown'),
                          initialValue: 2,
                          items: items,
                          decoration: const InputDecoration(
                            labelText: 'choice',
                            filled: true,
                          ),
                          onChanged: (_) {},
                        );
                } else {
                  button = original
                      ? DropdownButton<int>(
                          key: const Key('dropdown'),
                          value: 2,
                          items: items,
                          onChanged: (_) {},
                        )
                      : PaperDropdownButton<int>(
                          key: const Key('dropdown'),
                          value: 2,
                          items: items,
                          onChanged: (_) {},
                        );
                }
                await t.pumpWidget(
                  RepaintBoundary(
                    key: const Key('canvas'),
                    child: MaterialApp(
                      theme: dark ? Paper.darkTheme : Paper.theme,
                      builder: (_, child) => Directionality(
                        textDirection: rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: PaperControlTheme(child: child!),
                      ),
                      home: Scaffold(
                        body: Align(
                          alignment: bottom
                              ? Alignment.bottomLeft
                              : Alignment.topRight,
                          child: SizedBox(width: 240, child: button),
                        ),
                      ),
                    ),
                  ),
                );
                await t.pumpAndSettle();
                await t.tap(find.byKey(const Key('dropdown')));
                await t.pumpAndSettle();
                final boundary = t.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('canvas')),
                );
                final pixels = (await t.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final data = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List().toList();
                  image.dispose();
                  return data;
                }))!;
                if (original) {
                  before = pixels;
                  size = boundary.size;
                } else {
                  expect(boundary.size, size);
                  expect(
                    pixels,
                    before,
                    reason: 'form=$form dark=$dark rtl=$rtl bottom=$bottom',
                  );
                  comparisons++;
                }
                await t.pumpWidget(const SizedBox());
                await t.pump();
              }
            }
          }
        }
      }
      expect(comparisons, 16);
      expect(t.takeException(), isNull);
    },
  );
}

void setReduced(WidgetTester t, bool value) {
  t.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: value);
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> host(WidgetTester t, ProbeObserver observer, Widget child) async {
  await t.pumpWidget(
    MaterialApp(
      theme: Paper.theme,
      navigatorObservers: [observer],
      builder: (_, child) => PaperControlTheme(child: child!),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await t.pumpAndSettle();
}

Widget dropdown({ValueChanged<int?>? onChanged}) => PaperDropdownButton<int>(
  key: const Key('dropdown'),
  value: 1,
  items: const [
    DropdownMenuItem(value: 1, child: Text('one')),
    DropdownMenuItem(value: 2, child: Text('two')),
  ],
  onChanged: onChanged ?? (_) {},
);
Finder get menuFinder => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.role == ui.SemanticsRole.menu,
);
double menuOpacity(WidgetTester t) => t
    .widget<FadeTransition>(
      find
          .ancestor(of: menuFinder, matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;
