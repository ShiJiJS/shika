import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/features/preview/video_preview_route.dart';
import 'package:video_viewer/features/settings/maintenance_task_detail.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper_management.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'server_native_motion_test.dart' show host;

class PageMotionObserver extends NavigatorObserver {
  PageMotionObserver(this.pushed);
  final void Function(ModalRoute<dynamic>) pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PaperPageRoute<dynamic>) pushed(route);
  }
}

/// Observe the route bound by Navigator before its first rendered frame,
/// without depending on when snapshot transitions mount the target subtree.
class PageMotionProbe {
  PageMotionProbe.entry(this.name, this.reduced, {this.excludedRoute})
    : closing = false;
  PageMotionProbe.exit(this.name, this.reduced, this.route)
    : closing = true,
      excludedRoute = null {
    animation = route!.animation!;
    duration = route!.reverseTransitionDuration;
    mediaQueryFlag = MediaQuery.disableAnimationsOf(route!.subtreeContext!);
  }
  final String name;
  final bool reduced, closing;
  final ModalRoute<dynamic>? excludedRoute;
  ModalRoute<dynamic>? route;
  Animation<double>? animation;
  Duration? duration;
  bool? mediaQueryFlag;
  final frames = <Map<String, dynamic>>[];
  bool done = false;

  void bind(ModalRoute<dynamic> value) {
    if (route != null || value == excludedRoute) return;
    route = value;
    animation = value.animation!;
    duration = value.transitionDuration;
    mediaQueryFlag = MediaQuery.disableAnimationsOf(value.navigator!.context);
  }

  void frame(Duration stamp) {
    if (done) return;
    final value = animation;
    if (value == null) return;
    if (closing && value.status == AnimationStatus.completed) return;
    frames.add({
      'frame_us': stamp.inMicroseconds,
      'value': value.value,
      'status': value.status.name,
      'native_flag': ui
          .PlatformDispatcher
          .instance
          .accessibilityFeatures
          .disableAnimations,
      'media_query_flag_at_action': mediaQueryFlag,
    });
    done =
        value.status ==
        (closing ? AnimationStatus.dismissed : AnimationStatus.completed);
  }

