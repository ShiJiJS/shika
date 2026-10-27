import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/features/packs/reader_images.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/playback_defaults.dart';
import 'package:video_viewer/library/repository.dart' show ReaderMode;
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/playback_session.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const resume = bool.fromEnvironment('CONTENT_RESTART_RESUME');
  const contentCase = String.fromEnvironment(
    'CONTENT_CASE',
    defaultValue: 'video',
  );
  testWidgets(
    'active $contentCase real process restart is read-only until explicit reopen',
    (t) async {
      await configureApplicationWindow();
      final directory = await getApplicationSupportDirectory();
      final book = File(
        '${directory.path}/content-restart-$contentCase-owned.json',
      );
      final appearance = File(
        '${directory.path}/content-restart-$contentCase-appearance.json',
      );
      final credentials = SecureCredentialStore(
        key: 'video_viewer.content_restart.$contentCase.owned',
      );
      if (!resume) {
        await credentials.clear();
        if (book.existsSync()) await book.delete();
        if (appearance.existsSync()) await appearance.delete();
      }
      final preferences = await UiPreferences.load(file: appearance);
      final repo = ServerLibraryRepository(credentials, port: 8768);
      PlaybackSession? playing;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      if (!resume) {
        await preferences.setPreloadAdjacent(false);
        await repo.connect(
          'http://10.0.2.2',
          8768,
          'prototype-fidelity-owned-only',
        );
        if (contentCase != 'reader') {
          final defaults = repo.createPlaybackDefaults();
          try {
            final value = await defaults.read();
            await defaults.submit(
              WritePlaybackDefaults(
                'content-owned-sequential-$contentCase',
                PlaybackDefaults(PlayOrder.sequential, value.revision),
              ),
            );
          } finally {
            defaults.dispose();
          }
        }
      }
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: resume,
        ),
      );
      Future<void> until(FutureOr<bool> Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!await done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Content restart timeout: $why');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().length == 1, 'unique $f');
        Map<String, dynamic> trace() {
          final stages = find.byKey(const Key('video-stage'));
          final controller = stages.evaluate().isEmpty
              ? null
              : t.widget<PageView>(stages).controller;
          return {
            'target': f.toString().split('\n').first,
            'hittable': f.hitTestable().evaluate().length,
            'video': repo.current?.id,
            'page': controller?.hasClients == true ? controller!.page : null,
          };
        }

        debugPrint('CONTENT_TAP_BEFORE:${jsonEncode(trace())}');
        if (f.hitTestable().evaluate().isEmpty) {
          // Revealing a child of the video pager scrolls the video itself.
          // Its controls must be explicitly shown, then tapped in place.
          expect(
            find.ancestor(
              of: f,
              matching: find.byKey(const Key('video-stage')),
            ),
            findsNothing,
            reason: 'Do not scroll a video page to reveal its controls',
          );
          await t.ensureVisible(f);
          await t.pump(const Duration(milliseconds: 150));
        }
        debugPrint('CONTENT_TAP_REVEALED:${jsonEncode(trace())}');
        await until(() => f.hitTestable().evaluate().length == 1, 'hit $f');
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 200));
        debugPrint('CONTENT_TAP_AFTER:${jsonEncode(trace())}');
      }

      VideoCatalogPageState video() => t.state(find.byType(VideoCatalogPage));
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      Future<void> libraryReady() => until(
        () =>
            find.byType(VideoCatalogPage).evaluate().length == 1 &&
            video().initialized &&
            !video().data.loading &&
            !video().busy &&
            !video().viewing &&
            video().data.total == 2 &&
            repo.libraryPreparation.value.ready,
        'cold video library',
      );
      Future<void> packReady() => until(
        () =>
            find.byType(PackCatalogPage).evaluate().length == 1 &&
            t
                .state<PackCatalogPageState>(find.byType(PackCatalogPage))
                .initialized &&
            !t
                .state<PackCatalogPageState>(find.byType(PackCatalogPage))
                .data
                .loading &&
            !t
                .state<PackCatalogPageState>(find.byType(PackCatalogPage))
                .continuationLoading,
        'pack library',
      );
      Future<void> playerReady() => until(() {
        final players = playing?.debugPlayers;
        return players != null &&
            players.length == 1 &&
            players.single.value.isInitialized &&
            players.single.value.isPlaying &&
            players.single.value.position.inMilliseconds > 100;
      }, 'native video playing');
      Future<Map<String, dynamic>?> playback() async {
        try {
          return await repo.api.json(
            'GET',
            '/api/v1/playback',
            query: {'create': 'false'},
          );
        } on ApiFailure catch (e) {
          if (e.status == 404) return null;
          rethrow;
        }
      }

      List<RawImage> decoded() {
        final id = reader().session.currentPage?.id;
        final page = find.byWidgetPredicate(
          (w) => w is ReaderImage && !w.thumbnail && w.page.id == id,
        );
        final canvas = t.getRect(find.byKey(const Key('reader-canvas')));
        return find
            .descendant(of: page, matching: find.byType(RawImage))
            .evaluate()
            .where((e) {
              final b = e.renderObject;
              return (e.widget as RawImage).image != null &&
                  b is RenderBox &&
                  b.hasSize &&
                  (b.localToGlobal(Offset.zero) & b.size).overlaps(canvas);
            })
            .map((e) => e.widget as RawImage)
            .toList();
      }

      Future<void> readerReady() => until(
        () =>
            find.byType(PackReaderPage).evaluate().length == 1 &&
            reader().session.opened &&
            !reader().session.loadingPages &&
            !reader().session.inputBlocked &&
            !reader().session.unsaved &&
            decoded().isNotEmpty,
        'actual saved reading frame',
      );
      List<double> pageGeometry() {
        final id = reader().session.currentPage!.id;
        final f = find.byWidgetPredicate(
          (w) => w is ReaderImage && !w.thumbnail && w.page.id == id,
        );
        final r = t.getRect(f),
            canvas = t.getRect(find.byKey(const Key('reader-canvas')));
        return [r.left - canvas.left, r.top - canvas.top, r.width, r.height];
      }

      Future<void> capture(String name) async {
        await t.pump(const Duration(milliseconds: 200));
        final media = MediaQueryData.fromView(t.view);
        final reading = find.byType(PackReaderPage).evaluate().isNotEmpty
            ? reader().session
            : null;
        debugPrint(
          'FIDELITY_METRICS:${jsonEncode({
            'state': name,
            'case': contentCase,
            'size': [media.size.width, media.size.height],
            'physical': [t.view.physicalSize.width, t.view.physicalSize.height],
            'dpr': media.devicePixelRatio,
            'fullscreen': find.byKey(const Key('fullscreen-exit')).evaluate().isNotEmpty,
            'movie_visible': find.byType(MovieStage).evaluate().length,
            'players': playing?.debugPlayers.map((p) => {'initialized': p.value.isInitialized, 'playing': p.value.isPlaying, 'position_ms': p.value.position.inMilliseconds, 'looping': p.value.isLooping, 'source': p.dataSource}).toList() ?? [],
            'range': repo.playbackIdentity,
            'current_video': repo.current?.id,
            'reading': reading == null ? null : {'range': reading.range!.id, 'page': reading.currentPage?.id, 'index': reading.index, 'ratio': reading.offsetRatio, 'mode': reading.preferences.mode.name, 'geometry': pageGeometry(), 'decoded': decoded().length},
            'preload': preferences.preloadAdjacent,
          })}',
        );
        await control('/checkpoint/$name', post: true);
        await until(
          () async => (await control('/state'))['ack'] == true,
          'screenshot $name',
        );
      }

      await libraryReady();
      if (resume) {
        final original = jsonDecode(await book.readAsString()) as Map;
        expect(original['case'], contentCase);
        debugPrint('CONTENT_NEW_PROCESS');
        expect(t.view.physicalSize.width, lessThan(t.view.physicalSize.height));
        expect(find.byType(MovieStage), findsNothing);
        expect(find.byType(PackReaderPage), findsNothing);
        expect(find.byKey(const Key('fullscreen-exit')), findsNothing);
        expect(preferences.preloadAdjacent, isFalse);
        expect(await playback(), original['playback']);
        expect(
          await repo.api.json('GET', '/api/v1/recent'),
          original['recent'],
        );
        if (contentCase == 'reader') {
          expect(
            await repo.api.json('GET', '/api/v1/packs/${original['pack_id']}'),
            original['pack_detail'],
          );
        }
        await capture('content-cold-library');
        await tap(find.byKey(const Key('nav-recent')));
        await until(
          () =>
              find.byType(VideoCatalogPage).evaluate().isNotEmpty &&
              !video().data.loading,
          'recent video',
        );
        if (contentCase == 'reader') {
          await tap(find.byKey(const Key('kind-pack')));
          await packReady();
        }
        expect(
          await repo.api.json('GET', '/api/v1/recent'),
          original['recent'],
        );
        await capture('content-cold-recent');
        await tap(find.byKey(const Key('nav-library')));
        if (contentCase == 'reader') {
          await libraryReady();
          await tap(find.byKey(const Key('kind-pack')));
          await packReady();
        } else {
          await libraryReady();
        }
        await capture('content-readonly-complete');
        await control('/checkpoint/content-readonly-boundary', post: true);
        debugPrint('CONTENT_READONLY_READY');
        await until(
          () async => (await control('/state'))['ack'] == true,
          'host seven-table readonly snapshot',
        );
        if (contentCase == 'reader') {
          await tap(find.byKey(Key('pack-tile-${original['pack_id']}')));
          await readerReady();
          expect(reader().session.index, original['index']);
          expect(reader().session.currentPage!.id, original['page']);
          expect(reader().session.preferences.mode.name, original['mode']);
          expect(
            reader().session.offsetRatio,
            closeTo((original['ratio'] as num).toDouble(), .01),
          );
          final geometry = pageGeometry();
          final old = (original['geometry'] as List).cast<num>();
          for (var i = 0; i < 4; i++) {
            expect(
              geometry[i],
              closeTo(old[i].toDouble(), 2),
              reason: 'same saved vertical page geometry $i',
            );
          }
          expect(reader().session.range!.id, isNot(original['reading_range']));
        } else {
          await tap(find.byKey(Key('tile-${original['video_id']}')));
          await until(
            () => find.byType(MovieStage).evaluate().isNotEmpty,
            'explicit video',
          );
          playing = t.widget<MovieStage>(find.byType(MovieStage)).session;
          await playerReady();
          expect(repo.current!.id, original['video_id']);
          expect(repo.playbackIdentity, isNot(original['range']));
        }
        await capture('content-reopened');
        if (contentCase == 'reader') {
          await tap(find.byTooltip('返回来源'));
          await packReady();
        } else {
          await tap(find.byKey(const Key('preview-back')));
          await libraryReady();
        }
        await capture('content-return');
        debugPrint(
          'CONTENT_RESTART_VERIFIED:${jsonEncode({'case': contentCase, 'original': original, 'auto_opened': false, 'explicit_reopened': true})}',
        );
        debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
        await credentials.clear();
        await book.delete();
        await appearance.delete();
        return;
      }
      await capture('content-start');
      String? videoId, packId;
      if (contentCase == 'reader') {
        await tap(find.byKey(const Key('kind-pack')));
        await packReady();
        final pack = t
            .state<PackCatalogPageState>(find.byType(PackCatalogPage))
            .data
            .items
            .singleWhere((p) => p.name.contains('034'));
        packId = pack.id;
        await tap(find.byKey(Key('pack-tile-$packId')));
        await readerReady();
        await tap(find.byTooltip('阅读设置'));
        await tap(find.widgetWithText(ChoiceChip, '纵向拼接'));
        await until(
          () =>
              reader().session.preferences.mode == ReaderMode.vertical &&
              !reader().session.inputBlocked,
          'vertical preference acknowledged',
        );
        await tap(find.byKey(const Key('reader-settings-done')));
        await readerReady();
        await t.drag(
          find.byKey(const Key('reader-vertical')),
          const Offset(0, -300),
        );
        await readerReady();
        for (var i = 0; i < 3 && reader().session.offsetRatio < .15; i++) {
          await t.drag(
            find.byKey(const Key('reader-vertical')),
            const Offset(0, -90),
          );
          await readerReady();
        }
        expect(reader().session.index, greaterThanOrEqualTo(3));
        expect(reader().session.offsetRatio, greaterThan(.04));
        expect(reader().session.offsetRatio, lessThan(.9));
      } else {
        final target = contentCase == 'fullscreen'
            ? video().data.items.firstWhere((v) => !v.portrait)
            : video().data.items.last;
        videoId = target.id;
        await tap(find.byKey(Key('tile-$videoId')));
        await until(
          () => find.byType(MovieStage).evaluate().isNotEmpty,
          'video route',
        );
        playing = t.widget<MovieStage>(find.byType(MovieStage)).session;
        await playerReady();
        void selectedVideo(String step) {
          expect(repo.current!.id, videoId, reason: step);
          expect(
            playing!.debugPlayers.single.dataSource,
            repo.current!.source.location,
            reason: 'Native player must belong to selected video: $step',
          );
          debugPrint(
            'CONTENT_VIDEO_IDENTITY:${jsonEncode({'step': step, 'video_id': videoId, 'current_video': repo.current!.id, 'source': playing!.debugPlayers.single.dataSource, 'looping': playing!.debugPlayers.single.value.isLooping})}',
          );
        }

        selectedVideo('initial-playing');
        if (contentCase == 'fullscreen') {
          await tap(find.widgetWithText(TextButton, '暂停'));
          await until(
            () => !playing!.debugPlayers.single.value.isPlaying,
            'paused before rotating short public clip',
          );
          selectedVideo('paused-before-rotation');
          await tap(find.text('横向全屏'));
          await until(
            () =>
                t.view.physicalSize.width > t.view.physicalSize.height &&
                find.byKey(const Key('fullscreen-exit')).evaluate().isNotEmpty,
            'actual landscape fullscreen',
          );
          expect(playing!.debugPlayers.single.value.isPlaying, isFalse);
          selectedVideo('fullscreen-paused');
        }
      }
      if (contentCase != 'reader') {
        await until(() async {
          final items =
              (await repo.api.json(
                    'GET',
                    '/api/v1/videos',
                    query: {
                      'source': 'recent',
                      'sort': 'recent',
                      'limit': '200',
                    },
                  ))['items']
                  as List;
          return items.any((row) => row['id'] == videoId);
        }, 'actual selected video opened acknowledgement');
      }
      final saved = await credentials.read();
      expect(saved, isNotNull);
      expect(saved!.endpoint.port, 8768);
      final original = <String, dynamic>{
        'case': contentCase,
        'credential_available': true,
        'playback': await playback(),
        'recent': await repo.api.json('GET', '/api/v1/recent'),
        'range': repo.playbackIdentity,
        'video_id': videoId,
        'pack_id': packId,
        'preload': preferences.preloadAdjacent,
      };
      if (contentCase == 'reader') {
        await readerReady();
        final s = reader().session;
        original.addAll({
          'index': s.index,
          'page': s.currentPage!.id,
          'ratio': s.offsetRatio,
          'mode': s.preferences.mode.name,
          'geometry': pageGeometry(),
          'reading_range': s.range!.id,
          'pack_detail': await repo.api.json('GET', '/api/v1/packs/$packId'),
        });
        expect(
          (original['pack_detail'] as Map)['progress']['page_id'],
          s.currentPage!.id,
        );
      }
      if (contentCase != 'reader') {
        expect(repo.current!.id, videoId);
        expect((original['playback'] as Map)['current']['id'], videoId);
      }
      await book.writeAsString(jsonEncode(original), flush: true);
      if (contentCase == 'fullscreen') {
        await tap(find.widgetWithText(TextButton, '播放'));
        await playerReady();
      }
      await capture('content-stop-ready');
      if (contentCase != 'reader') {
        await playerReady();
        expect(repo.current!.id, videoId);
      } else {
        await readerReady();
      }
      debugPrint('CONTENT_STOP_READY:${jsonEncode(original)}');
      await Completer<void>().future;
    },
  );
}
