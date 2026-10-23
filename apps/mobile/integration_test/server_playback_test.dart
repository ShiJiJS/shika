import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/device_controls.dart';
import 'package:video_viewer/ui/playback_session.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';
import 'package:video_viewer/ui/sheets.dart';

import 'support/fixture.dart';

class LifecycleTrace extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      debugPrint('NATIVE_LIFECYCLE $state');
}

Future<void> deviceBackground(
  WidgetTester tester,
  PlaybackSession session,
) async {
  await tester.runAsync(() async {
    debugPrint('VV_E2E_DEVICE_BACKGROUND');
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while ((WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.paused ||
              session.debugPlayers.isNotEmpty) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(WidgetsBinding.instance.lifecycleState, AppLifecycleState.paused);
      expect(session.debugPlayers, isEmpty);
    } finally {
      debugPrint('VV_E2E_DEVICE_FOREGROUND');
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (WidgetsBinding.instance.lifecycleState !=
              AppLifecycleState.resumed &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(WidgetsBinding.instance.lifecycleState, AppLifecycleState.resumed);
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('E2E_RESUME')) {
    testWidgets(
      'I2 network round and nonzero position survive Android process restart',
      (t) async {
        final store = SecureCredentialStore(
          key: 'video_viewer.e2e.playback.v1',
        );
        final saved = await store.read();
        expect(saved, isNotNull);
        final observer = ServerApi(Uri.parse(fixtureBase), token: saved!.token);
        final before = await observer.json('GET', '/api/v1/playback');
        final traceBefore =
            (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
        final logins = traceBefore
            .where((r) => r['path'] == '/api/v1/auth/login')
            .length;
        final repo = ServerLibraryRepository(store, port: 9999);
        final preferences = UiPreferences(preloadAdjacent: false);
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(milliseconds: 300));
          repo.dispose();
          preferences.dispose();
          observer.close();
        });
        await t.pumpWidget(
          VideoViewerApp(
            repository: repo,
            preferences: preferences,
            initializeRepository: true,
          ),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!repo.snapshot.connected ||
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
            find.byKey(const Key('video-grid')).evaluate().isEmpty) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Android round did not reopen');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(repo.current!.name, '片段04.mp4');
        expect(repo.current!.id, before['current']['id']);
        expect(repo.playbackPosition, before['position']);
        expect(repo.playbackPosition, greaterThan(0));
        expect(repo.snapshot.query.folder, '/media/shorts/自然/花卉');
        final after = await observer.json('GET', '/api/v1/playback');
        expect(after['id'], before['id']);
        expect(
          find.byType(MovieStage),
          findsNothing,
          reason: 'restart retains fixed session metadata without autoplay',
        );
        final traceAfter =
            (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
        expect(
          traceAfter.where((r) => r['path'] == '/api/v1/auth/login').length,
          logins,
        );
        final target = find.byKey(Key('tile-${repo.current!.id}'));
        await t.ensureVisible(target);
        await t.tap(target);
        final pictureDeadline = DateTime.now().add(const Duration(seconds: 30));
        while (find.byType(VideoPlayer).evaluate().isEmpty) {
          if (DateTime.now().isAfter(pictureDeadline)) {
            fail('Explicit preview did not decode');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(repo.current!.id, before['current']['id']);
        final movieSession = t
            .widget<MovieStage>(find.byType(MovieStage))
            .session!;
        await observer.json('DELETE', '/api/v1/auth/session');
        await deviceBackground(t, movieSession);
        final expiryDeadline = DateTime.now().add(const Duration(seconds: 25));
        while (repo.snapshot.connected ||
            movieSession.debugPlayers.isNotEmpty ||
            find
                .byKey(const Key('video-preview-route'))
                .evaluate()
                .isNotEmpty) {
          if (DateTime.now().isAfter(expiryDeadline)) {
            fail('Native playback did not release its expired session');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        for (var i = 0; i < 30 && await store.read() != null; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(await store.read(), isNull);
        expect(find.text('连接你的视频库'), findsOneWidget);
      },
    );
    return;
  }
  late ServerLibraryRepository repo;
  late ServerApi observer;
  late UiPreferences preferences;
  PlaybackSession? session;
  var peakDecoders = 0;
  final stage = find.byKey(const Key('video-stage'));
  final surface = find.byKey(const Key('video-gesture-surface')).last;

  void audioBound() {
    final players = session?.debugPlayers ?? <VideoPlayerController>[];
    peakDecoders = peakDecoders < players.length
        ? players.length
        : peakDecoders;
    expect(players.length, lessThanOrEqualTo(3));
    expect(
      players.where((p) => p.value.isPlaying && p.value.volume > 0).length,
      lessThanOrEqualTo(1),
      reason: 'one audible native controller at a time',
    );
  }

  Future<void> until(
    WidgetTester t,
    bool Function() condition,
    String reason, {
    int seconds = 35,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (true) {
      await t.pump(const Duration(milliseconds: 80));
      audioBound();
      if (condition()) {
        await t.pump(const Duration(milliseconds: 80));
        if (condition()) return;
      }
      if (DateTime.now().isAfter(deadline)) {
        debugPrint(
          'VISIBLE_UI ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().join(' | ')}',
        );
        try {
          await fixture('/__fixture/checkpoint/error');
          await t.pump(const Duration(seconds: 1));
        } catch (_) {}
        fail('Timed out: $reason');
      }
    }
  }

  Future<void> idle(WidgetTester t) => until(
    t,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    'UI operation',
  );
  Future<void> tap(WidgetTester t, Finder target) async {
    bool exists() {
      try {
        return target.evaluate().isNotEmpty;
      } on StateError {
        return false;
      }
    }

    await until(t, exists, 'control appears');
    if (target.hitTestable().evaluate().isEmpty) await t.ensureVisible(target);
    await until(
      t,
      () =>
          target.hitTestable().evaluate().isNotEmpty &&
          target.evaluate().every(
            (e) => e.widget is! InkWell || (e.widget as InkWell).onTap != null,
          ),
      'control accepts taps',
    );
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 300));
    await idle(t);
  }

  Future<void> textTap(WidgetTester t, String text) =>
      tap(t, find.text(text).last);

  // The paused inline surface has a central play button above its gesture
  // detector. Exercise seeking/holding on exposed video, as a user would.
  Offset gesturePoint(WidgetTester t) {
    final rect = t.getRect(surface);
    return Offset(rect.left + rect.width * .3, rect.top + rect.height * .3);
  }

  Future<void> tapSurface(WidgetTester t) async {
    await t.tapAt(gesturePoint(t));
    await t.pump(const Duration(milliseconds: 300));
    await idle(t);
  }

  Future<void> dragSurface(WidgetTester t, Offset offset) =>
      t.dragFrom(gesturePoint(t), offset);
  Future<void> enter(WidgetTester t, {String? anchor}) async {
    await until(
      t,
      () => find.byKey(const Key('video-grid')).evaluate().isNotEmpty,
      'library before explicit preview',
    );
    if (anchor == null) {
      await textTap(t, '预览此范围');
    } else {
      final target = find.byKey(Key('tile-$anchor'));
      await t.scrollUntilVisible(
        target,
        400,
        scrollable: find.descendant(
          of: find.byKey(const Key('video-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      await tap(t, target);
    }
  }

  Future<void> nav(WidgetTester t, String page) async {
    final selected = repo.current?.id;
    if (find.byKey(const Key('video-preview-route')).evaluate().isNotEmpty) {
      if (page == 'browse') return;
      await tap(t, find.byKey(const Key('preview-back')));
      await until(t, () => stage.evaluate().isEmpty, 'leave secondary preview');
    }
    if (page == 'browse') {
      await nav(t, 'library');
      await enter(t, anchor: selected);
      return;
    }
    if (find.byKey(Key('nav-$page')).evaluate().isEmpty) {
      await tap(t, find.byTooltip('返回设置'));
    }
    await tap(t, find.byKey(Key('nav-$page')));
  }

  VideoPlayerController player(WidgetTester t) =>
      t.widget<VideoPlayer>(find.byType(VideoPlayer).last).controller;
  Future<void> ready(WidgetTester t) async {
    await until(
      t,
      () =>
          stage.evaluate().isNotEmpty &&
          find.byType(VideoPlayer).evaluate().isNotEmpty &&
          find
              .byWidgetPredicate(
                (w) =>
                    w is PlayerSurface &&
                    w.name == repo.current?.name &&
                    w.interactionsEnabled,
              )
              .evaluate()
              .isNotEmpty &&
          player(t).value.isInitialized &&
          player(t).dataSource == repo.current?.source.location &&
          t.widget<PageView>(stage).physics is! NeverScrollableScrollPhysics,
      'current authenticated video decoded',
    );
    session = t.widget<MovieStage>(find.byType(MovieStage)).session;
    audioBound();
  }

  Future<void> start(WidgetTester t, {bool preload = true}) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final credentials = SecureCredentialStore(
      key: 'video_viewer.e2e.playback.v1',
    );
    await credentials.clear();
    repo = ServerLibraryRepository(credentials, port: 8761);
    await repo.connect('10.0.2.2', 8761, fixturePassword);
    observer = ServerApi(
      Uri.parse(fixtureBase),
      token: (await credentials.read())!.token,
    );
    preferences = UiPreferences(preloadAdjacent: preload);
    session = null;
    peakDecoders = 0;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 400));
      repo.dispose();
      preferences.dispose();
      observer.close();
      session = null;
    });
  }

  Future<void> show(WidgetTester t) async {
    await t.pumpWidget(
      VideoViewerApp(repository: repo, preferences: preferences),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(MovieStage),
      findsNothing,
      reason: 'restored scope does not autoplay',
    );
    await enter(t);
  }

  Future<void> folder(WidgetTester t, List<String> names) async {
    await tap(t, find.byTooltip('选择文件夹'));
    await textTap(t, '媒体目录');
    for (final name in names) {
      await textTap(t, name);
    }
    await until(
      t,
      () =>
          t
              .widget<FilledButton>(
                find.descendant(
                  of: find.byType(FolderPicker),
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed !=
          null,
      'directory tree loaded',
    );
    await textTap(t, names.isEmpty ? '使用全部目录' : '使用此目录');
  }

  Future<void> clearScope(WidgetTester t) async {
    await nav(t, 'library');
    await tap(t, find.byTooltip('筛选视频'));
    await textTap(t, '清除条件');
    await textTap(t, '应用筛选');
    await t.enterText(find.byKey(const Key('video-search')), '');
  }

  Future<void> mode(WidgetTester t, String name) async {
    await tap(t, find.byKey(const Key('preview-scope')));
    await tap(
      t,
      find.byKey(
        Key('queue-order-${name == '顺序播放' ? 'sequential' : 'random'}'),
      ),
    );
    await tap(t, find.byTooltip('关闭面板'));
  }

  Future<void> choose(WidgetTester t, String id) async {
    await tap(t, find.byKey(const Key('preview-scope')));
    final queue = find.byKey(const Key('preview-queue'));
    await until(t, () => queue.evaluate().isNotEmpty, 'queue mounted');
    t.widget<ListView>(queue).controller!.jumpTo(0);
    await until(
      t,
      () => find
          .descendant(
            of: queue,
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .isEmpty,
      'queue metadata loaded',
    );
    final target = find.byKey(Key('queue-video-$id'));
    await t.scrollUntilVisible(
      target,
      300,
      scrollable: find.descendant(
        of: find.byKey(const Key('preview-queue')),
        matching: find.byType(Scrollable),
      ),
    );
    await tap(t, target);
    await ready(t);
  }

  Future<void> fling(WidgetTester t, {bool back = false}) async {
    await t.fling(
      stage,
      Offset(0, t.getSize(stage).height * (back ? .65 : -.65)),
      1200,
    );
    await t.pump(const Duration(milliseconds: 350));
    await idle(t);
  }

  bool controlsVisible(WidgetTester t) {
    final controls = find.byKey(const Key('playback-controls'));
    // A rebuilding fullscreen surface has no controls yet; it has not hidden them.
    if (controls.evaluate().isEmpty) return true;
    final opacity = find.ancestor(
      of: controls.last,
      matching: find.byType(AnimatedOpacity),
    );
    if (opacity.evaluate().isEmpty) return true;
    return t.widget<AnimatedOpacity>(opacity.first).opacity > 0;
  }

  Future<void> background(WidgetTester t) => deviceBackground(t, session!);

  testWidgets('I2 measure eight actual container/codec samples on Android', (
    t,
  ) async {
    await fixture('/__fixture/actions/formats');
    await start(t, preload: false);
    await repo.refresh();
    await repo.beginPreview(
      VideoEntryScope(query: VideoQuery(folder: '/media/camera/格式')),
      order: PlayOrder.sequential,
    );
    final all = await observer.json(
      'GET',
      '/api/v1/videos',
      query: {'limit': '200'},
    );
    final samples =
        (all['items'] as List)
            .cast<Map<String, dynamic>>()
            .where((v) => (v['path'] as String).startsWith('/media/camera/格式/'))
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
    expect(samples, hasLength(8));
    await show(t);
    await ready(t);
    final results = <Map<String, dynamic>>[];
    for (final sample in samples) {
      await nav(t, 'library');
      await until(
        t,
        () => find.byKey(const Key('video-grid')).evaluate().isNotEmpty,
        'format grid',
      );
      final target = find.byKey(Key('tile-${sample['id']}'));
      await t.scrollUntilVisible(
        target,
        400,
        scrollable: find.descendant(
          of: find.byKey(const Key('video-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      await tap(t, target);
      var openRetried = false;
      if (stage.evaluate().isEmpty &&
          find.textContaining('暂时无法连接服务').evaluate().isNotEmpty) {
        // A stale keep-alive can fail before the write reaches the service.
        // Exercise the same public action; the repository retains its key.
        openRetried = true;
        await tap(t, target);
      }
      await until(
        t,
        () =>
            find.byType(VideoPlayer).evaluate().isNotEmpty ||
            find.textContaining('无法解码').evaluate().isNotEmpty ||
            find.textContaining('暂时无法播放').evaluate().isNotEmpty,
        'native format result ${sample['name']}',
      );
      final decoded = find.byType(VideoPlayer).evaluate().isNotEmpty;
      final result = <String, dynamic>{
        'name': sample['name'],
        'container': sample['container'],
        'video_codec': sample['video_codec'],
        'audio_codec': sample['audio_codec'],
        'rotation': sample['rotation'],
        'decoded': decoded,
        'open_retried': openRetried,
      };
      if (decoded) {
        await ready(t);
        final controller = player(t);
        await until(
          t,
          () => controller.value.position.inMilliseconds > 80,
          'decoded frames advancing',
        );
        expect(controller.value.isLooping, isTrue);
        if (sample['name'] == 'h264.mov') {
          await until(
            t,
            () => controller.value.position.inMilliseconds > 600,
            'loop reaches the end',
          );
          await until(
            t,
            () => controller.value.position.inMilliseconds < 500,
            'loop returns to the beginning while playing',
          );
          expect(controller.value.isPlaying, isTrue);
          result['loop_observed'] = true;
        }
        await tapSurface(t);
        await until(
          t,
          () => !controller.value.isPlaying,
          'pause acknowledged by native player',
        );
        await t.drag(
          find.byKey(const Key('video-progress-touch')),
          const Offset(20, 0),
        );
        await t.pump(const Duration(milliseconds: 400));
        expect(
          controller.value.position.inMilliseconds,
          inInclusiveRange(0, controller.value.duration.inMilliseconds + 100),
        );
        // One-second AVI/MOV samples can land on the first keyframe. The long
        // unbuffered sample below independently verifies an actual forward seek.
        expect(controller.value.isPlaying, isFalse);
        result.addAll({
          'width': controller.value.size.width,
          'height': controller.value.size.height,
          'seek_ms': controller.value.position.inMilliseconds,
          'loop': controller.value.isLooping,
        });
        if (sample['name'] == 'rotated.mov' ||
            sample['name'] == 'portrait.mp4') {
          expect(
            controller.value.size.height,
            greaterThan(controller.value.size.width),
          );
        }
      } else {
        expect(find.text('重试'), findsOneWidget);
      }
      results.add(result);
      debugPrint('FORMAT_RESULT ${jsonEncode(result)}');
    }
    for (final name in [
      'portrait.mp4',
      'h264.mov',
      'rotated.mov',
      'h264.mkv',
    ]) {
      expect(
        results.singleWhere((r) => r['name'] == name)['decoded'],
        isTrue,
        reason: 'baseline network codec must actually decode',
      );
    }
    await fixture('/__fixture/checkpoint/formats');
    await t.pump(const Duration(seconds: 2));
    final trace =
        (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
    expect(
      trace.any(
        (r) =>
            (r['path'] as String).endsWith('/stream') &&
            r['method'] == 'GET' &&
            [200, 206].contains(r['status']) &&
            r['authenticated'],
      ),
      isTrue,
    );
  });

  testWidgets(
    'I2 exhaustion stays on the last clip and a new round is explicit',
    (t) async {
      await fixture('/__fixture/actions/formats');
      await start(t);
      await repo.refresh();
      await repo.beginPreview(
        VideoEntryScope(
          query: VideoQuery(
            folder: '/media/camera/格式',
            type: 'MOV',
            orientation: 'portrait',
          ),
        ),
        order: PlayOrder.sequential,
      );
      await show(t);
      await ready(t);
      expect(repo.playbackTotal, 1);
      final id = repo.current!.id;
      final before = await observer.json('GET', '/api/v1/playback');
      await fling(t);
      await until(
        t,
        () => find.text('本次范围已到末尾').evaluate().isNotEmpty,
        'explicit exhaustion',
      );
      expect(repo.current!.id, id);
      final exhausted = await observer.json('GET', '/api/v1/playback');
      expect(exhausted['finished'], isTrue);
      await tap(t, find.byKey(const Key('preview-restart')));
      await ready(t);
      final next = await observer.json('GET', '/api/v1/playback');
      expect(next['id'], before['id']);
      expect(next['finished'], isFalse);
      expect(repo.current!.id, id);
      expect(repo.snapshot.query.type, 'MOV');
      expect(repo.snapshot.query.orientation, 'portrait');
    },
  );

  testWidgets('I2 fullscreen gestures, rate selection and background recovery', (
    t,
  ) async {
    final lifecycle = LifecycleTrace();
    WidgetsBinding.instance.addObserver(lifecycle);
    addTearDown(() => WidgetsBinding.instance.removeObserver(lifecycle));
    await start(t, preload: false);
    await repo.beginPreview(
      VideoEntryScope(query: VideoQuery(folder: '/media/camera/旅行')),
      order: PlayOrder.sequential,
    );
    await show(t);
    await ready(t);
    final device = PlaybackDeviceControls();
    final levels = await device.levels();
    addTearDown(() async {
      await device.setVolume(levels['volume']!);
      await device.restoreBrightness();
    });
    await device.setVolume(.4);
    await device.setBrightness(.35);
    if (!player(t).value.isPlaying) await tapSurface(t);
    await until(
      t,
      () => player(t).value.isPlaying,
      'playing before fullscreen',
    );
    debugPrint(
      'FULLSCREEN_ENTER before_playing=${player(t).value.isPlaying} lifecycle=${WidgetsBinding.instance.lifecycleState}',
    );
    final beforeRotation = player(t);
    await textTap(t, '横向全屏');
    await until(
      t,
      () => t.view.physicalSize.width > t.view.physicalSize.height,
      'actual landscape',
    );
    await until(
      t,
      () =>
          find.byKey(const Key('fullscreen-exit')).evaluate().isNotEmpty &&
          find.byKey(const Key('playback-controls')).evaluate().isNotEmpty,
      'fullscreen surface mounted',
    );
    debugPrint(
      'FULLSCREEN_ENTER after_playing=${player(t).value.isPlaying} lifecycle=${WidgetsBinding.instance.lifecycleState}',
    );
    expect(
      player(t).value.isPlaying,
      isTrue,
      reason: 'entering fullscreen preserves play intent',
    );
    expect(
      identical(player(t), beforeRotation),
      isTrue,
      reason: 'rotation keeps the decoder and playback timeline',
    );
    await until(t, () => !controlsVisible(t), 'landscape controls hide');
    await tapSurface(t);
    expect(find.byKey(const Key('fullscreen-exit')), findsOneWidget);
    final rect = t.getRect(surface);
    final beforeLevels = await device.levels();
    await t.dragFrom(
      Offset(rect.left + rect.width * .2, rect.center.dy),
      const Offset(0, -95),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(
      (await device.levels())['brightness']!,
      greaterThan(beforeLevels['brightness']!),
    );
    await t.dragFrom(
      Offset(rect.left + rect.width * .8, rect.center.dy),
      const Offset(0, 95),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(
      (await device.levels())['volume']!,
      lessThan(beforeLevels['volume']!),
    );
    if (!controlsVisible(t)) {
      await tapSurface(t);
    }
    final ratePlayer = player(t);
    var observedRate = ratePlayer.value.playbackSpeed;
    void changedRate() {
      if (ratePlayer.value.playbackSpeed != observedRate) {
        observedRate = ratePlayer.value.playbackSpeed;
        debugPrint('FULLSCREEN_RATE $observedRate');
      }
    }

    ratePlayer.addListener(changedRate);
    addTearDown(() => ratePlayer.removeListener(changedRate));
    await tap(t, find.byTooltip('播放速度'));
    final rateChoice = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<double> && widget.value == 1.5,
    );
    await tap(t, rateChoice);
    await until(
      t,
      () => player(t).value.playbackSpeed == 1.5,
      'fullscreen base rate',
    );
    final landscapeHold = await t.startGesture(gesturePoint(t));
    await until(
      t,
      () => player(t).value.playbackSpeed == 2,
      'fullscreen hold rate',
    );
    await background(t);
    await landscapeHold.cancel();
    await until(
      t,
      () =>
          find.byType(VideoPlayer).evaluate().isNotEmpty &&
          player(t).value.isInitialized &&
          player(t).value.playbackSpeed == 1.5,
      'fullscreen reopens after releasing network resources',
    );
    expect(t.view.physicalSize.width, greaterThan(t.view.physicalSize.height));
    expect(player(t).value.isPlaying, isFalse);
    expect(
      (await device.levels())['windowBrightness'],
      levels['windowBrightness'],
    );
    if (!controlsVisible(t)) {
      await tapSurface(t);
    }
    await tap(t, find.byKey(const Key('fullscreen-exit')));
    await until(
      t,
      () => t.view.physicalSize.height > t.view.physicalSize.width,
      'portrait return',
    );
    expect(
      (await device.levels())['windowBrightness'],
      levels['windowBrightness'],
    );

    expect(t.takeException(), isNull);
  });

  testWidgets(
    'I2 real rounds, gestures, bounded preparation, failures and Docker recovery',
    (t) async {
      await fixture('/__fixture/actions/seek-sample');
      await start(t);
      await repo.refresh();
      final videos =
          (await observer.json(
                'GET',
                '/api/v1/videos',
                query: {'limit': '200'},
              ))['items']
              as List;
      final flowers = videos
          .where(
            (v) => (v['path'] as String).startsWith('/media/shorts/自然/花卉/'),
          )
          .map((v) => v['id'] as String)
          .toSet();
      final tags = <String>{};
      for (final name in ['播放验证甲', '播放验证乙']) {
        await repo.editTag(name: name);
        tags.add(
          repo.snapshot.tags.singleWhere((id) => repo.tagName(id) == name),
        );
      }
      await repo.setVideoTags(flowers, tags);
      await repo.beginPreview(
        VideoEntryScope(
          query: VideoQuery(
            folder: '/media/shorts/自然/花卉',
            tags: tags,
            orientation: 'portrait',
            type: 'MP4',
          ),
        ),
        order: PlayOrder.random,
      );
      await show(t);
      await ready(t);
      final round = await observer.json('GET', '/api/v1/playback');
      final entries =
          (await observer.json(
                'GET',
                '/api/v1/rounds/${round['id']}/entries',
                query: {'limit': '200'},
              ))['items']
              as List;
      final order = entries.map((r) => r['video']['id'] as String).toList();
      expect(order, hasLength(25));
      expect(order.toSet(), hasLength(25));
      await choose(t, order.first);
      expect(repo.current!.id, order.first);
      expect((round['scope']['tag_ids'] as List).toSet(), tags);
      final controller = player(t);
      await preferences.setDark(true);
      await until(
        t,
        () => preferences.dark && player(t).value.isPlaying,
        'dark theme preserves network playback',
      );
      expect(identical(player(t), controller), isTrue);
      await preferences.setDark(false);
      await until(
        t,
        () => !preferences.dark && player(t).value.isPlaying,
        'light theme preserves network playback',
      );
      await until(
        t,
        () => controller.value.position.inMilliseconds > 250,
        'network playback advancing',
      );
      final hold = await t.startGesture(gesturePoint(t));
      await until(
        t,
        () => controller.value.playbackSpeed == 2,
        'temporary native speed',
      );
      await hold.cancel();
      await until(
        t,
        () => controller.value.playbackSpeed == 1,
        'cancel restores speed',
      );
      await tapSurface(t);
      expect(controller.value.isPlaying, isFalse);
      final pausedHold = await t.startGesture(gesturePoint(t));
      await t.pump(const Duration(milliseconds: 650));
      expect(controller.value.isPlaying, isFalse);
      expect(find.byKey(const Key('hold-speed-hint')), findsNothing);
      await pausedHold.up();
      // Start away from the loop boundary so a clamped seek still has room.
      await dragSurface(t, Offset(-t.getSize(surface).width * 1.1, 0));
      await until(
        t,
        () => controller.value.position.inMilliseconds < 250,
        'paused seek returns to beginning',
      );
      final originalPosition = controller.value.position;
      await dragSurface(t, const Offset(120, 0));
      await until(
        t,
        () =>
            controller.value.position >
            originalPosition + const Duration(milliseconds: 500),
        'forward seek',
      );
      final forward = controller.value.position;
      await dragSurface(t, const Offset(-100, 0));
      await until(
        t,
        () => controller.value.position < forward,
        'backward seek',
      );
      expect(controller.value.isPlaying, isFalse);
      expect(
        find.byKey(const Key('inline-play')).hitTestable(),
        findsOneWidget,
      );
      await tapSurface(t);
      final short = await t.startGesture(t.getCenter(stage));
      await short.moveBy(const Offset(0, -24));
      await t.pump();
      await short.moveBy(const Offset(0, -50));
      await t.pump(const Duration(milliseconds: 150));
      expect(t.widget<PageView>(stage).controller!.page, greaterThan(0));
      expect(repo.playbackPosition, 0);
      await short.up();
      await until(
        t,
        () => t.widget<PageView>(stage).controller!.page!.abs() < .005,
        'short drag rebounds',
      );
      expect(repo.playbackPosition, 0);
      for (var index = 1; index <= 5; index++) {
        await fling(t);
        await until(
          t,
          () => repo.playbackPosition == index,
          'global round position $index',
        );
        await ready(t);
        expect(repo.current!.id, order[index]);
      }
      await fling(t, back: true);
      await until(t, () => repo.playbackPosition == 4, 'backtrack position');
      await ready(t);
      expect(repo.current!.id, order[4]);
      await fling(t);
      await until(
        t,
        () => repo.playbackPosition == 5,
        'forward after backtrack',
      );
      await ready(t);
      expect(repo.current!.id, order[5]);
      await fixture('/__fixture/checkpoint/playback');
      await t.pump(const Duration(seconds: 2));

      await choose(t, order.last);
      await tap(t, find.byKey(const Key('preview-next')));
      await until(
        t,
        () => find.byKey(const Key('preview-restart')).evaluate().isNotEmpty,
        'range end before restart',
      );
      await tap(t, find.byKey(const Key('preview-restart')));
      await ready(t);
      final fresh = await observer.json('GET', '/api/v1/playback');
      final freshEntries =
          (await observer.json(
                'GET',
                '/api/v1/rounds/${fresh['id']}/entries',
                query: {'limit': '200'},
              ))['items']
              as List;
      expect(fresh['id'], round['id']);
      expect(freshEntries.map((r) => r['video']['id']).toSet(), flowers);
      expect((fresh['scope']['tag_ids'] as List).toSet(), tags);

      await fixture('/__fixture/actions/slow-streams');
      await mode(t, '顺序播放');
      final sequential = await observer.json(
        'GET',
        '/api/v1/rounds/${fresh['id']}/entries',
        query: {'limit': '200'},
      );
      await choose(t, sequential['items'][0]['video']['id'] as String);
      await until(
        t,
        () =>
            repo.snapshot.order == PlayOrder.sequential &&
            repo.playbackPosition == 0,
        'sequential mode committed before sliding',
      );
      await fling(t);
      await until(
        t,
        () => repo.playbackPosition == 1,
        'paging during network initialization',
      );
      await ready(t);
      expect(repo.current!.name, '片段02.mp4');
      expect(repo.snapshot.query.tags, tags);
      expect(repo.snapshot.query.orientation, 'portrait');
      await fixture('/__fixture/actions/normal-streams');
      await nav(t, 'settings');
      await until(
        t,
        () => session!.debugPlayers.isEmpty,
        'leaving playback releases decoders',
      );
      await tap(t, find.byKey(const Key('preload-setting')));
      expect(preferences.preloadAdjacent, isFalse);
      final beforeDefaults = repo.playbackIdentity,
          beforeDefaultsPosition = repo.playbackPosition;
      await t.scrollUntilVisible(
        find.text('默认播放顺序'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await textTap(t, '默认播放顺序');
      await textTap(t, '顺序播放');
      expect(preferences.videoOrder, PlayOrder.sequential);
      expect(repo.playbackIdentity, beforeDefaults);
      expect(repo.playbackPosition, beforeDefaultsPosition);
      await nav(t, 'browse');
      await ready(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(session!.debugPlayers, hasLength(1));
      expect(repo.snapshot.order, PlayOrder.sequential);
      await mode(t, '随机播放');
      expect(preferences.videoOrder, PlayOrder.sequential);
      await mode(t, '顺序播放');
      await dragSurface(t, const Offset(40, 0));
      await tap(t, find.byTooltip('播放速度'));
      await textTap(t, '1.5×');
      await until(
        t,
        () => player(t).value.playbackSpeed == 1.5,
        'selected base rate',
      );
      final boostBeforeBackground = await t.startGesture(gesturePoint(t));
      await until(
        t,
        () => player(t).value.playbackSpeed == 2,
        'boost before background',
      );
      await background(t);
      await boostBeforeBackground.cancel();
      await ready(t);
      expect(player(t).value.isPlaying, isFalse);
      expect(player(t).value.playbackSpeed, 1.5);
      await tapSurface(t);

      await clearScope(t);
      await fixture('/__fixture/actions/slow-streams');
      await folder(t, ['端到端相机', '长视频']);
      await enter(t);
      await ready(t);
      await tapSurface(t);
      expect(player(t).value.isPlaying, isFalse);
      final bufferedBefore = player(t).value.buffered
          .map((b) => b.end.inMilliseconds)
          .fold<int>(0, (a, b) => a > b ? a : b);
      await dragSurface(t, const Offset(200, 0));
      await until(
        t,
        () => player(t).value.position.inMilliseconds > 45000,
        'seek beyond buffered media',
      );
      final seekPosition = player(t).value.position.inMilliseconds;
      expect(seekPosition, greaterThan(bufferedBefore));
      await tapSurface(t);
      await until(
        t,
        () => player(t).value.position.inMilliseconds > seekPosition + 250,
        'new range decodes and advances',
      );
      final rangeTrace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      final range = rangeTrace.lastWhere(
        (r) =>
            (r['path'] as String).endsWith('/stream') &&
            r['method'] == 'GET' &&
            r['range'] != null &&
            r['status'] == 206,
      );
      expect(range['authenticated'], isTrue);
      debugPrint(
        'RANGE_RESULT ${jsonEncode({'range': range['range'], 'status': 206, 'seek_ms': seekPosition, 'buffered_before_ms': bufferedBefore})}',
      );
      await fixture('/__fixture/actions/normal-streams');

      await clearScope(t);
      await folder(t, ['端到端相机', '旅行']);
      await enter(t);
      await mode(t, '顺序播放');
      await ready(t);
      expect(repo.current!.name, '横版片段.mp4');
      final beforeOutage = await observer.json('GET', '/api/v1/playback');
      await fixture('/__fixture/checkpoint/outage');
      var down = false;
      for (var i = 0; i < 80 && !down; i++) {
        try {
          await fixture('/health', method: 'GET');
        } on IOException {
          down = true;
        }
        if (!down) await t.pump(const Duration(milliseconds: 100));
      }
      expect(down, isTrue);
      await background(t);
      await until(
        t,
        () =>
            find.textContaining('无法连接').evaluate().isNotEmpty ||
            find.textContaining('连接超时').evaluate().isNotEmpty ||
            find.textContaining('视频加载较慢').evaluate().isNotEmpty ||
            find.textContaining('暂时无法播放').evaluate().isNotEmpty,
        'explain network failure',
      );
      expect(repo.current!.id, beforeOutage['current']['id']);
      var up = false;
      for (var i = 0; i < 160 && !up; i++) {
        try {
          await fixture('/health', method: 'GET');
          up = true;
        } on IOException {
          await t.pump(const Duration(milliseconds: 150));
        }
      }
      expect(up, isTrue);
      await textTap(t, '重试');
      await ready(t);
      final afterOutage = await observer.json('GET', '/api/v1/playback');
      expect(afterOutage['id'], beforeOutage['id']);
      expect(afterOutage['position'], beforeOutage['position']);
      expect(afterOutage['current']['id'], beforeOutage['current']['id']);
      await fixture('/__fixture/checkpoint/recovered');
      await t.pump(const Duration(seconds: 2));

      await clearScope(t);
      await folder(t, ['端到端短视频', '自然', '花卉']);
      await until(
        t,
        () => find.byKey(const Key('video-search')).evaluate().isNotEmpty,
        'library search',
      );
      await t.enterText(find.byKey(const Key('video-search')), '片段');
      await until(
        t,
        () => find.text('25 个视频').evaluate().isNotEmpty,
        'target for external removal',
      );
      final currentId = flowers.firstWhere(
        (id) => videos.any((v) => v['id'] == id && v['name'] == '片段03.mp4'),
      );
      await enter(t, anchor: currentId);
      await ready(t);
      await fixture('/__fixture/actions/remove');
      await background(t);
      await until(
        t,
        () => repo.current?.id != currentId,
        'server skips unavailable source',
      );
      await ready(t);
      expect(find.text('视频已不可用，已更新当前播放范围'), findsOneWidget);
      debugPrint(
        'PLAYBACK_RESULT ${jsonEncode({'peak_decoders': peakDecoders, 'samples_in_round': order.length, 'swipes': 7, 'preload_disabled': true, 'background_released': true, 'docker_restart_preserved_round': true, 'missing_source_skipped': true})}',
      );
      await fixture('/__fixture/checkpoint/done');
      expect(t.takeException(), isNull);
    },
  );
}
