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
    request.write(jsonEncode({'name': name, 'sample': sample}));
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
  testWidgets(
    'profile complex-photo cold opens, adjacent flips and 500 pages',
    (t) async {
      expect(
        kProfileMode,
        isTrue,
        reason: 'Do not report debug timing as profile',
      );
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8773);
      final prefs = UiPreferences(preloadAdjacent: false);
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
          if (DateTime.now().isAfter(deadline)) fail('$phase timeout: $why');
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
        await until(
          () =>
              present() &&
              !reader().session.loadingPages &&
              decoded().isNotEmpty,
          'visible current decoded image',
        );
        await SchedulerBinding.instance.endOfFrame;
      }

      Future<void> settled() => until(
        () =>
            !present() ||
            (!reader().session.inputBlocked && !reader().session.unsaved),
        'acknowledged state',
      );
      Future<void> ready(Finder target) async {
        await settled();
        await until(() => target.evaluate().length == 1, 'unique $target');
        await t.ensureVisible(target);
        await until(
          () => target.hitTestable().evaluate().length == 1,
          'hit $target',
        );
      }

      Future<void> tap(Finder target) async {
        await ready(target);
        await t.tap(target);
        await t.pump();
      }

      Map<String, dynamic> sample(String kind, {int? trial, int? micros}) {
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
        expect(s.error, isEmpty);
        expect(s.pageError, isEmpty);
        final v = <String, dynamic>{
          'phase': kind,
          'trial': trial,
          'latency_us': micros,
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
        final tooltip = expected > reader().session.index ? '下一张' : '上一张';
        final button = find.byTooltip(tooltip);
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
        clock.stop();
        if (measured) {
          sample(kind!, trial: trial, micros: clock.elapsedMicroseconds);
        }
        await settled();
      }

      Future<void> firstPage() async {
        await settled();
        if (reader().session.index != 0) {
          final slider = find.byType(Slider);
          await ready(slider);
          final rect = t.getRect(slider);
          await t.tapAt(rect.centerLeft + const Offset(1, 0));
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
        for (var trial = 0; trial < 30; trial++) {
          phase = '$label-open-$trial';
          await ready(tile);
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          final clock = Stopwatch()..start();
          await t.tap(tile);
          await imageReady();
          clock.stop();
          expect(reader().session.index, 0);
          final v = sample(
            '$label-open',
            trial: trial,
            micros: clock.elapsedMicroseconds,
          );
          if (trial == 0 || trial == 29) {
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
      await checkpoint('long-start', sample('long-start'));
      final reached = <int>{0};
      var gestures = 0, stalls = 0, previous = 0;
      final scrollClock = Stopwatch()..start();
      while (reader().session.index < 499) {
        phase = 'long-scroll-${reader().session.index}';
        await t.drag(
          find.byKey(const Key('reader-vertical')),
          const Offset(0, -240),
        );
        await imageReady();
        final index = reader().session.index;
        reached.add(index);
        gestures++;
        stalls = index == previous ? stalls + 1 : 0;
        previous = index;
        expect(stalls, lessThan(20));
        expect(gestures, lessThan(2000));
        sample('long-scroll');
        if (index > 0 &&
            index % 100 == 0 &&
            !samples.any((v) => v['phase'] == 'long-page-$index')) {
          await checkpoint('long-page-$index', sample('long-page-$index'));
        }
      }
      scrollClock.stop();
      expect(reached.length, 500);
      expect(reader().session.range!.id, rangeId);
      expect(await reader().session.flush(), isTrue);
      await checkpoint('long-end', sample('long-end'));
      final page = reader().session.currentPage!.id;
      await tap(find.byTooltip('阅读设置'));
      await tap(find.widgetWithText(ChoiceChip, '横向翻页'));
      await tap(find.byKey(const Key('reader-settings-done')));
      await imageReady();
      expect(reader().session.currentPage!.id, page);
      await checkpoint('long-horizontal-end', sample('long-horizontal-end'));
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
    },
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
