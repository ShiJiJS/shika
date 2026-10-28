import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

Future<Map<String, dynamic>> host(
  String action, {
  String? name,
  bool? reduced,
  Offset? point,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://10.0.2.2:8778/actions'),
    );
    request.headers.set('X-Fixture-Key', 'native-motion-owned-only');
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(
      jsonEncode({
        'action': action,
        'name': name,
        'reduced': reduced,
        if (point != null) 'point': [point.dx.round(), point.dy.round()],
      }),
    );
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(const Duration(seconds: 35));
    expect(response.statusCode, 200);
    return Map<String, dynamic>.from(
      jsonDecode(await response.transform(utf8.decoder).join()) as Map,
    );
  } finally {
    client.close(force: true);
  }
}

/// Reads the production widgets/render animations after actual device frames.
/// No tester calls, fake clock, or accessibility overrides run in this callback.
class MotionProbe {
  MotionProbe(this.targets, this.footer);
  final Map<String, ({Element target, Element fade})> targets;
  final RenderBox? footer;
  final samples = <Map<String, dynamic>>[];
  Map<String, dynamic>? baseline;
  Duration? start;
  bool done = false;

  void frame(Duration stamp) {
    if (done ||
        targets.values.any((e) => !e.target.mounted || !e.fade.mounted)) {
      return;
    }
    final values = {
      for (final e in targets.entries)
        e.key: {
          'target': (e.value.target.widget as AnimatedOpacity).opacity,
          'duration_us': (e.value.target.widget as AnimatedOpacity)
              .duration
              .inMicroseconds,
          'opacity': (e.value.fade.widget as FadeTransition).opacity.value,
        },
    };
    final sample = <String, dynamic>{
      'frame_us': stamp.inMicroseconds,
      'values': values,
      if (footer?.attached == true)
        'footer_y': footer!.localToGlobal(Offset.zero).dy,
    };
    if (values['controls']!['target'] == 1 && start == null) {
      baseline = sample;
      return;
    }
    start ??= stamp;
    sample['elapsed_us'] = (stamp - start!).inMicroseconds;
    samples.add(sample);
    done =
        (stamp - start!).inMilliseconds >= 350 &&
        values.values.every((v) => v['opacity'] == 0);
  }

  Map<String, dynamic> verify(bool reduced) {
    expect(done, isTrue);
    expect(samples, isNotEmpty);
    for (final key in targets.keys) {
      final values = samples
          .map((e) => (e['values'] as Map)[key] as Map)
          .toList();
      expect(
        values.every((v) => v['duration_us'] == (reduced ? 0 : 160000)),
        isTrue,
      );
      expect(values.first['opacity'], reduced ? 0 : 1);
      expect(values.last['opacity'], 0);
      if (!reduced) {
        expect(
          values.any(
            (v) => (v['opacity'] as double) > 0 && (v['opacity'] as double) < 1,
          ),
          isTrue,
        );
      }
    }
    if (footer != null) {
      expect(baseline, isNotNull);
      final before = baseline!['footer_y'] as double,
          end = samples.last['footer_y'] as double;
      expect(end - before, closeTo(34, .5));
      if (reduced) expect(samples.first['footer_y'], closeTo(end, .5));
    }
    return {'baseline': baseline, 'frames': samples};
  }
}

