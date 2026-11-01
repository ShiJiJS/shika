import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

void main() {
  for (final reduced in [false, true]) {
    testWidgets('actual library reader entry follows reduced motion=$reduced', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduced);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final original = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final repo = AssetReadingLibrary();
      await repo.initialize();
      final preferences = UiPreferences();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        repo.dispose();
        preferences.dispose();
        VideoPlayerPlatform.instance = original;
      });
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('kind-pack')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pack-tile-p1')));
      for (
        var i = 0;
        i < 40 && find.byType(PackReaderPage).evaluate().isEmpty;
        i++
      ) {
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
        await t.pump();
      }
      expect(find.byType(PackReaderPage), findsOneWidget);
      final route = ModalRoute.of(t.element(find.byType(PackReaderPage)))!;
      expect(
        route.transitionDuration,
        Duration(milliseconds: reduced ? 0 : 240),
      );
      expect(
        route.reverseTransitionDuration,
        Duration(milliseconds: reduced ? 0 : 160),
      );
      if (reduced) {
        expect(route.animation!.value, 1);
        expect(route.animation!.status, AnimationStatus.completed);
      } else {
        expect(route.animation!.value, 0);
        await t.pump(const Duration(milliseconds: 120));
        expect(route.animation!.value, inExclusiveRange(0, 1));
        await t.pump(const Duration(milliseconds: 200));
        expect(route.animation!.status, AnimationStatus.completed);
      }
      expect(t.takeException(), isNull);
    });
  }
  for (final fade in [false, true]) {
    for (final enteredReduced in [false, true]) {
      for (final returnedReduced in [false, true]) {
        testWidgets(
          'page retains source and result; fade=$fade, entry=$enteredReduced, return=$returnedReduced',
          (t) async {
            t.platformDispatcher.accessibilityFeaturesTestValue =
                FakeAccessibilityFeatures(disableAnimations: enteredReduced);
            addTearDown(
              t.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
            final source = TextEditingController(text: '原来源搜索');
            addTearDown(source.dispose);
            late PaperPageRoute<String> route;
            String? returned;
            Widget page(BuildContext context) => Scaffold(
              body: TextButton(
                key: const Key('close-page'),
                onPressed: () => Navigator.pop(context, 'same-target'),
                child: const Text('返回来源'),
              ),
            );
            await t.pumpWidget(
              MaterialApp(
                theme: Paper.theme,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Column(
                      children: [
                        TextField(controller: source),
                        TextButton(
                          key: const Key('open-page'),
                          onPressed: () {
                            route = fade
                                ? PaperPageRoute<String>.fade(builder: page)
                                : PaperPageRoute<String>(builder: page);
                            unawaited(
                              Navigator.of(context)
                                  .push(route)
                                  .then((v) => returned = v),
                            );
                          },
                          child: const Text('打开内容'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await t.tap(find.byKey(const Key('open-page')));
            await t.pump();
            expect(route.animation!.value, enteredReduced ? 1 : 0);
            if (!enteredReduced) {
              await t.pump(const Duration(milliseconds: 120));
              expect(route.animation!.value, inExclusiveRange(0, 1));
              await t.pump(const Duration(milliseconds: 136));
            }
            expect(route.animation!.status, AnimationStatus.completed);
            t.platformDispatcher.accessibilityFeaturesTestValue =
                FakeAccessibilityFeatures(disableAnimations: returnedReduced);
            await t.pump();
            expect(
              route.reverseTransitionDuration,
              Duration(milliseconds: returnedReduced ? 0 : 160),
            );
            await t.tap(find.byKey(const Key('close-page')));
            expect(route.animation!.value, returnedReduced ? 0 : 1);
            await t.pump();
            if (!returnedReduced) {
              await t.pump(const Duration(milliseconds: 80));
              expect(route.animation!.value, inExclusiveRange(0, 1));
              await t.pump(const Duration(milliseconds: 96));
            }
            await t.pump();
            expect(returned, 'same-target');
            expect(find.byKey(const Key('close-page')), findsNothing);
            expect(source.text, '原来源搜索');
            expect(find.byKey(const Key('open-page')), findsOneWidget);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
}
