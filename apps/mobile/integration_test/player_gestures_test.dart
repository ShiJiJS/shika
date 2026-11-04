import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late DemoLibraryRepository repo;
  final stage = find.byKey(const Key('video-stage'));
  final surface = find.byKey(const Key('video-gesture-surface')).last;
  VideoPlayerController player(WidgetTester t) =>
      t.widget<VideoPlayer>(find.byType(VideoPlayer).last).controller;
  double page(WidgetTester t) => t.widget<PageView>(stage).controller!.page!;

  Future<void> until(WidgetTester t, bool Function() ready) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail('Player state timed out');
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> ready(WidgetTester t) => until(
    t,
    () =>
        t.widget<PageView>(stage).physics is! NeverScrollableScrollPhysics &&
        find
            .byWidgetPredicate(
              (w) =>
                  w is PlayerSurface &&
                  w.name == repo.current?.name &&
                  w.interactionsEnabled,
            )
            .evaluate()
            .isNotEmpty &&
        find.byType(VideoPlayer).evaluate().isNotEmpty &&
        player(t).value.isInitialized &&
        player(t).value.isPlaying,
  );

  Future<void> start(
    WidgetTester t, {
    DemoScenario scenario = DemoScenario.normal,
    String? video,
  }) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    repo = DemoLibraryRepository(MemoryStateStore(), scenario: scenario);
    await repo.initialize();
    if (video != null) await repo.openVideo(video);
    await t.pumpWidget(ShikaApp(repository: repo));
    await ready(t);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 300));
      repo.dispose();
    });
  }

  Future<void> tap(WidgetTester t, Finder target) async {
    await until(t, () => target.hitTestable().evaluate().isNotEmpty);
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> holdAndRelease(WidgetTester t, double original) async {
    final id = repo.current!.id;
    final press = await t.startGesture(t.getCenter(surface));
    await until(
      t,
      () => find.byKey(const Key('hold-speed-hint')).evaluate().isNotEmpty,
    );
    await until(t, () => player(t).value.playbackSpeed == 2);
    expect(player(t).value.isPlaying, isTrue);
    // Once a long press owns the gesture, movement must not change videos.
    await press.moveBy(const Offset(0, -90));
    await t.pump(const Duration(milliseconds: 150));
    expect(repo.current!.id, id);
    await press.up();
    await until(
      t,
      () =>
          player(t).value.playbackSpeed == original &&
          find.byKey(const Key('hold-speed-hint')).evaluate().isEmpty,
    );
    expect(find.byKey(const Key('hold-speed-hint')), findsNothing);
    expect(player(t).value.isPlaying, isTrue);
  }

  testWidgets(
    'paging follows the finger, cancels short drags and restores hold speed',
    (t) async {
      await start(t);
      final first = repo.current!.id;
      await holdAndRelease(t, 1);
      await tap(t, surface);
      expect(player(t).value.isPlaying, isFalse);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
      final pausedHold = await t.startGesture(t.getCenter(surface));
      await t.pump(const Duration(milliseconds: 650));
      expect(player(t).value.isPlaying, isFalse);
      expect(player(t).value.playbackSpeed, 1);
      expect(find.byKey(const Key('hold-speed-hint')), findsNothing);
      await pausedHold.up();
      await t.drag(surface, const Offset(70, 0));
      await t.pump(const Duration(milliseconds: 300));
      await tap(t, find.byTooltip('播放速度'));
      await tap(t, find.text('1.5×').last);
      await until(t, () => player(t).value.playbackSpeed == 1.5);
      await tap(t, surface);
      await holdAndRelease(t, 1.5);

      final short = await t.startGesture(t.getCenter(stage));
      await short.moveBy(const Offset(0, -24));
      await t.pump();
      await short.moveBy(const Offset(0, -65));
      await t.pump(const Duration(milliseconds: 150));
      expect(page(t), greaterThan(.01));
      expect(page(t), lessThan(.4));
      expect(repo.current!.id, first);
      await short.up();
      await until(t, () => page(t).abs() < .001);
      expect(repo.current!.id, first);

      final height = t.getSize(stage).height;
      final drag = await t.startGesture(
        t.getCenter(stage) + Offset(0, height * .2),
      );
      await drag.moveBy(const Offset(0, -24));
      await t.pump();
      await drag.moveBy(Offset(0, -height * .65));
      await t.pump(const Duration(milliseconds: 150));
      expect(page(t), inExclusiveRange(.5, .9));
      expect(repo.current!.id, first); // Commit only after settling.
      await drag.up();
      await until(t, () => repo.snapshot.position == 1);
      await ready(t);
      expect(page(t), closeTo(1, .001));
      expect(find.byType(VideoPlayer), findsOneWidget);
      await t.fling(stage, Offset(0, height * .65), 1200);
      await until(t, () => repo.current!.id == first);
      await ready(t);
      expect(page(t), closeTo(0, .001));
      // Cancelled native pointers also restore the selected rate.
      final cancel = await t.startGesture(t.getCenter(surface));
      await until(t, () => player(t).value.playbackSpeed == 2);
      await cancel.cancel();
      await until(t, () => player(t).value.playbackSpeed == 1.5);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'paging preserves boundaries and returns to the saved page on failure',
    (t) async {
      await start(t);
      final height = t.getSize(stage).height;
      await t.fling(stage, Offset(0, height * .6), 1200);
      await until(t, () => page(t).abs() < .001);
      expect(repo.snapshot.position, 0);
      await repo.openVideo(repo.snapshot.round.last);
      await t.pump();
      await ready(t);
      await until(
        t,
        () => (page(t) - (repo.snapshot.round.length - 1)).abs() < .001,
      );
      await t.fling(stage, Offset(0, -height * .6), 1200);
      await until(t, () => find.text('本轮已看完').evaluate().isNotEmpty);
      expect(repo.snapshot.position, repo.snapshot.round.length - 1);
      await tap(t, find.text('开始新一轮'));
      await until(t, () => repo.snapshot.position == 0);
      await ready(t);
      await until(t, () => page(t).abs() < .001);
      await repo.reset(scenario: DemoScenario.storageFailure);
      await t.pump();
      await ready(t);
      final first = repo.current!.id;
      await t.fling(stage, Offset(0, -height * .6), 1200);
      await until(t, () => find.textContaining('保存失败').evaluate().isNotEmpty);
      await until(t, () => page(t).abs() < .001);
      expect(repo.current!.id, first);
      expect(player(t).value.isPlaying, isTrue);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'landscape uses the same hold gesture and restores on backgrounding',
    (t) async {
      await start(t, video: 'v2');
      final controller = player(t);
      await tap(t, find.text('横屏'));
      await until(
        t,
        () => t.view.physicalSize.width > t.view.physicalSize.height,
      );
      await until(
        t,
        () => find.byKey(const Key('fullscreen-exit')).evaluate().isNotEmpty,
      );
      await holdAndRelease(t, 1);
      final hold = await t.startGesture(t.getCenter(surface));
      await until(t, () => controller.value.playbackSpeed == 2);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await until(
        t,
        () =>
            controller.value.playbackSpeed == 1 && !controller.value.isPlaying,
      );
      expect(controller.value.isPlaying, isFalse);
      await hold.cancel();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await until(
        t,
        () =>
            find.byType(VideoPlayer).evaluate().isNotEmpty &&
            find
                .byWidgetPredicate(
                  (w) => w is PlayerSurface && w.interactionsEnabled,
                )
                .evaluate()
                .isNotEmpty,
      );
      final exit = find.byKey(const Key('fullscreen-exit'));
      final opacity = t
          .widget<AnimatedOpacity>(
            find
                .ancestor(of: exit, matching: find.byType(AnimatedOpacity))
                .first,
          )
          .opacity;
      if (opacity == 0) await tap(t, surface);
      await tap(t, exit);
      await until(
        t,
        () => t.view.physicalSize.height > t.view.physicalSize.width,
      );
      expect(repo.current!.id, 'v2');
      expect(identical(player(t), controller), isTrue);
      expect(controller.value.playbackSpeed, 1);
      expect(t.takeException(), isNull);
    },
  );
}
