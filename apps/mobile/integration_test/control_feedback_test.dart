import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/main.dart' show configureApplicationWindow;
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/paper_press.dart';

import '../test/press_feedback_test.dart' show CaptureFactory;
import 'server_native_motion_test.dart' show host;

const idle = Color(0xfffaf8f3), selectedFill = Color(0xff53664a);

class ControlProbe {
  ControlProbe(this.name, this.kind, this.reduced, this.closing);
  final String name, kind;
  final bool reduced, closing;
  PaperPressInk? ink;
  int removalBaseline = 0;
  final frames = <Map<String, dynamic>>[];
  bool done = false, departed = false;
  void add(Duration stamp, double value, bool nativeFlag, bool mediaFlag) {
    if (done) return;
    final target = closing ? 0.0 : 1.0;
    if (closing && value == 1 && !departed) return;
    departed = true;
    frames.add({
      'frame_us': stamp.inMicroseconds,
      'paint_value': value,
      'native_flag': nativeFlag,
      'media_query_flag': mediaFlag,
    });
    done = (value - target).abs() < .00001;
  }

  Map<String, dynamic> verify() {
    expect(done, isTrue);
    expect(frames, isNotEmpty);
    final target = closing ? 0.0 : 1.0;
    expect(frames.last['paint_value'], closeTo(target, .00001));
    expect(
      frames.every(
        (v) => v['native_flag'] == reduced && v['media_query_flag'] == reduced,
      ),
      isTrue,
    );
    if (reduced) {
      expect(
        frames.every(
          (v) => ((v['paint_value'] as double) - target).abs() < .00001,
        ),
        isTrue,
      );
    } else {
      expect(
        frames.any(
          (v) =>
              (v['paint_value'] as double) > 0 &&
              (v['paint_value'] as double) < 1,
        ),
        isTrue,
      );
    }
    return {
      'name': name,
      'kind': kind,
      'closing': closing,
      'reduced': reduced,
      'nominal_ms': reduced
          ? 0
          : kind == 'press'
          ? 100
          : 140,
      'frames': frames,
    };
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets(
    'production control components follow actual Android preference without commands',
    (t) async {
      expect(kProfileMode, isTrue);
      final cases = <Map<String, dynamic>>[];
      final result = <String, dynamic>{
        'production_component_only': true,
        'normal_release_acceptance': false,
        'no_repository_or_file_commands': true,
        'system_accessibility_injected': false,
        'cases': cases,
        'pre_action_frames': <Map<String, dynamic>>[],
      };
      binding.reportData = {'control_feedback': result};
      late BuildContext source;
      CaptureFactory? captured;
      ControlProbe? active;
      var buttonCalls = 0,
          choiceCalls = 0,
          filterCalls = 0,
          choice = false,
          filter = false,
          observing = true;
      void frame(Duration _) {
        if (!observing) return;
        final probe = active;
        if (probe != null && !probe.done) {
          double? value;
          if (probe.kind == 'press') {
            if (probe.ink == null && captured!.features.isNotEmpty) {
              probe.ink = captured!.features.last;
            }
            if (probe.ink != null) {
              value = captured!.removals > probe.removalBaseline
                  ? 0
                  : probe.ink!.animation.value;
            }
          } else {
            final raw = find.descendant(
              of: find.byKey(Key('control-${probe.kind}')),
              matching: find.byType(RawChip),
            );
            if (raw.evaluate().length == 1) {
              final selected = t.widget<RawChip>(raw).selected;
              if (selected != !probe.closing) {
                (result['pre_action_frames'] as List).add({
                  'name': probe.name,
                  'frame_us': SchedulerBinding
                      .instance
                      .currentSystemFrameTimeStamp
                      .inMicroseconds,
                  'semantic_selected': selected,
                });
                WidgetsBinding.instance.addPostFrameCallback(frame);
                return;
              }
              final ink = find.descendant(of: raw, matching: find.byType(Ink));
              final color =
                  (t.widget<Ink>(ink).decoration as ShapeDecoration).color!;
              value = ((color.r - idle.r) / (selectedFill.r - idle.r)).clamp(
                0.0,
                1.0,
              );
            }
          }
          if (value != null) {
            probe.add(
              SchedulerBinding.instance.currentSystemFrameTimeStamp,
              value,
              ui
                  .PlatformDispatcher
                  .instance
                  .accessibilityFeatures
                  .disableAnimations,
              MediaQuery.disableAnimationsOf(source),
            );
          }
        }
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
        active = null;
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await configureApplicationWindow();
      });
      Future<void> until(bool Function() ready, String label) async {
        final end = DateTime.now().add(const Duration(seconds: 30));
        while (!ready()) {
          if (DateTime.now().isAfter(end)) {
            result['failure'] = {'waiting': label, 'frames': active?.frames};
            fail(label);
          }
          await t.pump(const Duration(milliseconds: 16));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> configure(bool value) async {
        await host('configure', reduced: value);
        await until(
          () =>
              ui
                      .PlatformDispatcher
                      .instance
                      .accessibilityFeatures
                      .disableAnimations ==
                  value &&
              MediaQuery.disableAnimationsOf(source) == value,
          'actual system preference',
        );
      }

      Future<void> action(String kind, String command) async {
        final target = find.byKey(Key('control-$kind'));
        expect(target.hitTestable(), findsOneWidget);
        await host(
          command,
          point: t.getCenter(target) * t.view.devicePixelRatio,
        );
      }

      await configureApplicationWindow();
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme.copyWith(
            chipTheme: const ChipThemeData(selectedColor: selectedFill),
          ),
          home: PaperControlTheme(
            child: StatefulBuilder(
              builder: (context, change) {
                source = context;
                captured ??= CaptureFactory(Theme.of(context).splashFactory);
                return Theme(
                  data: Theme.of(context).copyWith(splashFactory: captured),
                  child: Scaffold(
                    appBar: AppBar(title: const Text('操作反馈组件检查')),
                    body: Column(
                      children: [
                        FilledButton(
                          key: const Key('control-press'),
                          onPressed: () => buttonCalls++,
                          child: const Text('按住检查反馈'),
                        ),
                        PaperChoiceChip(
                          key: const Key('control-choice'),
                          label: const Text('单选检查'),
                          selected: choice,
                          backgroundColor: idle,
                          selectedColor: selectedFill,
                          onSelected: (v) {
                            choiceCalls++;
                            change(() => choice = v);
                          },
                        ),
                        PaperFilterChip(
                          key: const Key('control-filter'),
                          label: const Text('多选检查'),
                          selected: filter,
                          backgroundColor: idle,
                          onSelected: (v) {
                            filterCalls++;
                            change(() => filter = v);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await until(
        () => find.byKey(const Key('control-press')).evaluate().isNotEmpty,
        'component root',
      );
      for (var round = 1; round <= 3; round++) {
        for (final kind in ['press', 'choice', 'filter']) {
          for (final reduced in [false, true]) {
            final name = 'round-$round-$kind-${reduced ? 'reduced' : 'normal'}';
            await configure(reduced);
            await host('begin', name: name);
            final before = buttonCalls + choiceCalls + filterCalls;
            final entry = ControlProbe('$name-entry', kind, reduced, false);
            entry.removalBaseline = captured!.removals;
            active = entry;
            // Each hold creates exactly one new feature; ignore prior disposed entries.
            if (kind == 'press') {
              captured!.features.clear();
              await action(kind, 'hold_start');
            } else {
              await action(kind, 'tap');
            }
            await until(() => entry.done, 'entry target');
            cases.add(entry.verify());
            active = null;
            await host('capture', name: '$name-entry');
            if (kind != 'press') {
              expect(buttonCalls + choiceCalls + filterCalls, before + 1);
            }
            await configure(!reduced);
            final exit = ControlProbe('$name-return', kind, !reduced, true)
              ..ink = entry.ink
              ..removalBaseline = entry.removalBaseline;
            active = exit;
            if (kind == 'press') {
              await host('hold_end');
            } else {
              await action(kind, 'tap');
            }
            await until(() => exit.done, 'return target');
            cases.add(exit.verify());
            active = null;
            expect(
              buttonCalls + choiceCalls + filterCalls,
              before + (kind == 'press' ? 1 : 2),
            );
            expect(choice, isFalse);
            expect(filter, isFalse);
            await host('capture', name: '$name-return');
            await host('end', name: name);
          }
        }
      }
      expect(cases.length, 36);
      expect(buttonCalls, 6);
      expect(choiceCalls, 12);
      expect(filterCalls, 12);
      result.addAll({
        'button_callbacks': buttonCalls,
        'choice_callbacks': choiceCalls,
        'filter_callbacks': filterCalls,
        'complete': true,
      });
    },
  );
}
