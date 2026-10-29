import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/main.dart' show configureApplicationWindow;
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/trash_layout.dart';

import 'server_native_motion_test.dart' show host;

class CheckboxProbe {
  CheckboxProbe(
    this.name,
    this.channel,
    this.target,
    this.reduced,
    this.callsBefore, {
    this.live = false,
  });
  final String name, channel;
  final double target;
  final bool reduced, live;
  final int callsBefore;
  final before = <Map<String, dynamic>>[], frames = <Map<String, dynamic>>[];
  int tail = 0;
  bool reached = false;
  bool get done => tail >= 3;
  void sample(Map<String, dynamic> f) {
    final down = f['down'] as bool;
    final started = channel == 'position'
        ? (f['calls'] as int) > callsBefore
        : channel == 'disable'
        ? down || f['enabled'] == false
        : target == 1
        ? down
        : !down;
    if (frames.isEmpty && !started) {
      before.add(f);
      return;
    }
    frames.add(f);
    final key = channel == 'position' ? 'position' : 'reaction';
    final atTarget =
        ((f[key] as double) - target).abs() < .00001 &&
        ((f['paint_$key'] as double) - target).abs() < .00001;
    final endpoint =
        atTarget &&
        (channel != 'disable' || f['enabled'] == false) &&
        (!live || f['native_flag'] == true);
    if (!reached && endpoint) {
      reached = true;
    }
    if (reached) tail++;
  }

