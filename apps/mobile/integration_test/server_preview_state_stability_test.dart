import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/media_tag_editor.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('preview keeps fixed membership across tag writes and new media', (
    t,
  ) async {
    final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
    final prefs = UiPreferences();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      prefs.dispose();
    });
    await repo.connect(
      'http://10.0.2.2',
      8768,
      'prototype-fidelity-owned-only',
    );
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: prefs,
        initializeRepository: false,
      ),
    );
    Future<void> until(FutureOr<bool> Function() done, String reason) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!await done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Preview stability timeout: $reason');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().length == 1, 'unique $target');
      if (target.hitTestable().evaluate().isEmpty) {
        await t.ensureVisible(target);
      }
      await until(
        () => target.hitTestable().evaluate().length == 1,
        'visible $target',
      );
      await t.tap(target);
      await t.pump(const Duration(milliseconds: 250));
    }

    // The source route remains mounted but is offstage during preview.
    VideoCatalogPageState? retainedCatalog;
    VideoCatalogPageState catalog() {
      if (retainedCatalog?.mounted != true) {
        retainedCatalog = t.state(find.byType(VideoCatalogPage));
      }
      return retainedCatalog!;
    }

    VideoPlayerController player() =>
        t.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;
    Future<void> decoded(String id) => until(() {
      if (find.byType(VideoPlayer).evaluate().length != 1) return false;
      final p = player();
      return p.dataSource.endsWith('/videos/$id/stream') &&
          p.value.isInitialized &&
          p.value.isPlaying &&
          !p.value.size.isEmpty;
    }, 'visible initialized playing video $id');
    Future<Map<String, dynamic>> active() =>
        repo.api.json('GET', '/api/v1/playback', query: {'create': 'false'});
    Future<List<String>> entries(String id) async {
      final rows =
          (await repo.api.json(
                'GET',
                '/api/v1/rounds/$id/entries',
                query: {'limit': '48'},
              ))['items']
              as List;
      return rows.map((r) => r['video']['id'] as String).toList();
    }

    Future<void> fixed(
      String id,
      List<String> members,
      String current,
      int cursor,
      String tag,
    ) async {
      final round = await active();
      expect(round['id'], id);
      expect(round['membership'], 'fixed');
      expect(round['total'], members.length);
      expect(round['position'], cursor);
      expect(round['current']['id'], current);
      expect(round['scope']['tag_ids'], [tag]);
      expect(await entries(id), members);
      expect(repo.playbackIdentity, id);
      expect(repo.current!.id, current);
      expect(repo.playbackTotal, members.length);
    }

    Future<void> capture(String state) async {
      await t.pump(const Duration(milliseconds: 200));
      final root =
          find.byKey(const Key('video-preview-route')).evaluate().isEmpty
          ? find.byKey(const Key('app-shell'))
          : find.byKey(const Key('video-preview-route'));
      final media = MediaQueryData.fromView(View.of(t.element(root)));
      final keys = <String, List<double>>{};
      for (final key in [
        'video-grid',
        'preview-scope',
        'preview-position',
        'preview-queue-frame',
        'tag-assignment-save',
        'tag-assignment-error',
      ]) {
        final f = find.byKey(Key(key));
        if (f.evaluate().length == 1) {
          final r = t.getRect(f);
          keys[key] = [r.left, r.top, r.width, r.height];
        }
      }
      final players = find.byType(MovieStage).evaluate().isEmpty
          ? null
          : t.widget<MovieStage>(find.byType(MovieStage)).session!.debugPlayers;
      debugPrint(
        'FIDELITY_METRICS:${jsonEncode({
          'state': state,
          'physical': [media.size.width * media.devicePixelRatio, media.size.height * media.devicePixelRatio],
          'dpr': media.devicePixelRatio,
          'keys': keys,
          'round': repo.playbackIdentity,
          'current': repo.current?.id,
          'cursor': repo.playbackPosition,
          'total': repo.playbackTotal,
          'current_tags': repo.current?.tags.toList(),
          'entry_tags': catalog().entry.query.tags.toList(),
          'catalog_ids': catalog().data.items.map((v) => v.id).toList(),
          'catalog_total': catalog().data.total,
          'inventory': [repo.catalogCounts.value?.videos, repo.catalogCounts.value?.packs],
          'visible_video': find.byType(VideoPlayer).evaluate().length == 1 ? player().dataSource : null,
          'players': players?.map((p) => {'source': p.dataSource, 'initialized': p.value.isInitialized, 'playing': p.value.isPlaying, 'volume': p.value.volume}).toList(),
        })}',
      );
      await control('/checkpoint/$state', post: true);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while ((await control('/state'))['ack'] != true) {
        if (DateTime.now().isAfter(deadline)) fail('Missing screenshot $state');
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tags() async {
      if (find.text('视频标签').hitTestable().evaluate().isEmpty) {
        await tap(find.byKey(const Key('video-gesture-surface')).last);
      }
      await tap(find.text('视频标签'));
      await until(
        () =>
            find.byType(MediaTagEditor).evaluate().length == 1 &&
            find
                    .ancestor(
                      of: find.text('户外'),
                      matching: find.bySubtype<FilterChip>(),
                    )
                    .evaluate()
                    .length ==
                1,
        'real tag choices',
      );
    }

    FilterChip choice(String name) => t.widget<FilterChip>(
      find.ancestor(
        of: find.text(name),
        matching: find.bySubtype<FilterChip>(),
      ),
    );
    Future<void> backToLibrary() async {
      await tap(find.byKey(const Key('preview-back')));
      await until(
        () =>
            find.byKey(const Key('video-preview-route')).evaluate().isEmpty &&
            !catalog().viewing &&
            !catalog().busy &&
            !catalog().data.loading &&
            catalog().pendingReturn == null,
        'source query complete',
      );
    }

    Future<void> queue(List<String> ids, String state) async {
      await tap(find.byKey(const Key('preview-scope')));
      await until(
        () => ids.every(
          (id) => find.byKey(Key('queue-video-$id')).evaluate().length == 1,
        ),
        'fixed queue rows',
      );
      await capture(state);
      await tap(find.byTooltip('关闭面板'));
    }

    await until(
      () =>
          find.byType(VideoCatalogPage).evaluate().length == 1 &&
          !catalog().data.loading &&
          catalog().data.total == 2,
      'initial library',
    );
    final original = catalog().data.items.map((v) => v.id).toList();
    final outdoor = repo.snapshot.tags.singleWhere(
      (id) => repo.tagName(id) == '户外',
    );
    final liked = repo.snapshot.tags.singleWhere(
      (id) => repo.tagName(id) == '喜欢',
    );
    await capture('stability-library');
    await tap(find.byTooltip('筛选视频'));
    await tap(
      find.ancestor(
        of: find.text('户外'),
        matching: find.bySubtype<FilterChip>(),
      ),
    );
    await tap(find.text('应用筛选'));
    await until(
      () =>
          !catalog().data.loading &&
          catalog().entry.query.tags.contains(outdoor) &&
          catalog().data.total == 2,
      'tag-filtered library',
    );
    await capture('stability-filter');
    await tap(find.byKey(Key('tile-${original.first}')));
    await decoded(original.first);
    final firstRound = repo.playbackIdentity;
    final firstMembers = await entries(firstRound);
    final firstCursor = (await active())['position'] as int;
    expect(firstMembers.toSet(), original.toSet());
    await capture('stability-preview');
    await tags();
    expect(choice('户外').selected, isTrue);
    expect(choice('喜欢').selected, isTrue);
    await capture('stability-editor');
    await tap(
      find.ancestor(
        of: find.text('户外'),
        matching: find.bySubtype<FilterChip>(),
      ),
    );
    await tap(find.byKey(const Key('tag-assignment-save')));
    await until(
      () =>
          find.byType(MediaTagEditor).evaluate().isEmpty &&
          repo.current!.tags.length == 1 &&
          repo.current!.tags.contains(liked),
      'saved tags synchronized',
    );
    await decoded(original.first);
    await fixed(firstRound, firstMembers, original.first, firstCursor, outdoor);
    await capture('stability-saved');
    await tags();
    expect(choice('户外').selected, isFalse);
    expect(choice('喜欢').selected, isTrue);
    await capture('stability-readback');
    await tap(find.byTooltip('关闭面板'));
    await decoded(original.first);

    // External changes use the owned fixture and authenticated server API;
    // they do not invoke repository mutation helpers or forge UI success.
    final added = await control('/add-public-video', post: true);
    final newId = added['id'] as String;
    expect(original, isNot(contains(newId)));
    await repo.api.json(
      'PATCH',
      '/api/v1/video-tags',
      body: {
        'request_id': 'native-new-public-tag',
        'video_ids': [newId],
        'tag_ids': [outdoor],
        'mode': 'add',
      },
    );
    await fixed(firstRound, firstMembers, original.first, firstCursor, outdoor);
    final live = await repo.api.json(
      'GET',
      '/api/v1/videos',
      query: {'tag_ids': outdoor},
    );
    expect(live['total'], 2);
    expect((live['items'] as List).map((v) => v['id']).toSet(), {
      original.last,
      newId,
    });
    await decoded(original.first);
    await capture('stability-added');
    await queue(firstMembers, 'stability-frozen-queue');
    await decoded(original.first);
    await backToLibrary();
    await until(
      () =>
          catalog().data.total == 2 &&
          catalog().data.items.any((v) => v.id == newId),
      'new source results',
    );
    expect(catalog().entry.query.tags, {outdoor});
    await until(
      () => repo.catalogCounts.value?.videos == 3,
      'authoritative inventory refreshed on return',
    );
    await until(
      () =>
          find
              .byType(RawImage)
              .evaluate()
              .where((e) => (e.widget as RawImage).image != null)
              .length >=
          2,
      'returned source thumbnails decoded',
    );
    final refreshed = catalog().data.items.map((v) => v.id).toList();
    expect(refreshed.toSet(), {original.last, newId});
    await capture('stability-return');

    await tap(find.byKey(Key('tile-${original.last}')));
    await decoded(original.last);
    final secondRound = repo.playbackIdentity;
    expect(secondRound, isNot(firstRound));
    final secondMembers = await entries(secondRound);
    final secondCursor = (await active())['position'] as int;
    expect(secondMembers.toSet(), refreshed.toSet());
    await capture('stability-second-preview');
    await repo.api.json(
      'DELETE',
      '/api/v1/tags/$outdoor',
      body: {'request_id': 'native-delete-filter-tag'},
    );
    await fixed(
      secondRound,
      secondMembers,
      original.last,
      secondCursor,
      outdoor,
    );
    await decoded(original.last);
    await capture('stability-tag-deleted');
    await queue(secondMembers, 'stability-second-queue');
    await decoded(original.last);
    await backToLibrary();
    expect(catalog().entry.query.tags, {outdoor});
    expect(catalog().data.total, 0);
    expect(catalog().data.items, isEmpty);
    await capture('stability-empty');
    await tap(find.text('清除'));
    await until(
      () => !catalog().data.loading && catalog().data.total == 3,
      'explicitly cleared filter',
    );
    expect(catalog().entry.query.tags, isEmpty);
    final allIds = catalog().data.items.map((v) => v.id).toSet();
    expect(allIds, {...original, newId});
    await capture('stability-cleared');
    final recent = await repo.api.json('GET', '/api/v1/recent');
    expect(
      (recent['items'] as List).map((v) => v['id']).toSet(),
      original.toSet(),
    );
    debugPrint(
      'PREVIEW_STABILITY_VERIFIED:${jsonEncode({'original': original, 'outdoor_tag': outdoor, 'liked_tag': liked, 'first_round': firstRound, 'first_members': firstMembers, 'first_cursor': firstCursor, 'second_round': secondRound, 'second_members': secondMembers, 'second_cursor': secondCursor, 'new_video': newId, 'addition': added, 'refreshed': refreshed, 'final_ids': allIds.toList(), 'recent': recent})}',
    );
    debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
  });
}
