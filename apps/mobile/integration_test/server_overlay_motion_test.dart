import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/features/preview/video_preview_route.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'server_native_motion_test.dart' show host;
import 'server_page_motion_test.dart' show PageMotionProbe;

class PopupObserver extends NavigatorObserver {
  PopupObserver(this.pushed);
  final void Function(ModalRoute<dynamic>) pushed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) pushed(route);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets(
    'actual sheets and production dialog follow changed system preference',
    (t) async {
      expect(kProfileMode, isTrue);
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8777);
      final preferences = UiPreferences(preloadAdjacent: false);
      final cases = <Map<String, dynamic>>[];
      final result = <String, dynamic>{
        'cases': cases,
        'normal_release_acceptance': false,
        'system_accessibility_injected': false,
        'dialog_business_failure_acceptance': false,
      };
      binding.reportData = {'overlay_motion': result};
      PageMotionProbe? active;
      var observing = true;
      final observer = PopupObserver((route) {
        if (active != null && !active!.closing) active!.bind(route);
      });
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
        if (finder.hitTestable().evaluate().isEmpty) {
          await t.ensureVisible(finder);
          // benchmarkLive ignores pump: wait for the actual layout after scroll
          // before converting the rendered control center to Android coordinates.
          final laidOut = Completer<void>();
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => laidOut.complete(),
          );
          SchedulerBinding.instance.scheduleFrame();
          await laidOut.future;
        }
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

      await configureApplicationWindow();
      await repo.connect('http://10.0.2.2', 8777, 'native-motion-owned-only');
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          navigatorObservers: [observer],
        ),
      );
      await until(() => repo.libraryPreparation.value.ready, 'library ready');
      for (var round = 1; round <= 3; round++) {
        for (final reduced in [false, true]) {
          final prefix = 'round-$round-${reduced ? 'reduced' : 'normal'}';
          await configure(reduced);
          await tap(find.byKey(const Key('kind-pack')));
          final tiles = find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('pack-tile-'),
          );
          await until(() => tiles.evaluate().isNotEmpty, 'pack tiles');
          await tap(tiles.first);
          await until(
            () =>
                find.byType(PackReaderPage).evaluate().isNotEmpty &&
                t
                    .state<PackReaderPageState>(find.byType(PackReaderPage))
                    .session
                    .opened,
            'decoded reader',
          );
          final reader = t.state<PackReaderPageState>(
            find.byType(PackReaderPage),
          );
          final page = reader.session.index;
          await host('begin', name: '$prefix-reader-sheet');
          final sheet = await enter(
            '$prefix-reader-sheet-entry',
            reduced,
            (w) => w is SheetFrame,
            () => tap(
              find.text(
                reader.session.preferences.mode.name == 'horizontal'
                    ? '横向翻页'
                    : '纵向拼接',
              ),
            ),
          );
          await configure(!reduced);
          await leave(
            '$prefix-reader-sheet-return',
            !reduced,
            sheet,
            () => tap(find.byKey(const Key('reader-settings-done'))),
          );
          expect(reader.session.index, page);
          await until(
            () => find
                .byKey(const Key('reader-settings-done'))
                .evaluate()
                .isEmpty,
            'reader sheet removed',
          );
          await host('end', name: '$prefix-reader-sheet');
          await tap(find.byTooltip('返回来源'));
          await until(
            () => find.byType(PackReaderPage).evaluate().isEmpty,
            'pack source',
          );
          await configure(reduced);
          await tap(find.byKey(const Key('kind-video')));
          await until(
            () => find.text('预览此范围').hitTestable().evaluate().isNotEmpty,
            'video library',
          );
          await tap(find.text('预览此范围'));
          await until(
            () => find.byType(VideoPreviewRoute).evaluate().isNotEmpty,
            'preview',
          );
          final id = repo.current!.id, range = repo.playbackIdentity;
          await host('begin', name: '$prefix-video-sheet');
          final queue = await enter(
            '$prefix-video-sheet-entry',
            reduced,
            (w) => w is PreviewQueueSheet,
            () => tap(find.byKey(const Key('preview-scope'))),
          );
          await configure(!reduced);
          await leave(
            '$prefix-video-sheet-return',
            !reduced,
            queue,
            () => host('back'),
          );
          await until(
            () => find.byType(PreviewQueueSheet).evaluate().isEmpty,
            'queue removed',
          );
          expect(repo.current!.id, id);
          expect(repo.playbackIdentity, range);
          await host('end', name: '$prefix-video-sheet');
          await tap(find.byKey(const Key('preview-back')));
          await until(
            () => find.byType(VideoPreviewRoute).evaluate().isEmpty,
            'video source',
          );
        }
      }
      // Isolated production dialog helper, not an induced reader-save failure.
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('dialog-open'),
                  onPressed: () => paperDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('确认操作'),
                      content: const Text('保留原来源和确认结果'),
                      actions: [
                        TextButton(
                          key: const Key('dialog-cancel'),
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('打开确认'),
                ),
              ),
            ),
          ),
        ),
      );
      for (var round = 1; round <= 3; round++) {
        for (final reduced in [false, true]) {
          final prefix = 'dialog-$round-${reduced ? 'reduced' : 'normal'}';
          await configure(reduced);
          await host('begin', name: prefix);
          final dialog = await enter(
            '$prefix-entry',
            reduced,
            (w) => w is AlertDialog,
            () => tap(find.byKey(const Key('dialog-open'))),
          );
          await configure(!reduced);
          await leave(
            '$prefix-return',
            !reduced,
            dialog,
            () => tap(find.byKey(const Key('dialog-cancel'))),
          );
          await until(
            () => find.byType(AlertDialog).evaluate().isEmpty,
            'dialog removed',
          );
          await host('end', name: prefix);
        }
      }
      expect(cases.length, 36);
      result['complete'] = true;
    },
  );
}
