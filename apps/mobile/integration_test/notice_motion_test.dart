import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/main.dart' show configureApplicationWindow;
import 'package:video_viewer/ui/paper.dart';

import 'server_native_motion_test.dart' show host;

class NoticeProbe {
  NoticeProbe(this.name, this.reduced, this.closing, [this.controller]);
  final String name;
  final bool reduced, closing;
  AnimationController? controller;
  final frames = <Map<String, dynamic>>[];
  bool done = false;

  void frame(Duration stamp, bool mediaQueryFlag, double opacity) {
    final value = controller;
    if (done || value == null) return;
    if (closing && value.status == AnimationStatus.completed) return;
    frames.add({
      'frame_us': stamp.inMicroseconds,
      'value': value.value,
      'visible_opacity': opacity,
      'duration_us':
          (closing ? value.reverseDuration : value.duration)?.inMicroseconds,
      'native_flag': ui
          .PlatformDispatcher
          .instance
          .accessibilityFeatures
          .disableAnimations,
      'media_query_flag': mediaQueryFlag,
    });
    done =
        value.status ==
        (closing ? AnimationStatus.dismissed : AnimationStatus.completed);
  }

  Map<String, dynamic> verify() {
    expect(done, isTrue);
    expect(frames, isNotEmpty);
    final target = closing ? 0.0 : 1.0;
    expect(frames.first['value'], reduced ? target : 1 - target);
    expect(frames.last['value'], target);
    expect(
      frames.every(
        (f) => f['native_flag'] == reduced && f['media_query_flag'] == reduced,
      ),
      isTrue,
    );
    // Keep the shared forward controller usable by the SDK queue. Reduced
    // entries finish before paint; reduced returns have actual zero duration.
    expect(
      frames.every(
        (f) => f['duration_us'] == (closing && reduced ? 0 : 160000),
      ),
      isTrue,
    );
    if (reduced) {
      expect(
        frames.every(
          (f) => f['value'] == target && f['visible_opacity'] == target,
        ),
        isTrue,
      );
    } else {
      expect(
        frames.any(
          (f) => (f['value'] as double) > 0 && (f['value'] as double) < 1,
        ),
        isTrue,
      );
      expect(
        frames.any(
          (f) =>
              (f['visible_opacity'] as double) > 0 &&
              (f['visible_opacity'] as double) < 1,
        ),
        isTrue,
      );
    }
    return {
      'name': name,
      'reduced': reduced,
      'closing': closing,
      'frames': frames,
    };
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets('production notice component uses actual Android preferences', (
    t,
  ) async {
    expect(kProfileMode, isTrue);
    final cases = <Map<String, dynamic>>[];
    final result = <String, dynamic>{
      'production_component_only': true,
      'normal_release_acceptance': false,
      'no_repository_or_file_commands': true,
      'system_accessibility_injected': false,
      'cases': cases,
    };
    binding.reportData = {'notice_motion': result};
    NoticeProbe? active;
    var observing = true, undoCount = 0;
    late BuildContext source;
    void frame(Duration _) {
      if (!observing) return;
      final probe = active;
      if (probe != null && !probe.done) {
        final bars = find.byType(SnackBar);
        if (probe.controller == null && bars.evaluate().isNotEmpty) {
          probe.controller =
              t.widget<SnackBar>(bars.first).animation! as AnimationController;
        }
        final fades = bars.evaluate().isEmpty
            ? <FadeTransition>[]
            : t
                  .widgetList<FadeTransition>(
                    find.descendant(
                      of: bars.first,
                      matching: find.byType(FadeTransition),
                    ),
                  )
                  .toList();
        final opacity = bars.evaluate().isEmpty
            ? 0.0
            : fades.fold<double>(1, (v, fade) => v * fade.opacity.value);
        probe.frame(
          SchedulerBinding.instance.currentSystemFrameTimeStamp,
          MediaQuery.disableAnimationsOf(source),
          opacity,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback(frame);
    }

    WidgetsBinding.instance.addPostFrameCallback(frame);
    addTearDown(() async {
      if (result['complete'] != true) await host('failure', name: 'terminal');
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

    Future<void> tap(Finder finder) async {
      await until(
        () => finder.hitTestable().evaluate().length == 1,
        'actionable control',
      );
      await host(
        'tap',
        point: t.getCenter(finder.hitTestable()) * t.view.devicePixelRatio,
      );
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
        'actual system preference',
      );
    }

    await configureApplicationWindow();
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: Builder(
          builder: (context) {
            source = context;
            return Scaffold(
              appBar: AppBar(title: const Text('通知组件检查')),
              body: Column(
                children: [
                  TextButton(
                    key: const Key('notice-open'),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      PaperSnackBar(
                        context: context,
                        content: const Text('组件通知'),
                        duration: const Duration(seconds: 20),
                        action: SnackBarAction(
                          label: '测试撤销',
                          onPressed: () => undoCount++,
                        ),
                      ),
                    ),
                    child: const Text('显示通知'),
                  ),
                  TextButton(
                    key: const Key('notice-hide'),
                    onPressed: () =>
                        ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                    child: const Text('关闭通知'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await until(
      () => find.byKey(const Key('notice-open')).evaluate().isNotEmpty,
      'component root',
    );
    for (var round = 1; round <= 3; round++) {
      for (final reduced in [false, true]) {
        for (final action in [false, true]) {
          final name =
              'round-$round-${reduced ? 'reduced' : 'normal'}-${action ? 'undo' : 'hide'}';
          await configure(reduced);
          await host('begin', name: name);
          final entry = active = NoticeProbe('$name-entry', reduced, false);
          await tap(find.byKey(const Key('notice-open')));
          await until(() => entry.done, 'entry target');
          cases.add(entry.verify());
          active = null;
          await host('capture', name: '$name-entry');
          await configure(!reduced);
          final before = undoCount;
          final exit = active = NoticeProbe(
            '$name-return',
            !reduced,
            true,
            entry.controller,
          );
          await tap(
            action ? find.text('测试撤销') : find.byKey(const Key('notice-hide')),
          );
          await until(() => exit.done, 'return target');
          cases.add(exit.verify());
          active = null;
          expect(undoCount, before + (action ? 1 : 0));
          await until(
            () => find.byType(SnackBar).evaluate().isEmpty,
            'notice removed',
          );
          await host('capture', name: '$name-return');
          await host('end', name: name);
        }
      }
    }
    expect(cases.length, 24);
    expect(undoCount, 6);
    result['undo_callbacks'] = undoCount;
    result['complete'] = true;
  });
}
