import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/features/packs/pack_reading_session.dart';
import 'package:shika/features/packs/reader_images.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';

Future<Map<String, dynamic>> control(
  String path, {
  Map<String, dynamic>? data,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  try {
    final request = await client.openUrl(
      data == null ? 'GET' : 'POST',
      Uri.parse('http://10.0.2.2:8769/__long_reader$path'),
    );
    request.headers.set('X-Fixture-Key', 'reader-long-pack-owned-control');
    if (data != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(data));
    }
    final response = await request.close();
    final value = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('Fixture ${response.statusCode}: $value');
    }
    return jsonDecode(value) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '500-page real scrolling, large decode, bounded windows and return',
    (t) async {
      final previousError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('LONG_READER_FLUTTER_ERROR:$details');
        previousError?.call(details);
      };
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8769);
      final preferences = UiPreferences(preloadAdjacent: false);
      final timings = <FrameTiming>[];
      var peakPending = 0, peakLive = 0, peakCacheBytes = 0;
      void frames(List<FrameTiming> values) {
        timings.addAll(values);
        final cache = PaintingBinding.instance.imageCache;
        peakPending = max(peakPending, cache.pendingImageCount);
        peakLive = max(peakLive, cache.liveImageCount);
        peakCacheBytes = max(peakCacheBytes, cache.currentSizeBytes);
      }

      SchedulerBinding.instance.addTimingsCallback(frames);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
        SchedulerBinding.instance.removeTimingsCallback(frames);
        FlutterError.onError = previousError;
      });
      await repo.connect(
        'http://10.0.2.2',
        8769,
        'reader-long-pack-owned-only',
      );
      await repo.saveRoot(
        MediaRoot('', '长包合成夹具', '/media/packs', kind: MediaKind.pack),
      );
      var resumedScanWaits = 0;
      for (var attempt = 0; ; attempt++) {
        try {
          await repo.refresh();
          break;
        } on LibraryFailure catch (error) {
          if (error.message != '扫描仍在服务端进行，可稍后刷新查询进度' || attempt >= 2) {
            rethrow;
          }
          resumedScanWaits++;
          debugPrint(
            'LONG_READER_PREPARATION: continue querying the original scan',
          );
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      final catalog = await repo.loadPacks(PackQuery());
      expect(catalog.total, 4);
      final long = catalog.items.singleWhere((p) => p.name == '04-long');
      final large = catalog.items.singleWhere((p) => p.name == '02-large');
      expect(long.pageCount, 500);
      expect(large.pageCount, 3);
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Long reader timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        expect(t.takeException(), isNull);
      }

      bool readerSettled() =>
          find.byType(PackReaderPage).evaluate().isEmpty ||
          (!reader().session.inputBlocked && !reader().session.unsaved);
      Future<void> tap(Finder target) async {
        await until(readerSettled, 'reader save acknowledged before tap');
        await until(() => target.evaluate().length == 1, 'target $target');
        await t.ensureVisible(target);
        await t.pump(const Duration(milliseconds: 250));
        await until(
          () => target.hitTestable().evaluate().length == 1 && readerSettled(),
          'hit $target',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 300));
      }

      List<RawImage> decodedCurrent() {
        final id = reader().session.currentPage?.id;
        if (id == null) return [];
        final page = find.byWidgetPredicate(
          (w) => w is ReaderImage && !w.thumbnail && w.page.id == id,
        );
        final canvas = t.getRect(find.byKey(const Key('reader-canvas')));
        return find
            .descendant(of: page, matching: find.byType(RawImage))
            .evaluate()
            .where((element) {
              final box = element.renderObject;
              return (element.widget as RawImage).image != null &&
                  box is RenderBox &&
                  box.hasSize &&
                  box.attached &&
                  (box.localToGlobal(Offset.zero) & box.size).overlaps(canvas);
            })
            .map((element) => element.widget as RawImage)
            .toList();
      }

      Future<void> frame() => until(
        () =>
            !reader().session.loadingPages &&
            !reader().session.inputBlocked &&
            decodedCurrent().isNotEmpty,
        'current image frame',
      );
      Future<void> step(String tooltip, int expected) async {
        await until(readerSettled, 'page navigation save acknowledged');
        final button = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == tooltip,
        );
        await t.ensureVisible(button);
        await until(
          () =>
              readerSettled() && t.widget<IconButton>(button).onPressed != null,
          'enabled $tooltip',
        );
        await t.tap(button);
        await until(
          () => reader().session.index == expected,
          'page $expected after $tooltip',
        );
        await t.pump(const Duration(milliseconds: 200));
        await frame();
      }

      final samples = <Map<String, dynamic>>[];
      var peakProviders = 0,
          peakEstimated = 0,
          peakMetadata = 0,
          peakDecodedPixels = 0;
      void sample(String phase) {
        final s = reader().session, images = reader().images;
        final cache = PaintingBinding.instance.imageCache;
        final decoded = decodedCurrent()
            .map((w) => [w.image!.width, w.image!.height])
            .toList();
        for (final size in decoded) {
          final pixels = size[0] * size[1];
          peakDecodedPixels = max(peakDecodedPixels, pixels);
          expect(pixels, lessThanOrEqualTo(2105000));
        }
        peakProviders = max(peakProviders, images.length);
        peakEstimated = max(peakEstimated, images.estimatedBytes);
        peakMetadata = max(peakMetadata, s.pages.length);
        peakPending = max(peakPending, cache.pendingImageCount);
        peakLive = max(peakLive, cache.liveImageCount);
        peakCacheBytes = max(peakCacheBytes, cache.currentSizeBytes);
        expect(images.length, lessThanOrEqualTo(ReaderImages.maximumEntries));
        expect(
          images.estimatedBytes,
          lessThanOrEqualTo(ReaderImages.maximumBytes),
        );
        expect(
          s.pages.length,
          lessThanOrEqualTo(PackReadingSession.maximumPages),
        );
        expect(s.error, isEmpty);
        expect(s.pageError, isEmpty);
        samples.add({
          'phase': phase,
          'pack_id': s.range!.pack!.id,
          'page_id': s.currentPage?.id,
          'index': s.index,
          'ratio': s.offsetRatio,
          'window': [s.windowStart, s.windowEnd],
          'source_dimensions': [s.currentPage!.width, s.currentPage!.height],
          'metadata': s.pages.length,
          'providers': images.length,
          'estimated_bytes': images.estimatedBytes,
          'cache_bytes': cache.currentSizeBytes,
          'pending': cache.pendingImageCount,
          'live': cache.liveImageCount,
          'decoded': decoded,
        });
      }

      Future<void> capture(String name) async {
        await frame();
        await t.pump(const Duration(milliseconds: 300));
        sample(name);
        await control('/checkpoint/$name', data: samples.last);
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Host did not capture $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> mode(ReaderMode value) async {
        final id = reader().session.currentPage!.id;
        await tap(find.byTooltip('阅读设置'));
        await tap(
          find.widgetWithText(
            ChoiceChip,
            value == ReaderMode.vertical ? '纵向拼接' : '横向翻页',
          ),
        );
        await until(
          () =>
              reader().session.preferences.mode == value &&
              !reader().session.inputBlocked,
          'saved mode',
        );
        await tap(find.byKey(const Key('reader-settings-done')));
        await frame();
        expect(reader().session.currentPage!.id, id);
      }

      Future<Map<String, dynamic>> saved(String id) async =>
          Map<String, dynamic>.from(
            (await repo.api.json('GET', '/api/v1/packs/$id'))['progress']
                as Map,
          );
      await until(() => find.text('图包').evaluate().isNotEmpty, 'pack type');
      await tap(find.text('图包'));
      final open = Stopwatch()..start();
      await tap(find.byKey(Key('pack-tile-${long.id}')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            reader().session.opened,
        'long first frame',
      );
      await frame();
      final firstFrameMs = open.elapsedMilliseconds;
      expect(reader().session.range!.candidateCount, 4);
      final rangeId = reader().session.range!.id;
      await capture('long-horizontal');
      await mode(ReaderMode.vertical);
      await capture('long-vertical-start');
      final scroll = find.byKey(const Key('reader-vertical'));
      var previous = -1, stalled = 0, gestures = 0;
      final reached = <int>{0};
      final scrollClock = Stopwatch()..start();
      while (reader().session.index < 499) {
        await t.drag(scroll, const Offset(0, -420));
        await t.pump(const Duration(milliseconds: 100));
        await frame();
        final index = reader().session.index;
        reached.add(index);
        gestures++;
        stalled = index == previous ? stalled + 1 : 0;
        previous = index;
        expect(stalled, lessThan(15), reason: 'continuous scroll must advance');
        expect(gestures, lessThan(1000));
        sample('scroll');
        if (index >= 40 && reached.length % 40 == 0) {
          debugPrint(
            'LONG_READER_PROGRESS:index=$index window=${reader().session.windowStart}-${reader().session.windowEnd}',
          );
        }
        if (index > 0 &&
            index < 499 &&
            index % 100 == 0 &&
            !samples.any((s) => s['phase'] == 'long-page-${index + 1}')) {
          await capture('long-page-${index + 1}');
        }
      }
      await t.drag(scroll, const Offset(0, -420));
      await t.pump(const Duration(milliseconds: 200));
      await frame();
      scrollClock.stop();
      expect(reached.length, 500);
      expect(reader().session.range!.pack!.id, long.id);
      expect(reader().session.range!.id, rangeId);
      expect(await reader().session.flush(), isTrue);
      final endProgress = await saved(long.id);
      expect(endProgress['page_id'], reader().session.currentPage!.id);
      await capture('long-vertical-end');
      await mode(ReaderMode.horizontal);
      await capture('long-horizontal-end');
      await mode(ReaderMode.vertical);
      Future<void> choose(String title, String id) async {
        await tap(find.byTooltip('图包更多'));
        await tap(find.text('本次图包范围'));
        await until(
          () => find.widgetWithText(ListTile, title).evaluate().length == 1,
          'range member',
        );
        await tap(find.widgetWithText(ListTile, title));
        await until(
          () =>
              reader().session.range!.pack!.id == id &&
              !reader().session.inputBlocked,
          'range move',
        );
        await frame();
        expect(reader().session.range!.id, rangeId);
      }

      final largeFrames = <Map<String, dynamic>>[];
      for (var cycle = 0; cycle < 3; cycle++) {
        await choose(large.displayTitle, large.id);
        await mode(ReaderMode.horizontal);
        // Each large pack starts at its persisted page. Move through actual controls.
        for (var i = reader().session.index; i > 0; i--) {
          await step('上一张', i - 1);
        }
        for (var index = 0; index < 3; index++) {
          await frame();
          expect(reader().session.index, index);
          sample('large-$cycle-$index');
          largeFrames.add(samples.last);
          if (cycle == 0) await capture('large-page-${index + 1}');
          if (index < 2) await step('下一张', index + 1);
        }
        await mode(ReaderMode.vertical);
        await frame();
        sample('large-vertical-$cycle');
        expect(await reader().session.flush(), isTrue);
        await choose(long.displayTitle, long.id);
        expect(reader().session.index, 499);
        expect(reader().session.preferences.mode, ReaderMode.vertical);
        expect(reader().session.currentPage!.id, endProgress['page_id']);
        sample('return-$cycle');
      }
      await capture('long-return');
      expect(await reader().session.flush(), isTrue);
      final finalProgress = await saved(long.id);
      expect(finalProgress['page_id'], endProgress['page_id']);
      final pageId = reader().session.currentPage!.id;
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'return library',
      );
      await tap(find.byKey(Key('pack-tile-${long.id}')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            reader().session.opened,
        'reopen saved long pack',
      );
      await frame();
      expect(reader().session.currentPage!.id, pageId);
      expect(reader().session.preferences.mode, ReaderMode.vertical);
      await capture('long-reopened');
      double percentile(List<int> v, double p) {
        v.sort();
        return v.isEmpty ? 0 : v[((v.length - 1) * p).ceil()] / 1000;
      }

      final result = {
        'resumed_scan_waits': resumedScanWaits,
        'long_pack': long.id,
        'large_pack': large.id,
        'last_page_id': pageId,
        'range_id': rangeId,
        'first_frame_ms': firstFrameMs,
        'scroll_ms': scrollClock.elapsedMilliseconds,
        'gestures': gestures,
        'visited_indexes': reached.toList()..sort(),
        'samples': samples,
        'large_frames': largeFrames,
        'peaks': {
          'metadata': peakMetadata,
          'providers': peakProviders,
          'estimated_bytes': peakEstimated,
          'pending': peakPending,
          'live': peakLive,
          'cache_bytes': peakCacheBytes,
          'decoded_pixels': peakDecodedPixels,
        },
        'frame_count': timings.length,
        'frame_ms': {
          'build_p50': percentile(
            timings.map((v) => v.buildDuration.inMicroseconds).toList(),
            .5,
          ),
          'build_p95': percentile(
            timings.map((v) => v.buildDuration.inMicroseconds).toList(),
            .95,
          ),
          'raster_p50': percentile(
            timings.map((v) => v.rasterDuration.inMicroseconds).toList(),
            .5,
          ),
          'raster_p95': percentile(
            timings.map((v) => v.rasterDuration.inMicroseconds).toList(),
            .95,
          ),
        },
        'progress': finalProgress,
      };
      await control('/checkpoint/verified', data: result);
      debugPrint('LONG_READER_VERIFIED:${jsonEncode(result)}');
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
