import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary;

class MenuObserver extends NavigatorObserver {
  TransitionRoute<dynamic>? menu;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) menu = route;
  }
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets('actual workspace menu uses 240/160 or zero reduced=$reduced', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduced);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = WorkspaceLibrary();
      await repo.initialize();
      final preferences = UiPreferences();
      final observer = MenuObserver();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        preferences.dispose();
      });
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          navigatorObservers: [observer],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('更多'));
      await t.pump();
      final route = observer.menu!;
      debugPrint(
        'ACTUAL workspace reduced=$reduced forward=${route.transitionDuration.inMilliseconds} reverse=${route.reverseTransitionDuration.inMilliseconds}',
      );
      expect(
        route.transitionDuration,
        Duration(milliseconds: reduced ? 0 : 240),
      );
      expect(
        route.reverseTransitionDuration,
        Duration(milliseconds: reduced ? 0 : 160),
      );
    });
  }
  testWidgets(
    'actual workspace open menu completes when reduced is enabled mid-flight',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures();
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = WorkspaceLibrary();
      await repo.initialize();
      final preferences = UiPreferences();
      final observer = MenuObserver();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        preferences.dispose();
      });
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          navigatorObservers: [observer],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('更多'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      final route = observer.menu!;
      expect(route.animation!.value, inExclusiveRange(0, 1));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      debugPrint(
        'ACTUAL live reduced menu animation=${route.animation!.value}',
      );
      expect(route.animation!.value, 1);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'selection is immediate and exit finishes at 160 or zero reduced=$reduced',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final observer = MenuObserver();
        var selected = 0, cancelled = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            navigatorObservers: [observer],
            home: Scaffold(
              body: PaperMenuButton<String>(
                tooltip: 'menu',
                onSelected: (_) => selected++,
                onCanceled: () => cancelled++,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'one', child: Text('choose')),
                ],
              ),
            ),
          ),
        );
        await t.tap(find.byTooltip('menu'));
        await t.pumpAndSettle();
        final route = observer.menu!;
        var complete = false;
        route.completed.then((_) => complete = true);
        await t.tap(find.text('choose'));
        await t.pump();
        expect(selected, 1);
        expect(cancelled, 0);
        if (!reduced) {
          expect(complete, isFalse);
          await t.pump(const Duration(milliseconds: 160));
          expect(route.animation!.value, 0);
          // The visual endpoint is exact; Flutter finalizes the route on the
          // following ticker sample (simulation completion uses elapsed > end).
          await t.pump(const Duration(microseconds: 1));
        }
        await t.pump();
        expect(complete, isTrue);
        expect(find.text('choose'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'live reduced also completes an exiting menu without repeating its action',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures();
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final observer = MenuObserver();
      var selected = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          navigatorObservers: [observer],
          home: Scaffold(
            body: PaperMenuButton<String>(
              tooltip: 'menu',
              onSelected: (_) => selected++,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'one', child: Text('choose')),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('menu'));
      await t.pumpAndSettle();
      final route = observer.menu!;
      var complete = false;
      route.completed.then((_) => complete = true);
      await t.tap(find.text('choose'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(selected, 1);
      expect(complete, isFalse);
      expect(route.animation!.value, inExclusiveRange(0, 1));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      await t.pump();
      expect(complete, isTrue);
      expect(selected, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'keyboard skips disabled entries, selects once and Escape only cancels',
    (t) async {
      var selected = 0, cancelled = 0, opened = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: PaperMenuButton<String>(
              tooltip: 'menu',
              onOpened: () => opened++,
              onSelected: (_) => selected++,
              onCanceled: () => cancelled++,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'disabled',
                  enabled: false,
                  child: Text('disabled'),
                ),
                const PopupMenuItem(value: 'one', child: Text('choose')),
              ],
            ),
          ),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(opened, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(selected, 1);
      expect(cancelled, 0);
      await t.tap(find.byTooltip('menu'));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(opened, 2);
      expect(selected, 1);
      expect(cancelled, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'removing the anchor and resizing an open menu keeps close safe',
    (t) async {
      var visible = true, selected = 0;
      late StateSetter change;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                change = set;
                return visible
                    ? PaperMenuButton<String>(
                        tooltip: 'menu',
                        onSelected: (_) => selected++,
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'one',
                            child: Text('choose'),
                          ),
                        ],
                      )
                    : const SizedBox();
              },
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('menu'));
      await t.pumpAndSettle();
      change(() => visible = false);
      await t.pump();
      t.view.physicalSize = const Size(600, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pump();
      await t.tap(find.text('choose'));
      await t.pumpAndSettle();
      expect(selected, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'disabled and empty buttons do not open or invoke a menu action',
    (t) async {
      var builds = 0, opened = 0;
      var enabled = false;
      late StateSetter change;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                change = set;
                return PaperMenuButton<String>(
                  tooltip: 'menu',
                  enabled: enabled,
                  onOpened: () => opened++,
                  itemBuilder: (_) {
                    builds++;
                    return [];
                  },
                );
              },
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('menu'));
      await t.pumpAndSettle();
      expect(builds, 0);
      expect(opened, 0);
      change(() => enabled = true);
      await t.pump();
      await t.tap(find.byTooltip('menu'));
      await t.pumpAndSettle();
      expect(builds, 1);
      expect(opened, 0);
    },
  );
  testWidgets(
    'resting menu and button pixels match the original in 16 theme direction anchor and button combinations',
    (t) async {
      var count = 0;
      for (final dark in [false, true]) {
        for (final rtl in [false, true]) {
          for (final bottom in [false, true]) {
            for (final childButton in [false, true]) {
              List<int>? originalPixels;
              Size? originalSize;
              for (final original in [true, false]) {
                final entries = <PopupMenuEntry<int>>[
                  const PopupMenuItem(value: 1, child: Text('first')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 2, child: Text('chosen item')),
                ];
                final button = original
                    ? PopupMenuButton<int>(
                        tooltip: 'menu',
                        initialValue: 2,
                        position: childButton
                            ? PopupMenuPosition.under
                            : PopupMenuPosition.over,
                        child: childButton
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('chosen item'),
                              )
                            : null,
                        itemBuilder: (_) => entries,
                      )
                    : PaperMenuButton<int>(
                        tooltip: 'menu',
                        initialValue: 2,
                        position: childButton
                            ? PopupMenuPosition.under
                            : PopupMenuPosition.over,
                        child: childButton
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('chosen item'),
                              )
                            : null,
                        itemBuilder: (_) => entries,
                      );
                await t.pumpWidget(
                  RepaintBoundary(
                    key: const Key('canvas'),
                    child: MaterialApp(
                      theme: dark ? Paper.darkTheme : Paper.theme,
                      builder: (context, child) => Directionality(
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
                          child: button,
                        ),
                      ),
                    ),
                  ),
                );
                await t.pumpAndSettle();
                await t.tap(find.byTooltip('menu'));
                await t.pumpAndSettle();
                final boundary = t.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('canvas')),
                );
                final pixels = (await t.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final bytes = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List().toList();
                  image.dispose();
                  return bytes;
                }))!;
                if (original) {
                  originalPixels = pixels;
                  originalSize = boundary.size;
                } else {
                  expect(boundary.size, originalSize);
                  expect(
                    pixels,
                    originalPixels,
                    reason:
                        'dark=$dark rtl=$rtl bottom=$bottom child=$childButton',
                  );
                  count++;
                }
                await t.pumpWidget(const SizedBox());
                await t.pump();
              }
            }
          }
        }
      }
      expect(count, 16);
      expect(t.takeException(), isNull);
    },
  );
}
