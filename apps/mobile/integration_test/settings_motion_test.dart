import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/paper_toggle.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'server_native_motion_test.dart' show host;

Element? first(Element root, bool Function(Widget) matches) {
  if (matches(root.widget)) return root;
  Element? found;
  root.visitChildren((child) => found ??= first(child, matches));
  return found;
}

class SettingsProbe {
  SettingsProbe(this.name, this.theme, this.target, this.reduced);
  final String name;
  final bool theme, target, reduced;
  final frames = <Map<String, dynamic>>[];
  bool done = false;

  void add(Element root) {
    final control = first(root, (w) => w is PaperToggle);
    if (control == null || (control.widget as PaperToggle).value != target) {
      return;
    }
    final paint = first(
      control,
      (w) => w is CustomPaint && w.painter is PaperTogglePainter,
    );
    if (paint == null) return;
    final value =
        ((paint.widget as CustomPaint).painter! as PaperTogglePainter).position;
    final color = Paper.of(root).background;
    final progress =
        (color.r - Paper.background.r) /
        (Paper.darkTheme.scaffoldBackgroundColor.r - Paper.background.r);
    frames.add({
      'frame_us':
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
      'toggle_position': value,
      'paper_theme_progress': progress,
      'background_argb': color.toARGB32(),
      'native_flag': ui
          .PlatformDispatcher
          .instance
          .accessibilityFeatures
          .disableAnimations,
      'media_query_flag': MediaQuery.disableAnimationsOf(root),
    });
    final end = target ? 1.0 : 0.0;
    done =
        (value - end).abs() < .00001 &&
        (!theme || (progress - end).abs() < .00001);
  }

  Map<String, dynamic> verify() {
    expect(done, isTrue);
    expect(frames, isNotEmpty);
    expect(
      frames.every(
        (v) => v['native_flag'] == reduced && v['media_query_flag'] == reduced,
      ),
      isTrue,
    );
    for (final field in [
      'toggle_position',
      if (theme) 'paper_theme_progress',
    ]) {
      if (reduced) {
        expect(
          frames.every(
            (f) => ((f[field] as double) - (target ? 1 : 0)).abs() < .00001,
          ),
          isTrue,
        );
      } else {
        expect(
          frames.any(
            (f) =>
                (f[field] as double) > .00001 && (f[field] as double) < .99999,
          ),
          isTrue,
          reason: '$name/$field must have an actual intermediate paint',
        );
      }
    }
    return {
      'name': name,
      'theme': theme,
      'target': target,
      'reduced': reduced,
      'nominal_ms': reduced ? 0 : 140,
      'frames': frames,
    };
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets('real settings rows follow actual Android reduced motion', (
    t,
  ) async {
    expect(kProfileMode, isTrue);
    final repo = DemoLibraryRepository(
      MemoryStateStore(),
      latency: Duration.zero,
    );
    await repo.initialize();
    final preferences = UiPreferences();
    var commits = 0, observing = true;
    preferences.addListener(() => commits++);
    final cases = <Map<String, dynamic>>[];
    final result = <String, dynamic>{
      'actual_app_demo_repository': true,
      'ordinary_release_acceptance': false,
      'no_media_service_or_file_commands': true,
      'accessibility_injected': false,
      'cases': cases,
    };
    binding.reportData = {'settings_motion': result};
    SettingsProbe? active;
    Element? root;
    void frame(Duration _) {
      if (!observing) return;
      if (root?.mounted == true && active?.done == false) active!.add(root!);
      WidgetsBinding.instance.addPostFrameCallback(frame);
    }

    WidgetsBinding.instance.addPostFrameCallback(frame);
    addTearDown(() async {
      if (result['complete'] != true) {
        result['active_failure'] = {
          'name': active?.name,
          'frames': active?.frames,
        };
        await host('failure', name: 'terminal');
      }
      observing = false;
      await t.pumpWidget(const SizedBox());
      repo.dispose();
      preferences.dispose();
      await configureApplicationWindow();
    });
    Future<void> until(bool Function() condition, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail(label);
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(t.takeException(), isNull);
    }

    await configureApplicationWindow();
    await t.pumpWidget(
      VideoViewerApp(repository: repo, preferences: preferences),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('nav-settings')));
    await t.pumpAndSettle();
    final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
    for (var round = 1; round <= 3; round++) {
      for (final theme in [true, false]) {
        final row = find.byKey(
          Key(theme ? 'dark-mode-setting' : 'preload-setting'),
        );
        await t.ensureVisible(row);
        await t.pumpAndSettle();
        root = t.element(row);
        final control = first(root, (w) => w is PaperToggle)!;
        for (final reduced in [false, true]) {
          await host('configure', reduced: reduced);
          await until(
            () =>
                ui
                        .PlatformDispatcher
                        .instance
                        .accessibilityFeatures
                        .disableAnimations ==
                    reduced &&
                MediaQuery.disableAnimationsOf(root!) == reduced,
            'actual native reduced-motion flag',
          );
          final name =
              'round-$round-${theme ? 'theme' : 'preload'}-${reduced ? 'reduced' : 'normal'}';
          await host('begin', name: name);
          final before = commits;
          final initial = theme
              ? preferences.dark
              : preferences.preloadAdjacent;
          for (final target in [!initial, initial]) {
            final probe = SettingsProbe(
              '$name-${target ? 'on' : 'off'}',
              theme,
              target,
              reduced,
            );
            active = probe;
            final toggle = find.descendant(
              of: row,
              matching: find.byType(PaperToggle),
            );
            expect(toggle.hitTestable(), findsOneWidget);
            await host(
              'tap',
              point: t.getCenter(toggle) * t.view.devicePixelRatio,
            );
            await until(() => probe.done, 'settings paint target');
            cases.add(probe.verify());
            active = null;
            expect(first(root, (w) => w is PaperToggle), same(control));
            expect(
              t.state<NavigatorState>(find.byType(Navigator).first),
              same(navigator),
            );
            await host('capture', name: '${probe.name}-target');
          }
          expect(commits, before + 2);
          expect(preferences.dark, isFalse);
          expect(preferences.preloadAdjacent, isTrue);
          await host('end', name: name);
        }
      }
    }
    expect(cases.length, 24);
    result.addAll({'complete': true, 'commits': commits});
  });
}
