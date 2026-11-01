import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/main.dart' show configureApplicationWindow;
import 'package:video_viewer/ui/paper.dart';

import 'server_native_motion_test.dart' show host;

class MenuHandle {
  MenuHandle(this.route) : animation = route.animation! {
    route.completed.then((_) => finished = true);
  }
  final TransitionRoute<dynamic> route;
  final Animation<double> animation;
  bool popped = false, finished = false;
}

class MenuObserver extends NavigatorObserver {
  MenuObserver(this.onPush);
  final void Function(MenuHandle) onPush;
  final handles = <Route<dynamic>, MenuHandle>{};
  MenuHandle? last;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute<dynamic>) {
      last = MenuHandle(route);
      handles[route] = last!;
      onPush(last!);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    handles[route]?.popped = true;
  }
}

class MenuProbe {
  MenuProbe(this.name, this.opening, this.reduced, {this.live = false});
  final String name;
  final bool opening, reduced, live;
  MenuHandle? handle;
  bool done = false;
  final frames = <Map<String, dynamic>>[];
  final before = <Map<String, dynamic>>[];
  Map<String, dynamic> verify() {
    expect(done, isTrue);
    expect(frames, isNotEmpty);
    final target = opening ? 1.0 : 0.0;
    expect(frames.last['route_value'], closeTo(target, .00001));
    expect(frames.last['paint_opacity'], closeTo(target, .00001));
    if (opening) {
      expect(frames.last['height_factor'], closeTo(1, .00001));
      expect(frames.last['last_item_opacity'], closeTo(1, .00001));
    }
    expect(
      frames.every((f) => f['native_flag'] == f['media_query_flag']),
      isTrue,
    );
    if (live) {
      final split = frames.indexWhere((f) => f['native_flag'] == true);
      expect(split, greaterThan(0));
      expect(
        frames[split - 1]['route_value'],
        inExclusiveRange(0, 1),
        reason: 'System flag must arrive while transition is visibly in flight',
      );
      expect(
        frames
            .take(split)
            .any(
              (f) =>
                  (f['route_value'] as double) > 0 &&
                  (f['route_value'] as double) < 1,
            ),
        isTrue,
      );
      expect(
        frames
            .skip(split)
            .every(
              (f) =>
                  ((f['route_value'] as double) - target).abs() < .00001 &&
                  ((f['paint_opacity'] as double) - target).abs() < .00001,
            ),
        isTrue,
      );
    } else {
      expect(frames.every((f) => f['native_flag'] == reduced), isTrue);
      if (reduced) {
        expect(
          frames.every(
            (f) => ((f['route_value'] as double) - target).abs() < .00001,
          ),
          isTrue,
        );
      } else {
        expect(
          frames.any(
            (f) =>
                (f['route_value'] as double) > 0 &&
                (f['route_value'] as double) < 1,
          ),
          isTrue,
        );
      }
    }
    return {
      'name': name,
      'opening': opening,
      'reduced': reduced,
      'live_switch': live,
      'nominal_ms': reduced
          ? 0
          : opening
          ? 240
          : 160,
      'frames': frames,
      'pre_action_frames': before,
    };
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..shouldPropagateDevicePointerEvents = true
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets(
    'production menus follow real Android input and live system motion',
    (t) async {
      expect(kProfileMode, isTrue);
      final navigatorKey = GlobalKey<NavigatorState>();
      late BuildContext source;
      MenuProbe? active;
      var selected = 0, cancelled = 0, opened = 0, observing = true;
      final cases = <Map<String, dynamic>>[];
      final result = <String, dynamic>{
        'production_components_only': true,
        'normal_release_acceptance': false,
        'no_repository_or_file_commands': true,
        'accessibility_injected': false,
        'cases': cases,
      };
      binding.reportData = {'menu_motion': result};
      final observer = MenuObserver((handle) {
        final probe = active;
        if (probe?.opening == true) probe!.handle = handle;
      });

      ({double opacity, double height, double item, bool present}) paint() {
        Element? menu;
        List<Widget>? path;
        void visit(Element element, List<Widget> ancestors) {
          if (menu != null) return;
          final w = element.widget;
          if (w is Semantics && w.properties.role == ui.SemanticsRole.menu) {
            menu = element;
            path = ancestors;
            return;
          }
          element.visitChildren((child) => visit(child, [...ancestors, w]));
        }

        final root = navigatorKey.currentContext;
        if (root is Element && root.mounted) visit(root, []);
        if (menu == null) {
          return (opacity: 0, height: 0, item: 0, present: false);
        }
        final opacity = path!.whereType<Opacity>().last.opacity;
        final height = path!
            .whereType<Align>()
            .lastWhere((w) => w.heightFactor != null)
            .heightFactor!;
        var item = 0.0;
        void items(Element e) {
          if (e.widget is Opacity) item = (e.widget as Opacity).opacity;
          e.visitChildren(items);
        }

        items(menu!);
        return (opacity: opacity, height: height, item: item, present: true);
      }

      void frame(Duration _) {
        if (!observing) return;
        final p = active, h = p?.handle;
        if (p != null && !p.done) {
          final paintState = paint();
          final stamp = SchedulerBinding
              .instance
              .currentSystemFrameTimeStamp
              .inMicroseconds;
          final native = ui
              .PlatformDispatcher
              .instance
              .accessibilityFeatures
              .disableAnimations;
          final sample = <String, dynamic>{
            'frame_us': stamp,
            'native_flag': native,
            'media_query_flag': MediaQuery.disableAnimationsOf(source),
            'selected_callbacks': selected,
            'cancelled_callbacks': cancelled,
            'menu_present': paintState.present,
            'paint_opacity': paintState.opacity,
            'height_factor': paintState.height,
            'last_item_opacity': paintState.item,
          };
          if (h == null ||
              (!p.opening && !h.popped) ||
              (p.opening && !paintState.present)) {
            p.before.add(sample);
          } else {
            final value = h.finished ? 0.0 : h.animation.value;
            sample['route_value'] = value;
            sample['route_finished'] = h.finished;
            p.frames.add(sample);
            final target = p.opening ? 1.0 : 0.0;
            p.done =
                (value - target).abs() < .00001 &&
                (paintState.opacity - target).abs() < .00001 &&
                (!p.live || native);
          }
        }
        WidgetsBinding.instance.addPostFrameCallback(frame);
      }

      WidgetsBinding.instance.addPostFrameCallback(frame);
      addTearDown(() async {
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
          'real Android reduced flag',
        );
      }

      Future<void> tap(String kind, {bool reduce = false}) async {
        final target = find.byKey(Key('native-menu-$kind'));
        expect(target.hitTestable(), findsOneWidget);
        await host(
          reduce ? 'tap_reduce' : 'tap',
          point: t.getCenter(target) * t.view.devicePixelRatio,
        );
      }

      Future<MenuHandle> enter(
        String name,
        String kind,
        bool reduced, {
        bool live = false,
      }) async {
        final p = MenuProbe('$name-entry', true, reduced, live: live);
        active = p;
        await tap(kind, reduce: live);
        await until(() => p.done, 'menu entry');
        cases.add(p.verify());
        active = null;
        expect(observer.last, same(p.handle));
        return p.handle!;
      }

      Future<void> leave(
        String name,
        MenuHandle h,
        bool reduced,
        String action, {
        bool live = false,
      }) async {
        final wasSelected = selected, wasCancelled = cancelled;
        final p = MenuProbe('$name-exit', false, reduced, live: live)
          ..handle = h;
        active = p;
        if (action == 'select') {
          final item = find.text('名称');
          expect(item.hitTestable(), findsOneWidget);
          await host(
            live ? 'tap_reduce' : 'tap',
            point: t.getCenter(item) * t.view.devicePixelRatio,
          );
        } else {
          await host(live ? 'back_reduce' : 'back');
        }
        await until(() => p.done, 'menu exit');
        cases.add(p.verify());
        active = null;
        await until(() => h.finished, 'menu overlay removed');
        expect(selected, wasSelected + (action == 'select' ? 1 : 0));
        expect(cancelled, wasCancelled + (action == 'cancel' ? 1 : 0));
        if (!reduced && !live) {
          expect(
            p.frames.any(
              (f) =>
                  (f['route_value'] as double) > 0 &&
                  f[action == 'select'
                          ? 'selected_callbacks'
                          : 'cancelled_callbacks'] ==
                      (action == 'select' ? wasSelected : wasCancelled) + 1,
            ),
            isTrue,
            reason: 'Callback must occur before the exit animation completes',
          );
        }
      }

      await configureApplicationWindow();
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          navigatorKey: navigatorKey,
          navigatorObservers: [observer],
          builder: (context, child) => PaperControlTheme(child: child!),
          home: Scaffold(
            appBar: AppBar(title: const Text('菜单动作检查')),
            body: StatefulBuilder(
              builder: (context, change) {
                source = context;
                Widget button(String kind) => PaperMenuButton<String>(
                  key: Key('native-menu-$kind'),
                  tooltip: kind == 'icon' ? '更多' : '排序',
                  initialValue: 'name',
                  routeSettings: RouteSettings(name: 'native-$kind'),
                  onOpened: () => change(() => opened++),
                  onSelected: (_) => change(() => selected++),
                  onCanceled: () => change(() => cancelled++),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'name', child: Text('名称')),
                    const PopupMenuItem(value: 'newest', child: Text('最近加入')),
                  ],
                  icon: kind == 'icon' ? const Icon(Icons.more_horiz) : null,
                  child: kind == 'text'
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('名称 ↓'),
                        )
                      : null,
                );
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [button('text'), button('icon')],
                      ),
                      const SizedBox(height: 24),
                      Text('打开 $opened · 选择 $selected · 取消 $cancelled'),
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
        for (final kind in ['icon', 'text']) {
          for (final reduced in [false, true]) {
            await configure(reduced);
            final name = 'round-$round-$kind-${reduced ? 'reduced' : 'normal'}';
            await host('begin', name: name);
            for (final action in ['cancel', 'select']) {
              final h = await enter('$name-$action', kind, reduced);
              await leave('$name-$action', h, reduced, action);
            }
            await host('end', name: name);
          }
          await configure(false);
          var name = 'round-$round-$kind-live-entry';
          await host('begin', name: name);
          final h = await enter(name, kind, false, live: true);
          await leave(name, h, true, 'cancel');
          await host('end', name: name);
          await configure(false);
          name = 'round-$round-$kind-live-exit';
          await host('begin', name: name);
          final h2 = await enter(name, kind, false);
          await leave(name, h2, false, 'cancel', live: true);
          await host('end', name: name);
        }
      }
      expect(cases.length, 72);
      expect(opened, 36);
      expect(selected, 12);
      expect(cancelled, 24);
      result.addAll({
        'complete': true,
        'opened': opened,
        'selected': selected,
        'cancelled': cancelled,
      });
    },
  );
}
