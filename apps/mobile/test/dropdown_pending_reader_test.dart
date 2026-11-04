import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/ui/paper.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

class ReaderDropdownObserver extends NavigatorObserver {
  TransitionRoute<dynamic>? dropdown;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) dropdown = route;
  }
}

void main() {
  testWidgets(
    'actual reader save disables its field without cutting the popped menu exit',
    (t) async {
      final repo = AssetReadingLibrary();
      // This scenario exercises an existing horizontal preference.
      repo.prefs['p0'] = const ReaderPreferences(mode: ReaderMode.horizontal);
      repo.preferenceStarted = Completer<void>();
      repo.preferenceRelease = Completer<void>();
      final observer = ReaderDropdownObserver();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() async {
        if (!repo.preferenceRelease!.isCompleted) {
          repo.preferenceRelease!.complete();
        }
        await t.pump();
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          navigatorObservers: [observer],
          builder: (_, child) => PaperControlTheme(child: child!),
          home: PackReaderPage(
            repository: repo,
            entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
            editTags: (_) async {},
          ),
        ),
      );
      PackReaderPageState state() =>
          t.state<PackReaderPageState>(find.byType(PackReaderPage));
      for (
        var n = 0;
        n < 150 && (!state().session.opened || state().session.busy);
        n++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 3)),
        );
        await t.pump(const Duration(milliseconds: 30));
        expect(t.takeException(), isNull);
      }
      expect(state().session.opened, isTrue);
      expect(state().session.busy, isFalse);
      await t.tap(find.byTooltip('阅读设置'));
      await t.pumpAndSettle();
      await t.tap(find.byType(PaperDropdownButtonFormField<ReaderDirection>));
      await t.pumpAndSettle();
      final route = observer.dropdown!;
      final animation = route.animation!;
      await t.tap(find.text('从右向左').hitTestable().last);
      await t.pump(); // Start the exit ticker even when the write began synchronously.
      for (var n = 0; n < 20 && !repo.preferenceStarted!.isCompleted; n++) {
        await t.pump();
      }
      expect(repo.preferenceStarted!.isCompleted, isTrue);
      expect(state().session.busy, isTrue);
      final menu = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.role == ui.SemanticsRole.menu,
      );
      expect(menu, findsOneWidget);
      double opacity() => t
          .widget<FadeTransition>(
            find
                .ancestor(of: menu, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;
      debugPrint(
        'ACTUAL pending reader busy=${state().session.busy} routeActive=${route.isActive} progress=${animation.value} opacity=${opacity()}',
      );
      expect(route.isActive, isFalse);
      expect(animation.value, 1);
      expect(opacity(), 1);
      await t.pump(const Duration(milliseconds: 80));
      expect(state().session.busy, isTrue);
      expect(opacity(), closeTo(.5, .001));
      await t.pump(const Duration(milliseconds: 80));
      expect(animation.value, 0);
      repo.preferenceRelease!.complete();
      await t.pumpAndSettle();
      expect(state().session.busy, isFalse);
      expect(state().session.preferences.direction, ReaderDirection.rtl);
      expect(repo.prefs['p0']!.direction, ReaderDirection.rtl);
      expect(t.takeException(), isNull);
    },
  );
}
