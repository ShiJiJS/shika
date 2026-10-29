import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/main.dart' show configureApplicationWindow;
import 'package:video_viewer/ui/paper.dart';

import '../test/press_feedback_test.dart' show CaptureFactory;
import 'server_native_motion_test.dart' show host;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets(
    'quick native tap acknowledges once with live system motion preference',
    (t) async {
      expect(kProfileMode, isTrue);
      final cases = <Map<String, dynamic>>[];
      final result = <String, dynamic>{
        'production_component_only': true,
        'no_repository_or_file_commands': true,
        'normal_release_acceptance': false,
        'system_accessibility_injected': false,
        'cases': cases,
        'observations': <Map<String, dynamic>>[],
      };
      binding.reportData = {'quick_press_feedback': result};
      CaptureFactory? captured;
      late BuildContext source;
      var calls = 0, observing = true, removalBaseline = 0;
      List<Map<String, dynamic>>? active;
      void frame(Duration _) {
        if (!observing) return;
        final frames = active;
        if (frames != null && captured!.features.isNotEmpty) {
          final removed = captured!.removals > removalBaseline;
          frames.add({
            'frame_us': SchedulerBinding
                .instance
                .currentSystemFrameTimeStamp
                .inMicroseconds,
            'paint_value': removed
                ? 0.0
                : captured!.features.single.animation.value,
            'removed': removed,
            'native_flag': ui
                .PlatformDispatcher
                .instance
                .accessibilityFeatures
                .disableAnimations,
            'media_query_flag': MediaQuery.disableAnimationsOf(source),
            'callbacks': calls,
          });
        }
        WidgetsBinding.instance.addPostFrameCallback(frame);
      }

      WidgetsBinding.instance.addPostFrameCallback(frame);
      addTearDown(() async {
        if (result['complete'] != true) {
          result['active_failure'] = active;
          await host('failure', name: 'terminal');
        }
        observing = false;
        active = null;
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await configureApplicationWindow();
      });
      Future<void> until(bool Function() ready, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) {
            result['failure'] = {'waiting': label, 'frames': active};
            fail(label);
          }
          await t.pump(const Duration(milliseconds: 16));
        }
        expect(t.takeException(), isNull);
      }

      await configureApplicationWindow();
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: PaperControlTheme(
            child: Builder(
              builder: (context) {
                source = context;
                captured ??= CaptureFactory(Theme.of(context).splashFactory);
                return Theme(
                  data: Theme.of(context).copyWith(splashFactory: captured),
                  child: Scaffold(
                    appBar: AppBar(title: const Text('快速点击反馈检查')),
                    body: Center(
                      child: FilledButton(
                        key: const Key('quick-action'),
                        onPressed: () => calls++,
                        child: const Text('快速点击'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await until(
        () =>
            find
                .byKey(const Key('quick-action'))
                .hitTestable()
                .evaluate()
                .length ==
            1,
        'actionable button',
      );
      for (var round = 1; round <= 3; round++) {
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
                MediaQuery.disableAnimationsOf(source) == reduced,
            'actual Android preference',
          );
          final name = 'round-$round-quick-${reduced ? 'reduced' : 'normal'}';
          await host('begin', name: name);
          final before = calls;
          removalBaseline = captured!.removals;
          captured!.features.clear();
          final frames = <Map<String, dynamic>>[];
          active = frames;
          await host(
            'tap',
            point:
                t.getCenter(find.byKey(const Key('quick-action'))) *
                t.view.devicePixelRatio,
          );
          await until(
            () =>
                calls == before + 1 &&
                frames.isNotEmpty &&
                frames.last['removed'] == true,
            'single callback and press layer removed',
          );
          (result['observations'] as List).add({
            'name': name,
            'reduced': reduced,
            'callbacks_before': before,
            'frames': frames,
          });
          expect(captured!.features, hasLength(1));
          expect(captured!.removals, removalBaseline + 1);
          expect(
            frames.every(
              (f) =>
                  f['native_flag'] == reduced &&
                  f['media_query_flag'] == reduced,
            ),
            isTrue,
          );
          expect(frames.last['paint_value'], 0);
          final afterConfirmation = frames
              .where((f) => f['callbacks'] == before + 1)
              .toList();
          expect(afterConfirmation, isNotEmpty);
          if (reduced) {
            for (final f in frames) {
              if (f['callbacks'] == before) {
                expect(
                  f['paint_value'],
                  1,
                  reason: 'Reduced motion shows pointer-down state immediately',
                );
              } else {
                expect(f['callbacks'], before + 1);
                expect(
                  f['paint_value'],
                  0,
                  reason: 'Confirmed quick tap has no residual animation',
                );
                expect(f['removed'], isTrue);
              }
            }
          } else {
            expect(
              afterConfirmation.any((f) => (f['paint_value'] as double) > 0),
              isTrue,
            );
            expect(
              afterConfirmation.any(
                (f) =>
                    (f['paint_value'] as double) > 0 &&
                    (f['paint_value'] as double) < 1,
              ),
              isTrue,
            );
          }
          active = null;
          cases.add({
            'name': name,
            'reduced': reduced,
            'callbacks_before': before,
            'callbacks_after': calls,
            'nominal_exit_ms': reduced ? 0 : 100,
            'frames': frames,
            'old_all_frames_zero': frames.every((f) => f['paint_value'] == 0),
          });
          await host('capture', name: '$name-done');
          await host('end', name: name);
        }
      }
      expect(cases, hasLength(6));
      expect(calls, 6);
      result['callbacks'] = calls;
      result['complete'] = true;
    },
  );
}