  Map<String, dynamic> verify() {
    expect(done, isTrue);
    expect(frames, isNotEmpty);
    expect(
      duration,
      Duration(
        milliseconds: reduced
            ? 0
            : closing
            ? 160
            : 240,
      ),
    );
    expect(mediaQueryFlag, reduced);
    expect(frames.every((v) => v['native_flag'] == reduced), isTrue);
    final target = closing ? 0.0 : 1.0;
    expect(
      frames.first['value'],
      reduced
          ? target
          : closing
          ? 1.0
          : 0.0,
    );
    expect(frames.last['value'], target);
    if (!reduced) {
      expect(
        frames.any(
          (v) => (v['value'] as double) > 0 && (v['value'] as double) < 1,
        ),
        isTrue,
      );
    }
    return {
      'name': name,
      'reduced': reduced,
      'closing': closing,
      'configured_duration_us': duration!.inMicroseconds,
      'frames': frames,
    };
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets('real system page entry and changed-preference return', (
    t,
  ) async {
    expect(kProfileMode, isTrue);
    final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8777);
    final preferences = UiPreferences(preloadAdjacent: false);
    final cases = <Map<String, dynamic>>[];
    final result = <String, dynamic>{
      'profile_entry': true,
      'normal_release_acceptance': false,
      'system_accessibility_injected': false,
      'audio_playback_acceptance': false,
      'cases': cases,
    };
    binding.reportData = {'page_motion': result};
    PageMotionProbe? active;
    var observing = true;
    void frame(Duration _) {
      if (!observing) return;
      active?.frame(SchedulerBinding.instance.currentSystemFrameTimeStamp);
      WidgetsBinding.instance.addPostFrameCallback(frame);
    }

    WidgetsBinding.instance.addPostFrameCallback(frame);
    addTearDown(() async {
      if (result['complete'] != true) await host('failure', name: 'terminal');
      observing = false;
      active = null;
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      preferences.dispose();
      await configureApplicationWindow();
    });
    Future<void> until(bool Function() ready, String why) async {
      final end = DateTime.now().add(const Duration(seconds: 40));
      while (!ready()) {
        if (DateTime.now().isAfter(end)) {
          result['failure'] = {
            'waiting_for': why,
            'active_name': active?.name,
            'frames': active?.frames,
            'texts': t
                .widgetList<Text>(find.byType(Text))
                .map((v) => v.data)
                .toList(),
          };
          await host('failure', name: 'timeout');
          fail('Native page motion timeout: $why');
        }
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> tap(Finder finder) async {
      await t.ensureVisible(finder);
      await until(() {
        if (finder.hitTestable().evaluate().length != 1) return false;
        final route = ModalRoute.of(t.element(finder));
        return route == null ||
            (route.isCurrent &&
                route.animation?.status == AnimationStatus.completed);
      }, 'actionable UI control');
      await host(
        'tap',
        point: t.getCenter(finder.hitTestable()) * t.view.devicePixelRatio,
      );
    }

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
                  t.element(find.byType(Navigator).first),
                ) ==
                reduced,
        'real Android system preference',
      );
      result['last_platform_settings'] = actual;
    }

    Future<PageMotionProbe> enter(
      String name,
      bool reduced,
      bool Function(Widget) matches,
      Future<void> Function() action, {
      ModalRoute<dynamic>? excludedRoute,
    }) async {
      final probe = active = PageMotionProbe.entry(
        name,
        reduced,
        excludedRoute: excludedRoute,
      );
      result['active_case'] = {'name': name, 'frames': probe.frames};
      await action();
      await until(() => probe.done, 'entry frame trace $name');
      cases.add(probe.verify());
      active = null;
      result.remove('active_case');
      await until(
        () => find.byWidgetPredicate(matches).evaluate().isNotEmpty,
        'actual target page mounted',
      );
      await host('capture', name: name);
      return probe;
    }

    Future<void> leave(
      String name,
      bool reduced,
      PageMotionProbe entry,
      Future<void> Function() action,
    ) async {
      final probe = active = PageMotionProbe.exit(name, reduced, entry.route);
      result['active_case'] = {'name': name, 'frames': probe.frames};
      await action();
      await until(() => probe.done, 'return frame trace $name');
      cases.add(probe.verify());
      active = null;
      result.remove('active_case');
      await host('capture', name: name);
    }

    Finder packTiles() => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('pack-tile-'),
    );
    bool taskRow(Widget w) =>
        w is PaperActionRow &&
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('maintenance-task-');
    await configureApplicationWindow();
    await repo.connect('http://10.0.2.2', 8777, 'native-motion-owned-only');
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: preferences,
        navigatorObservers: [
          PageMotionObserver((route) {
            final probe = active;
            if (probe != null && !probe.closing) probe.bind(route);
          }),
        ],
      ),
    );
    await until(
      () => repo.libraryPreparation.value.ready,
      'actual library ready',
    );
    for (var round = 1; round <= 3; round++) {
      for (final reduced in [false, true]) {
        final prefix = 'round-$round-${reduced ? 'reduced' : 'normal'}';
        await configure(reduced);
        await tap(find.byKey(const Key('kind-pack')));
        await until(() => packTiles().evaluate().isNotEmpty, 'pack library');
        await host('begin', name: '$prefix-reader');
        final reader = await enter(
          '$prefix-reader-entry',
          reduced,
          (w) => w is PackReaderPage,
          () => tap(packTiles().first),
        );
        await until(
          () => t
              .state<PackReaderPageState>(find.byType(PackReaderPage))
              .session
              .opened,
          'decoded current reader image confirmed',
        );
        await configure(!reduced);
        await leave(
          '$prefix-reader-return',
          !reduced,
          reader,
          () => tap(find.byTooltip('返回来源')),
        );
        await until(
          () =>
              find.byType(PackReaderPage).evaluate().isEmpty &&
              find.byKey(const Key('pack-search')).evaluate().isNotEmpty,
          'same pack library source',
        );
        await host('end', name: '$prefix-reader');

        await configure(reduced);
        await tap(find.byKey(const Key('kind-video')));
        await until(
          () => find.text('预览此范围').hitTestable().evaluate().isNotEmpty,
          'video library',
        );
        await host('begin', name: '$prefix-video');
        final preview = await enter(
          '$prefix-preview-entry',
          reduced,
          (w) => w is VideoPreviewRoute,
          () => tap(find.text('预览此范围')),
        );
        await until(
          () =>
              find.byType(PlayerSurface).evaluate().isNotEmpty &&
              t
                  .widget<PlayerSurface>(find.byType(PlayerSurface).last)
                  .controller
                  .value
                  .isInitialized,
          'actual video decoder',
        );
        final selected = repo.current!.id, range = repo.playbackIdentity;
        final fullscreen = await enter(
          '$prefix-fullscreen-entry',
          reduced,
          (w) => w is Scaffold,
          () => tap(find.text('横向全屏')),
          excludedRoute: preview.route,
        );
        await host('fullscreen_ready');
        await until(
          () =>
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed &&
              t.view.physicalSize.width > t.view.physicalSize.height &&
              t
                  .widgetList<PlayerSurface>(find.byType(PlayerSurface))
                  .any((w) => w.fullscreen && w.controller.value.isInitialized),
          'actual landscape and foreground after system hint',
        );
        await configure(!reduced);
        await leave(
          '$prefix-fullscreen-return',
          !reduced,
          fullscreen,
          () => host('back'),
        );
        await until(
          () =>
              t.view.physicalSize.height > t.view.physicalSize.width &&
              find.byKey(const Key('fullscreen-exit')).evaluate().isEmpty,
          'portrait preview retained',
        );
        expect(repo.current!.id, selected);
        expect(repo.playbackIdentity, range);
        await leave(
          '$prefix-preview-return',
          !reduced,
          preview,
          () => tap(find.byKey(const Key('preview-back'))),
        );
        await until(
          () =>
              find.byType(VideoPreviewRoute).evaluate().isEmpty &&
              find.byKey(const Key('video-search')).evaluate().isNotEmpty,
          'same video library source',
        );
        await host('end', name: '$prefix-video');

        await configure(reduced);
        await tap(find.byKey(const Key('nav-settings')));
        await tap(find.text('操作任务'));
        await until(
          () => find.byWidgetPredicate(taskRow).evaluate().isNotEmpty,
          'actual task rows',
        );
        final row = find.byWidgetPredicate(taskRow).first;
        final rowKey = t.widget(row).key!;
        await host('begin', name: '$prefix-task');
        final task = await enter(
          '$prefix-task-entry',
          reduced,
          (w) => w is MaintenanceTaskDetail,
          () => tap(row),
        );
        await until(
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
          'actual task detail loaded',
        );
        await configure(!reduced);
        await leave('$prefix-task-return', !reduced, task, () => host('back'));
        await until(
          () =>
              find.byType(MaintenanceTaskDetail).evaluate().isEmpty &&
              find.byKey(rowKey).evaluate().isNotEmpty,
          'same task source retained',
        );
        await host('end', name: '$prefix-task');
        await tap(find.byTooltip('返回设置'));
        await tap(find.byKey(const Key('nav-library')));
      }
    }
    expect(cases.length, 48);
    result['complete'] = true;
  });
}
