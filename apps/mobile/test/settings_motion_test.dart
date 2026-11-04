import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/main.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/preferences.dart';

void main() {
  testWidgets(
    'visible Paper colors follow the app theme without a halfway jump',
    (t) async {
      final repo = DemoLibraryRepository(
        MemoryStateStore(),
        latency: Duration.zero,
      );
      await repo.initialize();
      final preferences = UiPreferences();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        preferences.dispose();
      });
      await t.pumpWidget(
        ShikaApp(repository: repo, preferences: preferences),
      );
      await t.pumpAndSettle();
      await preferences.setDark(true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 70));
      final context = t.element(find.byType(Scaffold).first);
      final paint = Paper.of(context).background;
      expect(paint, Theme.of(context).scaffoldBackgroundColor);
      expect(
        paint,
        isNot(anyOf(Paper.background, Paper.darkTheme.scaffoldBackgroundColor)),
      );
      final explicit = t
          .widget<Scaffold>(find.byType(Scaffold).first)
          .backgroundColor;
      if (explicit != null) expect(explicit, paint);
      expect(t.takeException(), isNull);
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'actual app theme reaches target at ${reduced ? 0 : 140}ms while route draft focus and scroll survive',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final repo = DemoLibraryRepository(
          MemoryStateStore(),
          latency: Duration.zero,
        );
        await repo.initialize();
        final preferences = UiPreferences();
        final text = TextEditingController(text: 'retained draft');
        final focus = FocusNode();
        final scroll = ScrollController();
        final key = GlobalKey<ScaffoldState>();
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
          preferences.dispose();
          text.dispose();
          focus.dispose();
          scroll.dispose();
        });
        await t.pumpWidget(
          ShikaApp(repository: repo, preferences: preferences),
        );
        await t.pumpAndSettle();
        final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
        navigator.push<void>(
          PaperPageRoute(
            builder: (_) => Scaffold(
              key: key,
              body: Column(
                children: [
                  TextField(controller: text, focusNode: focus),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      children: List.generate(
                        40,
                        (i) => SizedBox(height: 48, child: Text('row $i')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        focus.requestFocus();
        await t.pump();
        scroll.jumpTo(240);
        await t.pump();
        final state = key.currentState;
        final initial = Theme.of(key.currentContext!).scaffoldBackgroundColor;
        await preferences.setDark(true);
        await t.pump();
        if (!reduced) {
          await t.pump(const Duration(milliseconds: 70));
          expect(
            Theme.of(key.currentContext!).scaffoldBackgroundColor,
            isNot(anyOf(initial, Paper.darkTheme.scaffoldBackgroundColor)),
          );
          await t.pump(const Duration(milliseconds: 70));
        }
        expect(
          Theme.of(key.currentContext!).scaffoldBackgroundColor,
          Paper.darkTheme.scaffoldBackgroundColor,
        );
        expect(key.currentState, same(state));
        expect(
          t.state<NavigatorState>(find.byType(Navigator).first),
          same(navigator),
        );
        expect(text.text, 'retained draft');
        expect(focus.hasFocus, isTrue);
        expect(scroll.offset, 240);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'actual app reduced preference completes an already running theme transition before next paint',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures();
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = DemoLibraryRepository(
        MemoryStateStore(),
        latency: Duration.zero,
      );
      await repo.initialize();
      final preferences = UiPreferences();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        preferences.dispose();
      });
      await t.pumpWidget(
        ShikaApp(repository: repo, preferences: preferences),
      );
      await t.pumpAndSettle();
      Color color() =>
          Theme.of(t.element(find.byType(Scaffold).first))
              .scaffoldBackgroundColor;
      await preferences.setDark(true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(color(), isNot(Paper.darkTheme.scaffoldBackgroundColor));
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await t.pump();
      expect(color(), Paper.darkTheme.scaffoldBackgroundColor);
      expect(t.takeException(), isNull);
    },
  );
  for (final selected in [false, true]) {
    testWidgets(
      'theme color reaches an unchanged chip without a second selection tween selected=$selected',
      (t) async {
        var dark = false;
        late StateSetter change;
        var callbacks = 0;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (context, set) {
              change = set;
              return MaterialApp(
                theme: Paper.theme,
                darkTheme: Paper.darkTheme,
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                themeAnimationDuration: Duration.zero,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => PaperChoiceChip(
                      label: const Text('chip'),
                      selected: selected,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      onSelected: (_) => callbacks++,
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await t.pumpAndSettle();
        final before = t.state(find.byType(RawChip));
        change(() => dark = true);
        await t.pump();
        final raw = t.element(find.byType(RawChip));
        final ink = t.widget<Ink>(
          find.descendant(of: find.byType(RawChip), matching: find.byType(Ink)),
        );
        expect(
          (ink.decoration as ShapeDecoration).color,
          selected
              ? Theme.of(raw).colorScheme.primary
              : Theme.of(raw).colorScheme.surface,
        );
        expect(t.state(find.byType(RawChip)), same(before));
        expect(callbacks, 0);
        expect(t.takeException(), isNull);
      },
    );
  }
}