  Map<String, dynamic> verify() {
    expect(done, isTrue);
    expect(frames, isNotEmpty);
    final key = channel == 'position' ? 'position' : 'reaction';
    bool endpoint(Map<String, dynamic> f) =>
        ((f[key] as double) - target).abs() < .00001 &&
        ((f['paint_$key'] as double) - target).abs() < .00001;
    expect(
      frames.every((f) => f['native_flag'] == f['media_query_flag']),
      isTrue,
    );
    expect(frames.skip(frames.length - 3).every(endpoint), isTrue);
    if (channel == 'disable') {
      final i = frames.indexWhere((f) => f['enabled'] == false);
      expect(i, greaterThan(0));
      expect(
        frames
            .take(i)
            .any((f) => f['down'] == true && (f['reaction'] as double) > 0),
        isTrue,
      );
      expect(
        frames.skip(i).every((f) => endpoint(f) && f['down'] == false),
        isTrue,
      );
    } else if (live) {
      final i = frames.indexWhere((f) => f['native_flag'] == true);
      expect(i, greaterThan(0));
      expect(
        frames[i - 1][key],
        inExclusiveRange(0, 1),
        reason: 'Native flag must arrive during the real running direction',
      );
      expect(frames.skip(i).every(endpoint), isTrue);
    } else if (reduced) {
      expect(frames.every(endpoint), isTrue);
    } else {
      expect(
        frames.any((f) => (f[key] as double) > 0 && (f[key] as double) < 1),
        isTrue,
      );
    }
    if (!live) expect(frames.every((f) => f['native_flag'] == reduced), isTrue);
    return {
      'name': name,
      'channel': channel,
      'target': target,
      'reduced': reduced,
      'live': live,
      'calls_before': callsBefore,
      'before': before,
      'frames': frames,
    };
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets(
    'production checkbox controls with real Android input and settings',
    (t) async {
      expect(kProfileMode, isTrue);
      late BuildContext source;
      late StateSetter update;
      var kind = 'trash', enabled = true, armDisable = false, observing = true;
      final values = {'trash': false, 'row': false};
      final calls = {'trash': 0, 'row': 0};
      Timer? disableTimer;
      CheckboxProbe? active;
      final cases = <Map<String, dynamic>>[];
      final result = <String, dynamic>{
        'production_components_only': true,
        'normal_release_acceptance': false,
        'accessibility_injected': false,
        'repository_or_file_commands': false,
        'cases': cases,
      };
      binding.reportData = {'checkbox_motion': result};
      Finder checkbox() => find.byWidgetPredicate((w) => w is PaperCheckbox);
      Map<String, dynamic> read() {
        final state = t.state(checkbox()) as ToggleableStateMixin;
        final painter =
            t
                    .widget<CustomPaint>(
                      find.descendant(
                        of: checkbox(),
                        matching: find.byWidgetPredicate(
                          (w) =>
                              w is CustomPaint &&
                              w.painter is ToggleablePainter,
                        ),
                      ),
                    )
                    .painter!
                as ToggleablePainter;
        return {
          'frame_us': SchedulerBinding
              .instance
              .currentSystemFrameTimeStamp
              .inMicroseconds,
          'native_flag': ui
              .PlatformDispatcher
              .instance
              .accessibilityFeatures
              .disableAnimations,
          'media_query_flag': MediaQuery.disableAnimationsOf(source),
          'kind': kind,
          'calls': calls[kind],
          'checkbox_value': t.widget<PaperCheckbox>(checkbox()).value,
          'enabled': state.isInteractive,
          'down': state.downPosition != null,
          'position': state.positionController.value,
          'paint_position': painter.position.value,
          'reaction': state.reactionController.value,
          'paint_reaction': painter.reaction.value,
          'position_ms': state.positionController.duration!.inMilliseconds,
          'reaction_ms': state.reactionController.duration!.inMilliseconds,
        };
      }

      void frame(Duration _) {
        if (!observing) return;
        final p = active;
        if (p != null && !p.done) {
          p.sample(read());
          if (!p.done) SchedulerBinding.instance.scheduleFrame();
        }
        WidgetsBinding.instance.addPostFrameCallback(frame);
      }

      WidgetsBinding.instance.addPostFrameCallback(frame);
      addTearDown(() async {
        disableTimer?.cancel();
        if (result['complete'] != true) {
          result['failure'] = {
            'name': active?.name,
            'frames': active?.frames,
            'before': active?.before,
          };
          await host('failure', name: 'terminal');
        }
        observing = false;
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await configureApplicationWindow();
      });
      Future<void> until(bool Function() ready, String message) async {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail(message);
          await t.pump(const Duration(milliseconds: 16));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> configure(bool reduced) async {
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
          'native reduced flag',
        );
      }

      Future<void> probe(
        String name,
        String channel,
        double target,
        bool reduced,
        String action, {
        bool live = false,
        int expectedCalls = 0,
      }) async {
        final was = calls[kind]!;
        final p = CheckboxProbe(
          name,
          channel,
          target,
          reduced,
          was,
          live: live,
        );
        active = p;
        final point = t.getCenter(checkbox()) * t.view.devicePixelRatio;
        await host(action, point: point);
        await until(() => p.done, name);
        cases.add(p.verify());
        active = null;
        expect(calls[kind], was + expectedCalls);
        expect(values[kind], channel == 'position' ? target == 1 : false);
        if (channel == 'position') {
          expect(
            p.frames.every(
              (f) =>
                  f['calls'] == was + 1 && f['checkbox_value'] == (target == 1),
            ),
            isTrue,
          );
        } else {
          expect(p.frames.every((f) => f['calls'] == was), isTrue);
        }
      }

      await configureApplicationWindow();
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          builder: (_, child) => PaperControlTheme(child: child!),
          home: Scaffold(
            appBar: AppBar(title: const Text('复选反馈检查')),
            body: StatefulBuilder(
              builder: (context, set) {
                source = context;
                update = set;
                void changed(bool next) => set(() {
                  values[kind] = next;
                  calls[kind] = calls[kind]! + 1;
                });
                final Widget control = kind == 'trash'
                    ? TrashEntryRow(
                        title: '样本图包',
                        path: '/fixture/sample',
                        selected: values[kind]!,
                        onToggle: enabled
                            ? () => changed(!values[kind]!)
                            : null,
                        onRestore: null,
                        restoreKey: const Key('no-restore'),
                      )
                    : PaperCheckboxListTile(
                        title: const Text('只确认选择，不提交任何操作'),
                        value: values[kind],
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: enabled ? (v) => changed(v!) : null,
                      );
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(kind == 'trash' ? '实际回收行' : '整行确认控件'),
                      const SizedBox(height: 24),
                      Listener(
                        onPointerDown: (_) {
                          if (armDisable) {
                            armDisable = false;
                            disableTimer = Timer(
                              const Duration(milliseconds: 260),
                              () {
                                if (context.mounted) set(() => enabled = false);
                              },
                            );
                          }
                        },
                        child: control,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '选择回调 ${calls[kind]} · 当前 ${values[kind]} · 可操作 $enabled',
                      ),
                      const Text('仅控件检查 · 不执行删除或恢复'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await host('fullscreen_ready');
      for (var round = 1; round <= 3; round++) {
        for (final type in ['trash', 'row']) {
          update(() {
            kind = type;
            enabled = true;
            armDisable = false;
          });
          await t.pumpAndSettle();
          expect(values[kind], isFalse);
          final prefix = 'round-$round-$kind';
          await configure(false);
          await host('begin', name: prefix);
          for (final reduced in [false, true]) {
            await configure(reduced);
            final name = '$prefix-${reduced ? 'reduced' : 'normal'}';
            await probe(
              '$name-select',
              'position',
              1,
              reduced,
              'tap',
              expectedCalls: 1,
            );
            await probe(
              '$name-deselect',
              'position',
              0,
              reduced,
              'tap',
              expectedCalls: 1,
            );
            await probe('$name-press', 'reaction', 1, reduced, 'hold_start');
            await probe('$name-cancel', 'reaction', 0, reduced, 'hold_cancel');
          }
          await configure(false);
          await probe(
            '$prefix-live-select',
            'position',
            1,
            false,
            'tap_reduce',
            live: true,
            expectedCalls: 1,
          );
          await configure(false);
          await probe(
            '$prefix-live-deselect',
            'position',
            0,
            false,
            'tap_reduce',
            live: true,
            expectedCalls: 1,
          );
          await configure(false);
          await probe(
            '$prefix-live-press',
            'reaction',
            1,
            false,
            'hold_reduce',
            live: true,
          );
          await probe(
            '$prefix-reduced-cancel-after-live',
            'reaction',
            0,
            true,
            'hold_cancel',
          );
          await configure(false);
          await probe(
            '$prefix-normal-press-before-live',
            'reaction',
            1,
            false,
            'hold_start',
          );
          await probe(
            '$prefix-live-cancel',
            'reaction',
            0,
            false,
            'cancel_reduce',
            live: true,
          );
          await configure(false);
          update(() => armDisable = true);
          await t.pump();
          await probe(
            '$prefix-disable-held',
            'disable',
            0,
            false,
            'hold_start',
          );
          await host('hold_end');
          await t.pump(const Duration(milliseconds: 100));
          expect(calls[kind], round * 6);
          update(() => enabled = true);
          await t.pumpAndSettle();
          await host('end', name: prefix);
        }
      }
      expect(cases, hasLength(90));
      expect(calls, {'trash': 18, 'row': 18});
      result.addAll({
        'complete': true,
        'callbacks': calls,
        'final_values': values,
        'directions': 90,
        'live_directions': 24,
        'recording_groups': 6,
      });
    },
  );
}