class NativeMotionLifecycle with WidgetsBindingObserver {
  final events = <Map<String, dynamic>>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    events.add({'time': DateTime.now().toIso8601String(), 'state': state.name});
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets(
    'real Android reduce animations reaches video controls without injection',
    (t) async {
      expect(kProfileMode, isTrue);
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8777);
      final preferences = UiPreferences(
        preloadAdjacent: false,
        videoOrder: PlayOrder.sequential,
      );
      final cases = <Map<String, dynamic>>[];
      final result = <String, dynamic>{
        'profile_entry': true,
        'normal_release_acceptance': false,
        'system_accessibility_injected': false,
        'audio_playback_acceptance': false,
        'cases': cases,
      };
      final lifecycle = NativeMotionLifecycle();
      WidgetsBinding.instance.addObserver(lifecycle);
      result['lifecycle'] = lifecycle.events;
      binding.reportData = {'native_motion': result};
      Map<String, dynamic> nativeState() => {
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'surfaces': t
            .widgetList<PlayerSurface>(find.byType(PlayerSurface))
            .map(
              (w) => {
                'controller': identityHashCode(w.controller),
                'initialized': w.controller.value.isInitialized,
                'playing': w.controller.value.isPlaying,
                'error': w.controller.value.errorDescription,
                'fullscreen': w.fullscreen,
              },
            )
            .toList(),
        'texts': t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .toList(),
      };
      MotionProbe? active;
      var observing = true;
      void frame(Duration _) {
        if (!observing) return;
        active?.frame(SchedulerBinding.instance.currentSystemFrameTimeStamp);
        WidgetsBinding.instance.addPostFrameCallback(frame);
      }

      WidgetsBinding.instance.addPostFrameCallback(frame);
      VideoPlayerController? isolated;
      addTearDown(() async {
        if (result['complete'] != true) {
          result['terminal_state'] = nativeState();
          await host('failure', name: 'terminal');
        }
        WidgetsBinding.instance.removeObserver(lifecycle);
        observing = false;
        active = null;
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await isolated?.dispose();
        repo.dispose();
        preferences.dispose();
        await configureApplicationWindow();
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      });
      Future<void> until(
        bool Function() ready,
        String why, {
        int seconds = 35,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready()) {
          if (DateTime.now().isAfter(end)) {
            result['failure'] = {
              'waiting_for': why,
              'texts': t
                  .widgetList<Text>(find.byType(Text))
                  .map((w) => w.data)
                  .toList(),
              'video_surfaces': t
                  .widgetList<PlayerSurface>(find.byType(PlayerSurface))
                  .map(
                    (w) => {
                      'initialized': w.controller.value.isInitialized,
                      'playing': w.controller.value.isPlaying,
                      'requested': w.isPlayRequested?.call(),
                      'error': w.controller.value.errorDescription,
                    },
                  )
                  .toList(),
              'active_baseline': active?.baseline,
              'active_frames': active?.samples,
            };
            debugPrint(
              'NATIVE_MOTION_FAILURE:${jsonEncode(result['failure'])}',
            );
            await host('failure', name: 'timeout');
            fail('Native motion timeout: $why');
          }
          await t.pump(const Duration(milliseconds: 16));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder finder) async {
        await until(() {
          if (finder.hitTestable().evaluate().length != 1) return false;
          final route = ModalRoute.of(t.element(finder));
          if (route != null &&
              (!route.isCurrent ||
                  route.animation?.status != AnimationStatus.completed)) {
            return false;
          }
          final widgets = [
            ...finder.evaluate().map((e) => e.widget),
            ...t.widgetList<Widget>(
              find.ancestor(
                of: finder,
                matching: find.byWidgetPredicate(
                  (w) => w is ButtonStyleButton || w is IconButton,
                ),
              ),
            ),
          ];
          return widgets.every(
            (w) => w is ButtonStyleButton
                ? w.onPressed != null
                : w is IconButton
                ? w.onPressed != null
                : true,
          );
        }, 'unique enabled actionable control');
        await t.pump();
        final point = t.getCenter(finder.hitTestable());
        await host('tap', point: point * t.view.devicePixelRatio);
        await t.pump();
      }

      PlayerSurface surface() =>
          t.widget<PlayerSurface>(find.byType(PlayerSurface).last);
      Future<void> tapCanvas() async {
        final finder = find.byKey(const Key('video-gesture-surface')).last;
        await until(() {
          if (finder.evaluate().isEmpty || t.getSize(finder).width <= 0) {
            return false;
          }
          final route = ModalRoute.of(t.element(finder));
          return route == null ||
              (route.isCurrent &&
                  route.animation?.status == AnimationStatus.completed);
        }, 'visible video gesture surface');
        // The centered inline-play overlay intercepts the center while paused,
        // and can remain until the next rendered frame after play completes.
        // Tap a real exposed part of the video, clear of all control overlays.
        final rect = t.getRect(finder);
        final point = Offset(
          rect.left + rect.width * .25,
          rect.top + rect.height * .35,
        );
        await host('tap', point: point * t.view.devicePixelRatio);
        await t.pump();
      }

      bool visible() {
        final controls = find.byKey(const Key('playback-controls'));
        if (controls.evaluate().isEmpty) return false;
        return t
                .widget<AnimatedOpacity>(
                  find
                      .ancestor(
                        of: controls.last,
                        matching: find.byType(AnimatedOpacity),
                      )
                      .first,
                )
                .opacity ==
            1;
      }

      Future<void> playing(bool expected) => until(() {
        if (find.byType(PlayerSurface).evaluate().isEmpty) return false;
        final p = surface().controller.value;
        return p.isInitialized &&
            !p.size.isEmpty &&
            p.isPlaying == expected &&
            (surface().isPlayRequested?.call() ?? p.isPlaying) == expected;
      }, 'native playing=$expected');

      Future<void> configure(bool reduced) async {
        final actual = await host('configure', reduced: reduced);
        await until(
          () =>
              ui
                      .PlatformDispatcher
                      .instance
                      .accessibilityFeatures
                      .disableAnimations ==
                  reduced &&
              MediaQuery.disableAnimationsOf(
                    t.element(find.byType(PlayerSurface).last),
                  ) ==
                  reduced,
          'real Android accessibility flag=$reduced',
        );
        result['last_platform_settings'] = actual;
      }

      MotionProbe probe({bool exit = false, bool footer = false}) {
        ({Element target, Element fade}) target(Finder child) {
          final opacity = find
              .ancestor(of: child, matching: find.byType(AnimatedOpacity))
              .first;
          final fade = find
              .descendant(of: opacity, matching: find.byType(FadeTransition))
              .first;
          return (target: t.element(opacity), fade: t.element(fade));
        }

        return MotionProbe(
          {
            'controls': target(find.byKey(const Key('playback-controls')).last),
            if (exit)
              'exit': target(find.byKey(const Key('fullscreen-exit')).last),
          },
          footer
              ? t.renderObject<RenderBox>(
                  find.byKey(const Key('native-motion-footer')),
                )
              : null,
        );
      }

      Future<void> measure(
        String name,
        bool reduced, {
        required bool automatic,
        bool exit = false,
        bool footer = false,
        bool resume = false,
      }) async {
        expect(visible(), isTrue);
        final controller = surface().controller;
        await host('begin', name: name);
        result['after_host_begin'] = {'name': name, ...nativeState()};
        await until(
          () =>
              find.byKey(const Key('playback-controls')).evaluate().isNotEmpty,
          'production controls mounted after native recording setup',
        );
        expect(
          identical(controller, surface().controller),
          isTrue,
          reason:
              'Native recording setup must not replace the video controller',
        );
        if (!visible()) await tapCanvas();
        final resting = probe(exit: exit, footer: footer);
        await until(
          () => resting.targets.values.every(
            (e) => (e.fade.widget as FadeTransition).opacity.value == 1,
          ),
          'fully visible baseline',
        );
        active = probe(exit: exit, footer: footer);
        // Sample a baseline in an actual frame before the action.
        await t.pump();
        final before = controller.value.position.inMilliseconds;
        if (automatic || resume) {
          await tap(find.widgetWithText(TextButton, '播放'));
          await playing(true);
        }
        if (!automatic) {
          await tapCanvas();
        }
        await until(
          () => active!.done,
          'first hidden frame and transition $name',
          seconds: 7,
        );
        result['active_case'] = {
          'name': name,
          'reduced': reduced,
          'baseline': active!.baseline,
          'frames': active!.samples,
        };
        final trace = active!.verify(reduced);
        active = null;
        expect(controller.value.isPlaying, isTrue);
        expect(identical(controller, surface().controller), isTrue);
        cases.add({
          'name': name,
          'reduced': reduced,
          'automatic_hide': automatic,
          'native_flag': ui
              .PlatformDispatcher
              .instance
              .accessibilityFeatures
              .disableAnimations,
          'media_query_flag': MediaQuery.disableAnimationsOf(
            t.element(find.byType(PlayerSurface).last),
          ),
          'physical': [t.view.physicalSize.width, t.view.physicalSize.height],
          'controller': identityHashCode(controller),
          'playing_after': true,
          'position_before_ms': before,
          'position_after_ms': controller.value.position.inMilliseconds,
          ...trace,
        });
        result.remove('active_case');
        await host('end', name: name);
        debugPrint('NATIVE_MOTION_CASE:$name');
      }

      await configureApplicationWindow();
      await repo.connect('http://10.0.2.2', 8777, 'native-motion-owned-only');
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      await until(
        () =>
            repo.libraryPreparation.value.ready &&
            find.text('预览此范围').hitTestable().evaluate().length == 1,
        'actual media library ready',
      );
      await tap(find.text('预览此范围'));
      await playing(true);
      final range = repo.playbackIdentity, selected = repo.current!.id;
      for (var round = 1; round <= 3; round++) {
        for (final reduced in [false, true]) {
          final prefix = 'round-$round-${reduced ? 'reduced' : 'normal'}';
          await configure(reduced);
          // Inline tap pauses while showing controls. A paused baseline cancels
          // the auto-hide timer before the host starts its recording.
          if (!visible()) {
            await tapCanvas();
          } else if (surface().controller.value.isPlaying) {
            await tap(find.widgetWithText(TextButton, '暂停'));
          }
          await playing(false);
          await measure('$prefix-app-inline', reduced, automatic: true);
          await tapCanvas();
          await playing(false);
          await tap(find.text('横向全屏'));
          await host('fullscreen_ready');
          await until(
            () =>
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed &&
                t.view.physicalSize.width > t.view.physicalSize.height &&
                find.byType(PlayerSurface).evaluate().isNotEmpty &&
                surface().fullscreen &&
                ModalRoute.of(t.element(find.byType(PlayerSurface).last))!
                        .animation!
                        .status ==
                    AnimationStatus.completed,
            'actual fullscreen orientation',
          );
          await playing(false);
          // The paused fullscreen baseline has no active hide timer.
          await measure(
            '$prefix-app-fullscreen',
            reduced,
            automatic: false,
            exit: true,
            resume: true,
          );
          await host('back');
          await until(
            () =>
                t.view.physicalSize.height > t.view.physicalSize.width &&
                find.byKey(const Key('fullscreen-exit')).evaluate().isEmpty,
            'Android back returns to portrait',
          );
          await playing(true);
          expect(repo.playbackIdentity, range);
          expect(repo.current!.id, selected);
        }
      }
      await tap(find.byKey(const Key('preview-back')));
      await until(
        () => find.byType(MovieStage).evaluate().isEmpty,
        'preview released',
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();

      // The current library path uses inlineControls. This extra native component
      // probe covers the retained legacy bar and optional moving caption, using
      // the production PlayerSurface and a real asset decoder, not a mock player
      // or an assertion that the whole old-service UI was exercised.
      for (var round = 1; round <= 3; round++) {
        for (final reduced in [false, true]) {
          final controller = isolated = VideoPlayerController.asset(
            'assets/media/flower-landscape.mp4',
          );
          await controller.initialize();
          await controller.setLooping(true);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
          ]);
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlayerSurface(
                  controller: controller,
                  name: 'native legacy motion probe',
                  fullscreen: true,
                  onExit: () {},
                  footer: const Text(
                    'Motion caption',
                    key: Key('native-motion-footer'),
                  ),
                ),
              ),
            ),
          );
          await until(
            () => t.view.physicalSize.width > t.view.physicalSize.height,
            'legacy component landscape',
          );
          await configure(reduced);
          await controller.play();
          await playing(true);
          if (!visible()) await tapCanvas();
          await measure(
            'round-$round-${reduced ? 'reduced' : 'normal'}-legacy-component',
            reduced,
            automatic: false,
            exit: true,
            footer: true,
          );
          await t.pumpWidget(const SizedBox());
          await t.pump();
          await controller.dispose();
          isolated = null;
        }
      }
      expect(cases.length, 18);
      result['complete'] = true;
    },
  );
}
