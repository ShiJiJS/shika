import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/main.dart' show configureApplicationWindow;
import 'package:video_viewer/ui/home.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import '../test/support/scan_details_fixture.dart';
import 'server_native_motion_test.dart' show host;

class ExpansionProbe {
  ExpansionProbe(this.name, this.target, this.reduced, this.live);
  final String name;
  final double target;
  final bool reduced, live;
  final before = <Map<String, dynamic>>[], frames = <Map<String, dynamic>>[];
  var tail = 0;
  bool get done => tail >= 3;
  bool endpoint(Map<String, dynamic> f) =>
      ((f['value'] as double) - target).abs() < .00001 &&
      ((f['height'] as double) - target).abs() < .00001 &&
      ((f['turns'] as double) - target * .5).abs() < .00001;
  void sample(Map<String, dynamic> f) {
    if (frames.isEmpty && f['expanded'] != (target == 1)) {
      before.add(f);
      return;
    }
    frames.add(f);
    if (endpoint(f) && (!live || f['native_flag'] == true)) tail++;
  }

  Map<String, dynamic> verify() {
    expect(done, isTrue);
    expect(frames.every((f) => f['expanded'] == (target == 1)), isTrue);
    expect(
      frames.every((f) => f['native_flag'] == f['media_query_flag']),
      isTrue,
    );
    expect(frames.skip(frames.length - 3).every(endpoint), isTrue);
    for (final f in frames) {
      expect(f['duration_ms'], f['native_flag'] == true ? 0 : 160);
      expect(
        f['body_px'],
        target == 0 && endpoint(f) ? 0 : greaterThanOrEqualTo(0),
      );
      if (target == 1 && endpoint(f)) expect(f['body_px'], greaterThan(0));
    }
    if (live) {
      final i = frames.indexWhere((f) => f['native_flag'] == true);
      expect(i, greaterThan(0));
      expect(frames[i - 1]['value'], inExclusiveRange(0, 1));
      expect(frames[i - 1]['height'], inExclusiveRange(0, 1));
      expect(frames.skip(i).every(endpoint), isTrue);
    } else if (reduced) {
      expect(frames.every(endpoint), isTrue);
    } else {
      expect(
        frames.any(
          (f) => (f['height'] as double) > 0 && (f['height'] as double) < 1,
        ),
        isTrue,
      );
    }
    if (!live) expect(frames.every((f) => f['native_flag'] == reduced), isTrue);
    return {
      'name': name,
      'target': target,
      'reduced': reduced,
      'live': live,
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
    'actual scan page with real Android expansion input and settings',
    (t) async {
      expect(kProfileMode, isTrue);
      expect(defaultTargetPlatform, TargetPlatform.android);
      final repo = ScanDetailsLibrary();
      final preferences = UiPreferences();
      late BuildContext source;
      var observing = true;
      ExpansionProbe? active;
      final cases = <Map<String, dynamic>>[],
          lifecycle = <Map<String, dynamic>>[];
      final result = <String, dynamic>{
        'actual_production_scan_page': true,
        'normal_release_acceptance': false,
        'accessibility_injected': false,
        'repository_or_file_commands': false,
        'cases': cases,
        'lifecycle': lifecycle,
      };
      binding.reportData = {'expansion_motion': result};

      Map<String, dynamic> read() {
        Element? tile;
        var cards = 0;
        String? summary, headerSummary;
        var failureDetail = false;
        void locate(Element element) {
          final w = element.widget;
          if (w is PaperExpansionTile) tile = element;
          if (w.key == const Key('library-preparation')) cards++;
          if (w is Text && w.key == const Key('preparation-progress')) {
            summary = w.data;
          }
          if (w is Text && w.key == const Key('root-scan-summary')) {
            headerSummary = w.data;
          }
          if (w is Text && w.data == '读取媒体信息超时 1 个') {
            failureDetail = true;
          }
          element.visitChildren(locate);
        }

        (source as Element).visitChildren(locate);
        final frame = <String, dynamic>{
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
          'tile_present': tile != null,
          'cards': cards,
          'preparation_summary': summary,
          'header_summary': headerSummary,
          'failure_detail_present': failureDetail,
        };
        if (tile == null) return frame;
        AnimationController? motion;
        RotationTransition? arrow;
        Align? align;
        RenderBox? body;
        bool? expanded;
        var controllers = 0, arrows = 0, clips = 0;
        final localizations = MaterialLocalizations.of(source);
        void visit(Element element) {
          final w = element.widget;
          if (w is AnimatedBuilder && w.animation is AnimationController) {
            motion = w.animation as AnimationController;
            controllers++;
          }
          if (w is RotationTransition &&
              w.child is Icon &&
              (w.child! as Icon).icon == Icons.expand_more) {
            arrow = w;
            arrows++;
          }
          if (w is ClipRect &&
              w.child is Align &&
              (w.child! as Align).heightFactor != null) {
            align = w.child! as Align;
            body = element.findRenderObject()! as RenderBox;
            clips++;
          }
          if (w is Semantics && w.properties.liveRegion == true) {
            if (w.properties.label == localizations.collapsedHint) {
              expanded = true;
            }
            if (w.properties.label == localizations.expandedHint) {
              expanded = false;
            }
          }
          element.visitChildren(visit);
        }

        tile!.visitChildren(visit);
        expect([controllers, arrows, clips], [1, 1, 1]);
        expect(expanded, isNotNull);
        return {
          ...frame,
          'expanded': expanded,
          'value': motion!.value,
          'duration_ms': motion!.duration!.inMilliseconds,
          'height': align!.heightFactor,
          'turns': arrow!.turns.value,
          'body_px': body!.size.height * MediaQuery.devicePixelRatioOf(source),
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
        if (result['complete'] != true) {
          result['failure'] = {
            'name': active?.name,
            'before': active?.before,
            'frames': active?.frames,
          };
          await host('failure', name: 'terminal');
        }
        observing = false;
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
        await configureApplicationWindow();
      });
      Future<void> until(bool Function() ready, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail(label);
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
          'actual native motion flag',
        );
      }

      Offset point() =>
          t.getCenter(find.byKey(const Key('root-scan-summary'))) *
          t.view.devicePixelRatio;
      Future<void> probe(
        String name,
        double target,
        bool reduced, {
        bool live = false,
      }) async {
        final p = ExpansionProbe(name, target, reduced, live);
        active = p;
        await host(live ? 'tap_reduce' : 'tap', point: point());
        await until(() => p.done, name);
        cases.add(p.verify());
        active = null;
      }

      await configureApplicationWindow();
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          builder: (_, child) => PaperControlTheme(
            child: Builder(
              builder: (context) {
                source = context;
                return child!;
              },
            ),
          ),
          home: LibraryHome(repository: repo, preferences: preferences),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('nav-settings')));
      await t.pumpAndSettle();
      await t.tap(find.text('媒体目录'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('root-scan-details')));
      await t.pumpAndSettle();
      await host('fullscreen_ready');
      for (var round = 1; round <= 3; round++) {
        await configure(false);
        expect(read()['expanded'], isFalse);
        final prefix = 'round-$round';
        await host('begin', name: prefix);
        await probe('$prefix-normal-expand', 1, false);
        await probe('$prefix-normal-collapse', 0, false);
        await configure(true);
        await probe('$prefix-reduced-expand', 1, true);
        await probe('$prefix-reduced-collapse', 0, true);
        await configure(false);
        await probe('$prefix-live-expand', 1, false, live: true);
        await configure(false);
        await probe('$prefix-live-collapse', 0, false, live: true);
        await configure(false);
        await host('tap', point: point());
        await until(() {
          final f = read();
          return f['expanded'] == true &&
              (f['height'] as double) > 0 &&
              (f['height'] as double) < 1;
        }, 'real expansion before scan update');
        final before = read();
        for (final stage in ['scanning', 'failed', 'completed']) {
          repo.libraryPreparation.value = stage == 'scanning'
              ? const LibraryPreparation(
                  scanning: true,
                  phase: 'processing_media',
                  discovered: 5,
                  processed: 4,
                )
              : stage == 'failed'
              ? const LibraryPreparation(
                  phase: 'failed',
                  failed: 1,
                  failureReasons: {'probe_timeout': 1},
                )
              : const LibraryPreparation(
                  phase: 'completed',
                  discovered: 5,
                  processed: 5,
                );
          await t.pump();
          final f = read();
          expect(f['tile_present'], stage == 'completed');
          expect(f['cards'], stage == 'completed' ? 0 : 1);
          if (stage == 'completed') {
            expect(f['expanded'], isFalse);
            expect(f['height'], 0);
            expect(f['header_summary'], contains('5 / 5 个'));
          } else if (stage == 'scanning') {
            expect(f['preparation_summary'], contains('4 / 5 个'));
          } else {
            expect(f['preparation_summary'], '扫描失败');
            expect(f['failure_detail_present'], isTrue);
          }
          final label = '$prefix-$stage';
          await host('capture', name: label);
          lifecycle.add({
            'name': label,
            'stage': stage,
            'before': before,
            'frame': f,
          });
        }
        await host('end', name: prefix);
      }
      expect(cases, hasLength(18));
      expect(lifecycle, hasLength(9));
      result.addAll({
        'complete': true,
        'directions': 18,
        'live_directions': 6,
        'additional_lifecycle_taps': 3,
        'lifecycle_states': 9,
        'recording_groups': 3,
      });
    },
  );
}
