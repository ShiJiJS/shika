import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/ui/player.dart';

import 'player_lifecycle_test.dart' as fixture;

void main() {
  for (final variant in [
    (fullscreen: false, reduced: false),
    (fullscreen: true, reduced: false),
    (fullscreen: false, reduced: true),
    (fullscreen: true, reduced: true),
  ]) {
    final fullscreen = variant.fullscreen, reduced = variant.reduced;
    testWidgets(
      'player motion preserves playback and follows system reduction; $variant',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: reduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final original = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = fixture.ReadyVideo();
        final controller = VideoPlayerController.networkUrl(
          Uri.parse('https://fixture.invalid/motion.mp4'),
        );
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await controller.dispose();
          VideoPlayerPlatform.instance = original;
        });
        await t.runAsync(() async {
          await controller.initialize();
          await controller.play();
        });
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: PlayerSurface(
                  controller: controller,
                  name: 'motion',
                  inlineControls: !fullscreen,
                  fullscreen: fullscreen,
                  footer: const Text(
                    'motion footer',
                    key: Key('motion-footer'),
                  ),
                ),
              ),
            ),
          ),
        );
        final control = find.byKey(const Key('playback-controls'));
        expect(control, findsOneWidget);
        final opacity = find
            .ancestor(of: control, matching: find.byType(AnimatedOpacity))
            .first;
        final fade = find
            .descendant(of: opacity, matching: find.byType(FadeTransition))
            .first;
        final initial = t.getTopLeft(find.byKey(const Key('motion-footer'))).dy;
        expect(t.widget<FadeTransition>(fade).opacity.value, 1);
        if (fullscreen) {
          await t.tap(find.byKey(const Key('video-gesture-surface')));
          await t.pump();
        } else {
          await t.pump(const Duration(seconds: 4));
        }
        if (!reduced) {
          expect(t.widget<FadeTransition>(fade).opacity.value, 1);
          await t.pump(const Duration(milliseconds: 80));
          expect(
            t.widget<FadeTransition>(fade).opacity.value,
            inExclusiveRange(0, 1),
          );
          await t.pump(const Duration(milliseconds: 80));
        }
        expect(
          t.widget<FadeTransition>(fade).opacity.value,
          0,
          reason: 'Reduce animations must apply hidden state on the first rendered frame',
        );
        expect(
          t.getTopLeft(find.byKey(const Key('motion-footer'))).dy,
          closeTo(initial + 34, .01),
        );
        if (fullscreen) {
          final exit = find.byKey(const Key('fullscreen-exit'));
          final outer = find
              .ancestor(of: exit, matching: find.byType(AnimatedOpacity))
              .first;
          final transition = find
              .descendant(of: outer, matching: find.byType(FadeTransition))
              .first;
          expect(t.widget<FadeTransition>(transition).opacity.value, 0);
        }
        expect(controller.value.isPlaying, isTrue);
      },
    );
  }
}
