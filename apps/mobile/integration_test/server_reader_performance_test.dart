import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/features/packs/pack_reading_session.dart';
import 'package:video_viewer/features/packs/reader_images.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

Future<void> checkpoint(String name, Map<String, dynamic> sample) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(
      Uri.parse('http://10.0.2.2:8774/checkpoint'),
    );
    request.headers.set('X-Fixture-Key', 'reader-performance-owned-only');
    request.headers.contentType = ContentType.json;
    final payload = utf8.encode(jsonEncode({'name': name, 'sample': sample}));
    request.contentLength = payload.length;
    request.add(payload);
    final response = await request.close().timeout(const Duration(seconds: 30));
    expect(response.statusCode, 200);
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets('profile complex-photo cold opens, adjacent flips and 500 pages', (
    t,
  ) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'Do not report debug timing as profile',
    );
    final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8773);
    final prefs = UiPreferences(preloadAdjacent: false);
    const trialCount = int.fromEnvironment(
      'READER_BENCH_TRIALS',
      defaultValue: 30,
    );
    expect([1, 30], contains(trialCount));
    final samples = <Map<String, dynamic>>[];
    final frames = <List<int>>[];
    final peaks = <String, int>{
      'providers': 0,
      'estimated_bytes': 0,
      'metadata': 0,
      'cache_bytes': 0,
      'pending': 0,
      'live': 0,
      'decoded_pixels': 0,
    };
    var phase = 'prepare';
    final result = <String, dynamic>{
      'mode': 'profile',
      'trial_count': trialCount,
      'final_matrix': trialCount == 30,
      'poll_ms': 8,
      'timing_definition': 'injected tap to decoded current RawImage and endOfFrame; excludes durable progress acknowledgement',
      'cache_definition': 'Flutter cache cleared per open; server OS/filesystem caches unchanged',
      'samples': samples,
      'peaks': peaks,
      'frame_timings_us': frames,
    };
    binding.reportData = {'reader_benchmark': result};
    PackReaderPageState? observedReader;
    PackReaderPageState reader() {
      final value = t.state<PackReaderPageState>(find.byType(PackReaderPage));
      observedReader = value;
      return value;
    }

    bool present() => find.byType(PackReaderPage).evaluate().isNotEmpty;
    void observe(List<FrameTiming> values) {
      for (final v in values) {
        frames.add([
          v.buildDuration.inMicroseconds,
          v.rasterDuration.inMicroseconds,
          v.totalSpan.inMicroseconds,
        ]);
      }
      final cache = PaintingBinding.instance.imageCache;
      for (final e in {
        'cache_bytes': cache.currentSizeBytes,
        'pending': cache.pendingImageCount,
        'live': cache.liveImageCount,
      }.entries) {
        peaks[e.key] = max(peaks[e.key]!, e.value);
      }
      // Timings callbacks run outside the tester's guarded async scope.
      // Use a state captured by the awaited driver, never t.state/find here.
      final r = observedReader;
      if (r != null && r.mounted) {
        peaks['providers'] = max(peaks['providers']!, r.images.length);
        peaks['estimated_bytes'] = max(
          peaks['estimated_bytes']!,
          r.images.estimatedBytes,
        );
        peaks['metadata'] = max(peaks['metadata']!, r.session.pages.length);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(observe);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      prefs.dispose();
      SchedulerBinding.instance.removeTimingsCallback(observe);
    });
    Future<void> until(
      bool Function() done,
      String why, {
      int seconds = 60,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          final state = present() ? reader().session : null;
          final diagnostic = <String, dynamic>{
            'phase': phase,
            'waiting_for': why,
            'present': present(),
            'index': state?.index,
            'opened': state?.opened,
            'busy': state?.busy,
            'pending': state?.pendingKind,
            'needs_reload': state?.needsReload,
            'unsaved': state?.unsaved,
            'live': state?.live,
            'error': state?.error,
            'page_error': state?.pageError,
            'page_id': state?.currentPage?.id,
            'offset_ratio': state?.offsetRatio,
          };
          result['failure'] = diagnostic;
          debugPrint('READER_BENCH_FAILURE:${jsonEncode(diagnostic)}');
          await checkpoint('failure', diagnostic);
          fail('$phase timeout: $why');
        }
        await t.pump(const Duration(milliseconds: 8));
      }
      expect(t.takeException(), isNull);
    }

    List<RawImage> decoded() {
      if (!present() || reader().session.currentPage == null) return [];
      final id = reader().session.currentPage!.id;
      final page = find.byWidgetPredicate(
        (w) => w is ReaderImage && !w.thumbnail && w.page.id == id,
      );
      final canvas = t.getRect(find.byKey(const Key('reader-canvas')));
      return find
          .descendant(of: page, matching: find.byType(RawImage))
          .evaluate()
          .where((e) {
            final box = e.renderObject;
            return (e.widget as RawImage).image != null &&
                box is RenderBox &&
                box.hasSize &&
                box.attached &&
                (box.localToGlobal(Offset.zero) & box.size).overlaps(canvas);
          })
          .map((e) => e.widget as RawImage)
          .toList();
    }

    Future<void> imageReady() async {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (true) {
        await until(
          () =>
              present() &&
              !reader().session.loadingPages &&
              decoded().isNotEmpty,
          'visible current decoded image',
        );
        final page = reader().session.currentPage!.id;
        await SchedulerBinding.instance.endOfFrame;
        if (present() &&
            !reader().session.loadingPages &&
            reader().session.currentPage?.id == page &&
            decoded().isNotEmpty) {
          return;
        }
        if (DateTime.now().isAfter(deadline)) {
          fail('Current decoded frame did not stabilize');
        }
      }
    }

    Future<void> settled() => until(
      () =>
          !present() ||
          (!reader().session.inputBlocked && !reader().session.unsaved),
      'acknowledged state',
    );
    Future<void> ready(Finder target) async {
      await settled();
      // Session acknowledgement may precede the frame that enables controls.
      await t.pump();
      await until(() => target.evaluate().length == 1, 'unique $target');
      await t.ensureVisible(target);
      await until(() {
        if (target.hitTestable().evaluate().length != 1) return false;
        final buttons = find.ancestor(
          of: target,
          matching: find.byType(IconButton),
        );
        return buttons.evaluate().every(
          (element) => (element.widget as IconButton).onPressed != null,
        );
      }, 'rendered enabled hit $target');
    }

    Future<void> tap(Finder target) async {
      await ready(target);
      await t.tap(target);
      await t.pump();
    }

    Future<Map<String, dynamic>> sample(
      String kind, {
      int? trial,
      Stopwatch? clock,
    }) async {
      // The manifest window can reflow in post-frame callbacks. Capture the
      // frame and its state together, after that async boundary, not before it.
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (true) {
        await imageReady();
        if (decoded().isNotEmpty) break;
        if (DateTime.now().isAfter(deadline)) {
          fail('No decoded current frame to sample');
        }
      }
      final r = reader(),
          s = r.session,
          cache = PaintingBinding.instance.imageCache;
      final sizes = decoded()
          .map((w) => [w.image!.width, w.image!.height])
          .toList();
      expect(sizes, isNotEmpty);
      for (final size in sizes) {
        peaks['decoded_pixels'] = max(
          peaks['decoded_pixels']!,
          size[0] * size[1],
        );
        expect(size[0] * size[1], lessThanOrEqualTo(2105000));
      }
      expect(r.images.length, lessThanOrEqualTo(ReaderImages.maximumEntries));
      expect(
        r.images.estimatedBytes,
        lessThanOrEqualTo(ReaderImages.maximumBytes),
      );
      expect(
        s.pages.length,
        lessThanOrEqualTo(PackReadingSession.maximumPages),
      );
      if (s.error.isNotEmpty || s.pageError.isNotEmpty) {
        final diagnostic = <String, dynamic>{
          'phase': phase,
          'sample_kind': kind,
          'index': s.index,
          'opened': s.opened,
          'busy': s.busy,
          'pending': s.pendingKind,
          'needs_reload': s.needsReload,
          'unsaved': s.unsaved,
          'live': s.live,
          'error': s.error,
          'page_error': s.pageError,
          'page_id': s.currentPage?.id,
          'offset_ratio': s.offsetRatio,
          'window': [s.windowStart, s.windowEnd],
        };
        result['failure'] = diagnostic;
        debugPrint('READER_BENCH_FAILURE:${jsonEncode(diagnostic)}');
        await checkpoint('failure', diagnostic);
      }
      expect(s.error, isEmpty);
      expect(s.pageError, isEmpty);
      final v = <String, dynamic>{
        'phase': kind,
        'trial': trial,
        'latency_us': clock?.elapsedMicroseconds,
        'pack_id': s.range!.pack!.id,
        'page_id': s.currentPage!.id,
        'index': s.index,
        'source_dimensions': [s.currentPage!.width, s.currentPage!.height],
        'decoded': sizes,
        'providers': r.images.length,
        'estimated_bytes': r.images.estimatedBytes,
        'metadata': s.pages.length,
        'window': [s.windowStart, s.windowEnd],
        'cache_bytes': cache.currentSizeBytes,
        'pending': cache.pendingImageCount,
        'live': cache.liveImageCount,
      };
      samples.add(v);
      return v;
    }

    Future<void> step(
      int expected, {
      bool measured = false,
      String? kind,
      int? trial,
    }) async {
      phase = '${kind ?? 'setup'}-step-$expected-trial-${trial ?? -1}';
      final tooltip = expected > reader().session.index ? '下一张' : '上一张';
      final button = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      );
      await ready(button);
      await until(
        () => t.widget<IconButton>(button).onPressed != null,
        'enabled $tooltip',
      );
      final clock = Stopwatch()..start();
      await t.tap(button);
      await until(
        () => reader().session.index == expected,
        'target index $expected',
      );
      await imageReady();
      if (measured) {
        final captured = await sample(kind!, trial: trial, clock: clock);
        expect(captured['index'], expected);
      }
      clock.stop();
      await settled();
    }

    Future<void> firstPage() async {
      await settled();
      if (reader().session.index != 0) {
        final slider = find.byType(Slider);
        await ready(slider);
        await until(
          () => t.widget<Slider>(slider).onChanged != null,
          'rendered enabled slider',
        );
        final element = t.element(slider), value = t.widget<Slider>(slider);
        final theme = SliderTheme.of(element);
        final box = element.findRenderObject()! as RenderBox;
        final track = (theme.trackShape ?? const RoundedRectSliderTrackShape())
            .getPreferredRect(
              parentBox: box,
              sliderTheme: theme,
              isEnabled: true,
            );
        final rtl = Directionality.of(element) == TextDirection.rtl;
        final fraction = (value.value - value.min) / (value.max - value.min);
        final thumb = box.localToGlobal(
          Offset(
            track.left + track.width * (rtl ? 1 - fraction : fraction),
            track.center.dy,
          ),
        );
        // Start on the real thumb. A center drag can miss it with slideThumb
        // interaction, and a session acknowledgement can precede its UI rebuild.
        await t.dragFrom(thumb, Offset((rtl ? 1 : -1) * track.width, 0));
        await until(
          () => reader().session.index == 0,
          'reset fixture page via slider',
        );
        await imageReady();
        await settled();
      }
    }

    await repo.connect(
      'http://10.0.2.2',
      8773,
      'reader-performance-owned-only',
    );
    final catalog = await repo.loadPacks(PackQuery());
    expect(catalog.total, 3);
    final long = catalog.items.singleWhere((v) => v.name == '01-photo-long');
    expect(long.pageCount, 500);
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: prefs,
        initializeRepository: false,
      ),
    );
    await tap(find.text('图包'));
    for (final label in ['4k', '8k']) {
      final pack = catalog.items.singleWhere(
        (v) => v.name == '0${label == '4k' ? 2 : 3}-photo-$label',
      );
      final tile = find.byKey(Key('pack-tile-${pack.id}'));
      // Warm the server normally, then measure Flutter-cache-cold opens.
      await tap(tile);
      await imageReady();
      await firstPage();
      await tap(find.byTooltip('返回来源'));
      await until(() => !present(), 'warmup reader disposed');
      for (var trial = 0; trial < trialCount; trial++) {
        phase = '$label-open-$trial';
        await ready(tile);
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        final clock = Stopwatch()..start();
        await t.tap(tile);
        await imageReady();
        final v = await sample('$label-open', trial: trial, clock: clock);
        clock.stop();
        expect(v['index'], 0);
        if (trial == 0 || trial == trialCount - 1) {
          await checkpoint('$label-open-$trial', v);
        }
        await step(1, measured: true, kind: '$label-adjacent', trial: trial);
        await step(0);
        await tap(find.byTooltip('返回来源'));
        await until(() => !present(), 'reader disposed');
        debugPrint(
          'READER_BENCH_TRIAL:$label:$trial:${clock.elapsedMicroseconds}',
        );
      }
    }
    phase = 'long-open';
    await tap(find.byKey(Key('pack-tile-${long.id}')));
    await imageReady();
    await firstPage();
    final rangeId = reader().session.range!.id;
    await tap(find.byTooltip('阅读设置'));
    await tap(find.widgetWithText(ChoiceChip, '纵向拼接'));
    await tap(find.byKey(const Key('reader-settings-done')));
    await imageReady();
    expect(reader().session.index, 0);
    await checkpoint('long-start', await sample('long-start'));
    final reached = <int>{0};
    var gestures = 0, stalls = 0, previous = 0;
    final scrollClock = Stopwatch()..start();
    while (reader().session.index < 499) {
      phase = 'long-scroll-${reader().session.index}';
      await t.drag(
        find.byKey(const Key('reader-vertical')),
        const Offset(0, -240),
      );
      final captured = await sample('long-scroll');
      final index = captured['index'] as int;
      reached.add(index);
      gestures++;
      stalls = index == previous ? stalls + 1 : 0;
      previous = index;
      expect(stalls, lessThan(20));
      expect(gestures, lessThan(2000));
      if (index > 0 &&
          index % 100 == 0 &&
          !samples.any((v) => v['phase'] == 'long-page-$index')) {
        await checkpoint('long-page-$index', await sample('long-page-$index'));
      }
    }
    scrollClock.stop();
    expect(reached.length, 500);
    expect(reader().session.range!.id, rangeId);
    expect(await reader().session.flush(), isTrue);
    await checkpoint('long-end', await sample('long-end'));
    final page = reader().session.currentPage!.id;
    await tap(find.byTooltip('阅读设置'));
    await tap(find.widgetWithText(ChoiceChip, '横向翻页'));
    await tap(find.byKey(const Key('reader-settings-done')));
    await imageReady();
    expect(reader().session.currentPage!.id, page);
    await checkpoint(
      'long-horizontal-end',
      await sample('long-horizontal-end'),
    );
    await tap(find.byTooltip('返回来源'));
    await until(() => !present(), 'final return');
    result.addAll({
      'completed': true,
      'reached': reached.toList()..sort(),
      'gestures': gestures,
      'scroll_us': scrollClock.elapsedMicroseconds,
    });
    await checkpoint('verified', {
      'completed': true,
      'samples': samples.length,
      'peaks': peaks,
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}
