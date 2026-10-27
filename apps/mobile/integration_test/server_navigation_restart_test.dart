import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/library/tag_catalog_page.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/playback_defaults.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const resume = bool.fromEnvironment('NAV_RESTART_RESUME');
  const coldSource = String.fromEnvironment(
    'NAV_COLD_SOURCE',
    defaultValue: 'library',
  );
  testWidgets(
    'all content sources return independently and survive a real process restart',
    (t) async {
      final directory = await getApplicationSupportDirectory();
      final book = File('${directory.path}/navigation-restart-owned.json');
      final appearance = File(
        '${directory.path}/navigation-restart-appearance.json',
      );
      final credentials = SecureCredentialStore(
        key: 'video_viewer.navigation_restart.owned',
      );
      if (!resume) {
        await credentials.clear();
        if (book.existsSync()) await book.delete();
        if (appearance.existsSync()) await appearance.delete();
      }
      final preferences = await UiPreferences.load(file: appearance);
      final repo = ServerLibraryRepository(credentials, port: 8768);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      if (!resume) {
        await preferences.setPreloadAdjacent(false);
        await preferences.setVideoOrder(PlayOrder.sequential);
        await repo.connect(
          'http://10.0.2.2',
          8768,
          'prototype-fidelity-owned-only',
        );
        final defaults = repo.createPlaybackDefaults();
        try {
          final current = await defaults.read();
          await defaults.submit(
            WritePlaybackDefaults(
              'navigation-owned-sequential-$coldSource',
              PlaybackDefaults(PlayOrder.sequential, current.revision),
            ),
          );
        } finally {
          defaults.dispose();
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
            fail('Navigation restart timeout: $why');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder f) async {
        await until(() => f.evaluate().length == 1, 'unique $f');
        if (f.hitTestable().evaluate().isEmpty) await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 100));
        await until(() => f.hitTestable().evaluate().length == 1, 'hit $f');
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 200));
      }

      VideoCatalogPageState video() => t.state(find.byType(VideoCatalogPage));
      PackCatalogPageState packs() => t.state(find.byType(PackCatalogPage));
      Future<void> videoReady(int total) => until(
        () =>
            find.byType(VideoCatalogPage).evaluate().length == 1 &&
            video().initialized &&
            !video().data.loading &&
            !video().busy &&
            !video().viewing &&
            video().pendingReturn == null &&
            video().data.total == total,
        'video list $total',
      );
      Future<void> packReady(int total) => until(
        () =>
            find.byType(PackCatalogPage).evaluate().length == 1 &&
            packs().initialized &&
            !packs().data.loading &&
            !packs().busy &&
            packs().pendingReturn == null &&
            packs().data.total == total,
        'pack list $total',
      );
      Future<void> nav(String value) => tap(find.byKey(Key('nav-$value')));
      Future<void> kind(bool pack) =>
          tap(find.byKey(Key(pack ? 'kind-pack' : 'kind-video')));
      Future<void> hideKeyboard() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await until(() => t.view.viewInsets.bottom == 0, 'keyboard hidden');
      }

      Future<void> search(String value, {bool pack = false}) async {
        final field = find.byKey(Key(pack ? 'pack-search' : 'video-search'));
        await tap(field);
        await t.enterText(field, value);
        await hideKeyboard();
      }

      Future<void> hostBack() async {
        await control('/checkpoint/nav-device-back', post: true);
        await until(
          () async => (await control('/state'))['ack'] == true,
          'real Android back acknowledged',
        );
      }

      Future<void> capture(
        String name, {
        Map<String, dynamic> extra = const {},
      }) async {
        await t.pump(const Duration(milliseconds: 200));
        final media = MediaQueryData.fromView(t.view);
        final v = find.byType(VideoCatalogPage).evaluate().length == 1
            ? video()
            : null;
        final p = find.byType(PackCatalogPage).evaluate().length == 1
            ? packs()
            : null;
        final r = find.byType(PackReaderPage).evaluate().length == 1
            ? t.state<PackReaderPageState>(find.byType(PackReaderPage))
            : null;
        debugPrint(
          'FIDELITY_METRICS:${jsonEncode({
            'state': name,
            'cold_source': coldSource,
            'physical': [media.size.width * media.devicePixelRatio, media.size.height * media.devicePixelRatio],
            'dpr': media.devicePixelRatio,
            'text_scale': media.textScaler.scale(14) / 14,
            'dark': preferences.dark,
            'preload': preferences.preloadAdjacent,
            'video': v == null ? null : {'entry': v.entry.entry.toJson(), 'total': v.data.total, 'offset': v.data.offset, 'scroll': v.scroll.offset, 'selected': v.selected.toList(), 'selecting': v.selecting},
            'pack': p == null ? null : {'query': p.entry.query.toJson(), 'total': p.data.total, 'offset': p.data.offset, 'scroll': p.scroll.offset, 'selected': p.selected.toList(), 'selecting': p.selecting},
            'reading': r == null ? null : {'id': r.session.range?.id, 'pack': r.session.range?.pack?.id, 'page': r.session.currentPage?.id, 'opened': r.session.opened},
            'round': repo.playbackIdentity,
            'current': repo.current?.id,
            ...extra,
          })}',
        );
        await control('/checkpoint/$name', post: true);
        await until(
          () async => (await control('/state'))['ack'] == true,
          'screenshot $name',
        );
      }

      Future<List<String>> videoIds() async {
        final e = video().entry;
        final page = await repo.api.json(
          'GET',
          '/api/v1/videos',
          query: {
            'source': e.source.name,
            'search': e.search,
            'sort': e.sort.name,
            if (e.sort == VideoSort.name) 'name_locale': 'zh-CN',
            'tag_ids': e.query.tags.join(','),
            if (e.query.orientation.isNotEmpty)
              'orientation': e.query.orientation,
            if (e.query.duration.isNotEmpty) 'duration': e.query.duration,
            if (e.query.type.isNotEmpty) 'file_type': e.query.type,
            'limit': '200',
          },
        );
        return (page['items'] as List).map((v) => v['id'] as String).toList();
      }

      Future<List<String>> packIds() async {
        final q = packs().entry.query;
        final page = await repo.api.json(
          'GET',
          '/api/v1/packs',
          query: {
            'source': q.source.name,
            'search': q.search,
            'sort': q.sort == PackSort.name ? 'title' : q.sort.name,
            'tag_ids': q.tags.join(','),
            'read_state': q.readState.name,
            'limit': '200',
          },
        );
        return (page['items'] as List).map((v) => v['id'] as String).toList();
      }

      Future<void> reveal(Finder target, bool pack) async {
        final body = find.descendant(
          of: find.byKey(Key(pack ? 'pack-grid' : 'video-grid')),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await t.scrollUntilVisible(
          target,
          260,
          scrollable: body.first,
          maxScrolls: 100,
        );
        await t.pump(const Duration(milliseconds: 200));
      }

      final visits = <Map<String, dynamic>>[];
      Future<void> openVideo(
        String label, {
        bool panels = false,
        bool systemBack = false,
        int? index,
      }) async {
        final origin = video();
        final expected = await videoIds();
        final at = index ?? (origin.recent ? 0 : 25);
        final id = expected[at];
        final tile = find.byKey(
          Key(origin.recent ? 'recent-video-$id' : 'tile-$id'),
        );
        await reveal(tile, false);
        final top = t.getRect(tile).top,
            scroll = origin.scroll.offset,
            entry = origin.entry.queryKey;
        if (at >= 24) expect(origin.data.items.any((v) => v.id == id), isTrue);
        await tap(tile);
        await until(() {
          if (find.byType(MovieStage).evaluate().length != 1) return false;
          final players = t
              .widget<MovieStage>(find.byType(MovieStage))
              .session!
              .debugPlayers;
          return players.length == 1 &&
              players.single.value.isInitialized &&
              players.single.value.isPlaying &&
              !players.single.value.size.isEmpty;
        }, 'real native video $id');
        final controller = t
            .widget<MovieStage>(find.byType(MovieStage))
            .session!
            .debugPlayers
            .single;
        await tap(
          find
              .descendant(
                of: find.byKey(const Key('playback-controls')),
                matching: find.byType(TextButton),
              )
              .first,
        );
        await until(() => !controller.value.isPlaying, 'user paused');
        final round = await repo.api.json(
          'GET',
          '/api/v1/playback',
          query: {'create': 'false'},
        );
        expect(round['source'], origin.entry.source.name);
        expect(repo.current!.id, id);
        final queue = await repo.api.json(
          'GET',
          '/api/v1/rounds/${round['id']}/entries',
          query: {'limit': '48'},
        );
        expect(
          (queue['items'] as List).map((r) => r['video']['id']).toList(),
          expected,
        );
        expect(repo.playbackPosition, at);
        final record = {
          'kind': 'video',
          'source': origin.entry.source.name,
          'id': id,
          'range': round['id'],
          'members': expected,
          'index': at,
          'scroll': scroll,
          'top': top,
          'query_key': entry,
        };
        visits.add(record);
        await capture('$label-preview', extra: record);
        if (panels) {
          await tap(find.byKey(const Key('preview-scope')));
          await until(
            () => find.byKey(const Key('preview-queue')).evaluate().isNotEmpty,
            'queue panel',
          );
          await capture('$label-panel');
          await hostBack();
          await until(
            () => find.byKey(const Key('preview-queue')).evaluate().isEmpty,
            'back closes only queue',
          );
          expect(find.byType(MovieStage), findsOneWidget);
          expect(repo.playbackIdentity, round['id']);
          await capture('$label-panel-return');
        }
        if (systemBack) {
          await hostBack();
        } else {
          await tap(find.byKey(const Key('preview-back')));
        }
        await videoReady(expected.length);
        expect(video().entry.queryKey, entry);
        await until(
          () => tile.hitTestable().evaluate().length == 1,
          'restored tile',
        );
        expect(t.getRect(tile).top, closeTo(top, 2));
        expect(video().scroll.offset, closeTo(scroll, 2));
        await capture('$label-return', extra: record);
      }

      Future<void> openPack(
        String label, {
        bool panels = false,
        bool systemBack = false,
        int? index,
      }) async {
        final origin = packs();
        final expected = await packIds();
        final at = index ?? (origin.recent ? 0 : 25);
        final id = expected[at];
        final tile = find.byKey(
          Key(origin.recent ? 'recent-pack-$id' : 'pack-tile-$id'),
        );
        await reveal(tile, true);
        final top = t.getRect(tile).top,
            scroll = origin.scroll.offset,
            query = origin.entry.queryKey;
        await tap(tile);
        await until(() {
          if (find.byType(PackReaderPage).evaluate().length != 1) return false;
          final s = t
              .state<PackReaderPageState>(find.byType(PackReaderPage))
              .session;
          return s.range?.pack?.id == id &&
              s.opened &&
              find
                  .descendant(
                    of: find.byType(PackReaderPage),
                    matching: find.byType(RawImage),
                  )
                  .evaluate()
                  .any((e) => (e.widget as RawImage).image != null);
        }, 'actual decoded and opened pack $id');
        final page = t.state<PackReaderPageState>(find.byType(PackReaderPage));
        final range = page.session.range!;
        expect(range.source, origin.entry.source);
        expect(range.cursor, at);
        final queue = await repo.api.json(
          'GET',
          '/api/v1/pack-sessions/${range.id}/entries',
          query: {'limit': '200'},
        );
        expect(
          (queue['items'] as List).map((r) => r['pack']['id']).toList(),
          expected,
        );
        final record = {
          'kind': 'pack',
          'source': origin.entry.source.name,
          'id': id,
          'range': range.id,
          'members': expected,
          'index': at,
          'scroll': scroll,
          'top': top,
          'query_key': query,
        };
        visits.add(record);
        await capture('$label-reader', extra: record);
        if (panels) {
          await tap(find.byTooltip('图包更多'));
          await tap(find.text('页码总览'));
          await until(
            () => find
                .byKey(const Key('reader-overview-sheet'))
                .evaluate()
                .isNotEmpty,
            'overview panel',
          );
          await capture('$label-panel');
          await hostBack();
          await until(
            () => find
                .byKey(const Key('reader-overview-sheet'))
                .evaluate()
                .isEmpty,
            'back closes only overview',
          );
          expect(find.byType(PackReaderPage), findsOneWidget);
          expect(page.session.range!.id, range.id);
          await capture('$label-panel-return');
        }
        if (systemBack) {
          await hostBack();
        } else {
          await tap(find.byTooltip('返回来源'));
        }
        await packReady(expected.length);
        expect(packs().entry.queryKey, query);
        await until(
          () => tile.hitTestable().evaluate().length == 1,
          'restored pack tile',
        );
        expect(t.getRect(tile).top, closeTo(top, 2));
        expect(packs().scroll.offset, closeTo(scroll, 2));
        await capture('$label-return', extra: record);
      }

      if (resume) {
        final original = jsonDecode(await book.readAsString()) as Map;
        expect(original['cold_source'], coldSource);
        final expectedTotal = coldSource == 'library' ? 1 : 27;
        await videoReady(expectedTotal);
        debugPrint('NAVIGATION_NEW_PROCESS');
        expect(find.byType(MovieStage), findsNothing);
        expect(find.byType(PackReaderPage), findsNothing);
        expect(find.byKey(const Key('nav-browse')), findsNothing);
        for (final value in ['library', 'tags', 'recent', 'settings']) {
          expect(find.byKey(Key('nav-$value')), findsOneWidget);
        }
        expect(preferences.dark, isTrue);
        expect(preferences.preloadAdjacent, isFalse);
        expect(preferences.videoOrder, PlayOrder.sequential);
        expect(repo.savedPreviewEntry!.toJson(), original['saved_entry']);
        expect(
          (await repo.api.json(
            'GET',
            '/api/v1/playback',
            query: {'create': 'false'},
          )),
          original['playback'],
        );
        expect(
          await repo.api.json('GET', '/api/v1/recent'),
          original['recent'],
        );
        expect(video().entry.source, BrowseSource.library);
        expect(video().entry.search, coldSource == 'library' ? '导航视频 01' : '');
        if (coldSource == 'library') {
          expect(video().entry.query.tags, {(original['video_tag'] as String)});
        } else {
          expect(video().entry.query.count, 0);
        }
        await capture('nav-cold-library');
        await nav('tags');
        await until(
          () =>
              find.byType(TagCatalogPage).evaluate().length == 1 &&
              !t
                  .state<TagCatalogPageState>(find.byType(TagCatalogPage))
                  .loading,
          'cold tag directory',
        );
        final selected = t
            .state<TagCatalogPageState>(find.byType(TagCatalogPage))
            .selected;
        expect(
          selected,
          coldSource == 'tags' ? {(original['video_tag'] as String)} : isEmpty,
        );
        await capture('nav-cold-tags');
        await nav('recent');
        await videoReady((original['recent_video_ids'] as List).length);
        expect(video().entry.source, BrowseSource.recent);
        expect(video().entry.search, isEmpty);
        expect(video().entry.query.count, 0);
        expect(
          (await videoIds()).toSet(),
          (original['recent_video_ids'] as List).toSet(),
        );
        await capture('nav-cold-recent-video');
        await kind(true);
        await packReady((original['recent_pack_ids'] as List).length);
        expect(packs().entry.query.count, 0);
        expect(packs().entry.query.search, isEmpty);
        expect(
          (await packIds()).toSet(),
          (original['recent_pack_ids'] as List).toSet(),
        );
        await capture('nav-cold-recent-pack');
        await nav('settings');
        await hostBack();
        await videoReady(expectedTotal);
        expect(
          await repo.api.json('GET', '/api/v1/recent'),
          original['recent'],
        );
        await capture('nav-cold-final-library');
        debugPrint(
          'NAVIGATION_RESTART_VERIFIED:${jsonEncode({'cold_source': coldSource, 'original': original, 'new_round': repo.playbackIdentity, 'auto_played': false})}',
        );
        debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
        await credentials.clear();
        await book.delete();
        await appearance.delete();
        return;
      }

      await videoReady(27);
      await until(
        () => repo.libraryPreparation.value.ready,
        'initial preparation',
      );
      final videoTags =
          (await repo.api.json('GET', '/api/v1/tags'))['items'] as List;
      final packTags =
          (await repo.api.json('GET', '/api/v1/pack-tags'))['items'] as List;
      final videoTag =
          videoTags.singleWhere((r) => r['name'] == '户外')['id'] as String;
      final packTag =
          packTags.singleWhere((r) => r['name'] == '户外')['id'] as String;
      expect(videoTag, isNot(packTag));
      await capture('nav-start');
      await search('导航视频');
      await videoReady(27);
      await tap(find.byTooltip('筛选视频'));
      await tap(find.widgetWithText(FilterChip, '户外'));
      await tap(find.text('应用筛选'));
      await videoReady(27);
      await tap(find.byTooltip('视频排序'));
      await t.pumpAndSettle();
      await tap(find.text('最近加入'));
      await until(
        () => video().entry.sort == VideoSort.newest,
        'newest menu selection applied',
      );
      await videoReady(27);
      final libraryVideo = video();
      final selectedVideo = libraryVideo.data.items.first.id;
      await tap(find.byTooltip('更多'));
      await tap(find.text('多选内容'));
      await tap(find.byKey(Key('tile-$selectedVideo')));
      expect(libraryVideo.selected, {selectedVideo});
      await capture('nav-video-draft');
      await kind(true);
      await packReady(27);
      expect(packs().selecting, isFalse);
      expect(packs().selected, isEmpty);
      await search('导航图包', pack: true);
      await packReady(27);
      await tap(find.byTooltip('筛选图包'));
      await tap(
        find.descendant(of: find.byType(SheetFrame), matching: find.text('标签')),
      );
      await tap(find.widgetWithText(FilterChip, '户外'));
      await tap(find.byKey(const Key('tag-assignment-save')));
      await tap(find.text('应用筛选'));
      await packReady(27);
      final libraryPack = packs();
      final selectedPack = libraryPack.data.items.first.id;
      await tap(find.byTooltip('更多'));
      await tap(find.text('多选内容'));
      await tap(find.byKey(Key('pack-tile-$selectedPack')));
      expect(libraryPack.selected, {selectedPack});
      await capture('nav-pack-draft');
      await kind(false);
      await videoReady(27);
      expect(video().search.text, '导航视频');
      expect(video().entry.query.tags, {videoTag});
      expect(video().entry.sort, VideoSort.newest);
      expect(video().selected, {selectedVideo});
      await tap(find.byTooltip('更多'));
      await tap(find.text('多选内容'));
      await kind(true);
      await packReady(27);
      expect(packs().entry.query.tags, {packTag});
      expect(packs().selected, {selectedPack});
      await tap(find.byTooltip('更多'));
      await tap(find.text('多选内容'));
      await kind(false);
      await videoReady(27);
      await openVideo('nav-library-video', panels: true, systemBack: true);
      await kind(true);
      await packReady(27);
      await openPack('nav-library-pack', panels: true, systemBack: true);
      await nav('tags');
      await until(
        () =>
            find.byType(TagCatalogPage).evaluate().length == 1 &&
            !t.state<TagCatalogPageState>(find.byType(TagCatalogPage)).loading,
        'tag directory',
      );
      await tap(find.byKey(Key('video-tag-$videoTag')));
      await tap(find.byKey(const Key('tag-view-results')));
      await videoReady(27);
      expect(video().entry.search, isEmpty);
      expect(video().entry.sort, VideoSort.name);
      await openVideo('nav-tag-video');
      await tap(find.byTooltip('返回标签选择'));
      await kind(true);
      await until(
        () =>
            find.byType(TagCatalogPage).evaluate().length == 1 &&
            !t.state<TagCatalogPageState>(find.byType(TagCatalogPage)).loading,
        'pack tag directory',
      );
      await tap(find.byKey(Key('pack-tag-$packTag')));
      await tap(find.byKey(const Key('tag-view-results')));
      await packReady(27);
      expect(packs().entry.query.search, isEmpty);
      await openPack('nav-tag-pack');
      await nav('recent');
      final recentVideos =
          ((await repo.api.json(
                    'GET',
                    '/api/v1/videos',
                    query: {
                      'source': 'recent',
                      'sort': 'recent',
                      'limit': '200',
                    },
                  ))['items']
                  as List)
              .map((v) => v['id'] as String)
              .toList();
      final recentPacks =
          ((await repo.api.json(
                    'GET',
                    '/api/v1/packs',
                    query: {
                      'source': 'recent',
                      'sort': 'recent',
                      'limit': '200',
                    },
                  ))['items']
                  as List)
              .map((v) => v['id'] as String)
              .toList();
      await videoReady(recentVideos.length);
      expect(video().entry.query.count, 0);
      expect(video().entry.search, isEmpty);
      await openVideo('nav-recent-video', systemBack: true);
      await kind(true);
      await packReady(recentPacks.length);
      expect(packs().entry.query.count, 0);
      expect(packs().entry.query.search, isEmpty);
      await openPack('nav-recent-pack', systemBack: true);
      await nav('library');
      await packReady(27);
      expect(packs().search.text, '导航图包');
      expect(packs().entry.query.tags, {packTag});
      await kind(false);
      await videoReady(27);
      expect(video().search.text, '导航视频');
      expect(video().entry.query.tags, {videoTag});
      expect(video().entry.sort, VideoSort.newest);
      await capture('nav-library-isolation', extra: {'visits': visits});

      if (coldSource == 'library') {
        await search('导航视频 01');
        await videoReady(1);
        await tap(find.byKey(Key('tile-${(await videoIds()).single}')));
      } else if (coldSource == 'tags') {
        await nav('tags');
        await kind(false);
        await until(
          () =>
              find.byType(TagCatalogPage).evaluate().length == 1 &&
              !t
                  .state<TagCatalogPageState>(find.byType(TagCatalogPage))
                  .loading,
          'last tag directory',
        );
        await tap(find.byKey(const Key('tag-preview-results')));
      } else {
        await nav('recent');
        await kind(false);
        await videoReady(recentVideos.length);
        await tap(find.byKey(Key('recent-video-${(await videoIds()).first}')));
      }
      await until(
        () =>
            find.byType(MovieStage).evaluate().length == 1 &&
            repo.savedPreviewEntry?.source.name == coldSource,
        'final saved source',
      );
      await until(() {
        final players = t
            .widget<MovieStage>(find.byType(MovieStage))
            .session!
            .debugPlayers;
        return players.length == 1 &&
            players.single.value.isInitialized &&
            players.single.value.isPlaying;
      }, 'last saved source actually decoded');
      await until(() async {
        final rows =
            (await repo.api.json(
                  'GET',
                  '/api/v1/videos',
                  query: {'source': 'recent', 'sort': 'recent', 'limit': '200'},
                ))['items']
                as List;
        return rows.any((r) => r['id'] == repo.current!.id);
      }, 'last source actual open recorded');
      await tap(find.byKey(const Key('preview-back')));
      await until(
        () => find.byType(MovieStage).evaluate().isEmpty,
        'final viewing closed',
      );
      await nav('settings');
      await tap(find.byKey(const Key('dark-mode-setting')));
      await until(() => preferences.dark, 'real setting persisted');
      final savedCredentials = await credentials.read();
      expect(savedCredentials, isNotNull);
      expect(savedCredentials!.endpoint.port, 8768);
      final original = {
        'cold_source': coldSource,
        'video_tag': videoTag,
        'pack_tag': packTag,
        'saved_entry': repo.savedPreviewEntry!.toJson(),
        'playback': await repo.api.json(
          'GET',
          '/api/v1/playback',
          query: {'create': 'false'},
        ),
        'recent': await repo.api.json('GET', '/api/v1/recent'),
        'recent_video_ids':
            ((await repo.api.json(
                      'GET',
                      '/api/v1/videos',
                      query: {
                        'source': 'recent',
                        'sort': 'recent',
                        'limit': '200',
                      },
                    ))['items']
                    as List)
                .map((v) => v['id'])
                .toList(),
        'recent_pack_ids':
            ((await repo.api.json(
                      'GET',
                      '/api/v1/packs',
                      query: {
                        'source': 'recent',
                        'sort': 'recent',
                        'limit': '200',
                      },
                    ))['items']
                    as List)
                .map((v) => v['id'])
                .toList(),
        'credential_available': true,
        'preferences': jsonDecode(await appearance.readAsString()),
        'visits': visits,
      };
      await book.writeAsString(jsonEncode(original), flush: true);
      await capture('nav-stop-ready');
      debugPrint('NAVIGATION_STOP_READY:${jsonEncode(original)}');
      await Completer<void>().future;
    },
  );
}
