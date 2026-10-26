import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/ui/media_history.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real recent history keeps distinct sources, fixed ranges and retry state', (
    t,
  ) async {
    final previousError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('RECENT_HISTORY_ERROR:$details');
      previousError?.call(details);
    };
    final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
    final preferences = UiPreferences(preloadAdjacent: false);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      preferences.dispose();
      FlutterError.onError = previousError;
    });
    await repo.connect(
      'http://10.0.2.2',
      8768,
      'prototype-fidelity-owned-only',
    );
    expect(repo.capabilities.videoNameOrder, isTrue);
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: preferences,
        initializeRepository: false,
      ),
    );
    Future<void> until(
      FutureOr<bool> Function() condition,
      String reason,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!await condition()) {
        if (DateTime.now().isAfter(deadline)) {
          if (find.byType(VideoCatalogPage).evaluate().length == 1) {
            final s = t.state<VideoCatalogPageState>(
              find.byType(VideoCatalogPage),
            );
            debugPrint(
              'VIDEO_NAME_ORDER_TIMEOUT_STATE:${jsonEncode({'search': s.search.text, 'entry': s.entry.search, 'loaded_entry': s.data.context.search, 'active': s.widget.active, 'viewing': s.viewing, 'busy': s.busy, 'loading': s.data.loading, 'total': s.data.total, 'error': s.data.error})}',
            );
          }
          fail('Video order timeout: $reason');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().length == 1, 'one target $target');
      if (target.hitTestable().evaluate().isEmpty) {
        await t.ensureVisible(target);
      }
      await until(
        () => target.hitTestable().evaluate().length == 1,
        'visible $target',
      );
      await t.tap(target);
      await t.pump(const Duration(milliseconds: 350));
    }

    VideoCatalogPageState catalog() => t.state(find.byType(VideoCatalogPage));
    Future<void> decoded() => until(() {
      if (find.byType(MovieStage).evaluate().length != 1) return false;
      final players = t
          .widget<MovieStage>(find.byType(MovieStage))
          .session!
          .debugPlayers;
      expect(players.length, lessThanOrEqualTo(3));
      return players.any(
        (p) =>
            p.value.isInitialized && p.value.isPlaying && !p.value.size.isEmpty,
      );
    }, 'actual initialized playing native video');
    Future<void> capture(String state) async {
      await t.pump(const Duration(milliseconds: 200));
      final root = find.byType(PackReaderPage).evaluate().isNotEmpty
          ? find.byType(PackReaderPage)
          : find.byType(MovieStage).evaluate().isNotEmpty
          ? find.byType(MovieStage)
          : find.byKey(const Key('app-shell'));
      final media = MediaQuery.of(t.element(root));
      List<double> rect(Rect r) => [r.left, r.top, r.width, r.height];
      final texts = <Map<String, dynamic>>[];
      for (final element in find.byType(Text).evaluate()) {
        final text = element.widget as Text, box = element.renderObject;
        if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
        final at = box.localToGlobal(Offset.zero);
        if (at.dy < 0 || at.dy >= media.size.height) continue;
        texts.add({
          'text': text.data ?? text.textSpan?.toPlainText(),
          'rect': rect(at & box.size),
          'fontSize': text.style?.fontSize,
        });
      }
      debugPrint(
        'FIDELITY_METRICS:${jsonEncode({
          'state': state,
          'size': [media.size.width, media.size.height],
          'dpr': media.devicePixelRatio,
          'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
          'viewInsets': [media.viewInsets.left, media.viewInsets.top, media.viewInsets.right, media.viewInsets.bottom],
          'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
          'textScale': media.textScaler.scale(14) / 14,
          'texts': texts,
          'history_rows': [for (final e in find.byType(MediaHistoryRow).evaluate())
            if (e.renderObject is RenderBox) rect((e.renderObject as RenderBox).localToGlobal(Offset.zero) & (e.renderObject as RenderBox).size)],
          'video_catalog': find.byType(VideoCatalogPage).evaluate().length != 1 ? null : {'source': catalog().entry.source.name, 'scrollOffset': catalog().scroll.hasClients ? catalog().scroll.offset : null, 'listHeader': catalog().listHeader, 'stride': catalog().stride, 'offset': catalog().data.offset},
          'pack_catalog': find.byType(PackCatalogPage).evaluate().length != 1 ? null : {'source': t.state<PackCatalogPageState>(find.byType(PackCatalogPage)).entry.source.name, 'scrollOffset': t.state<PackCatalogPageState>(find.byType(PackCatalogPage)).scroll.hasClients ? t.state<PackCatalogPageState>(find.byType(PackCatalogPage)).scroll.offset : null, 'listHeader': t.state<PackCatalogPageState>(find.byType(PackCatalogPage)).listHeader, 'stride': t.state<PackCatalogPageState>(find.byType(PackCatalogPage)).stride},
          'round': repo.playbackIdentity,
          'current': repo.current?.id,
          'library_ready': repo.libraryPreparation.value.ready,
        })}',
      );
      await control('/checkpoint/$state', post: true);
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while ((await control('/state'))['ack'] != true) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Missing screenshot $state');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    PackCatalogPageState packs() => t.state(find.byType(PackCatalogPage));
    PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
    Future<void> videoReady(int total) => until(
      () =>
          find.byType(VideoCatalogPage).evaluate().length == 1 &&
          catalog().initialized &&
          !catalog().data.loading &&
          !catalog().busy &&
          !catalog().viewing &&
          catalog().pendingReturn == null &&
          catalog().data.total == total,
      'video list $total',
    );
    Future<void> packReady(int total) => until(
      () =>
          find.byType(PackCatalogPage).evaluate().length == 1 &&
          packs().initialized &&
          !packs().data.loading &&
          packs().pendingReturn == null &&
          packs().data.total == total,
      'pack list $total',
    );
    Future<void> clearSearch(bool pack) async {
      await t.scrollUntilVisible(
        find.text('清除'),
        -160,
        scrollable: find.descendant(
          of: find.byKey(Key(pack ? 'pack-grid' : 'video-grid')),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await tap(find.text('清除'));
      await (pack ? packReady(4) : videoReady(2));
    }

    final keyboardCaptured = <bool>{};
    Future<void> search(String value, bool pack) async {
      final field = find.byKey(Key(pack ? 'pack-search' : 'video-search'));
      await t.pump();
      await tap(field);
      await t.enterText(field, value);
      await until(
        () => t.widget<TextField>(field).controller!.text == value,
        'entered search text',
      );
      await (pack ? packReady(1) : videoReady(1));
      if (keyboardCaptured.add(pack)) {
        await until(
          () =>
              MediaQuery.of(t.element(find.byKey(const Key('app-shell'))))
                  .viewInsets
                  .bottom >
              0,
          'actual system keyboard visible',
        );
        final media = MediaQuery.of(
          t.element(find.byKey(const Key('app-shell'))),
        );
        expect(media.viewInsets.bottom, greaterThan(0));
        expect(find.byKey(const Key('app-navigation')), findsNothing);
        expect(field.hitTestable(), findsOneWidget);
        if (media.textScaler.scale(14) / 14 > 1 &&
            media.size.height > media.size.width) {
          final action = pack
              ? find.byKey(const Key('pack-quick-cleanup'))
              : find.widgetWithText(FilledButton, '预览此范围');
          expect(action.hitTestable(), findsOneWidget);
          expect(
            t.getRect(action).bottom,
            lessThanOrEqualTo(media.size.height - media.viewInsets.bottom),
          );
        }
        await capture(pack ? 'recent-keyboard-pack' : 'recent-keyboard-video');
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
    }

    Future<void> returnVideo(int total) async {
      if (find
          .byKey(const Key('preview-back'))
          .hitTestable()
          .evaluate()
          .isEmpty) {
        await t.tap(find.byKey(const Key('video-gesture-surface')).last);
      }
      await tap(find.byKey(const Key('preview-back')));
      await until(
        () => find.byKey(const Key('video-preview-route')).evaluate().isEmpty,
        'preview route gone',
      );
      await videoReady(total);
    }

    Future<void> openPack(String id) async {
      await tap(find.byKey(Key('pack-tile-$id')));
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().length == 1 &&
            reader().session.opened &&
            !reader().session.busy,
        'actual first image read',
      );
    }

    Future<void> returnPack(int total) async {
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'reader gone',
      );
      await packReady(total);
    }

    Future<Object?> progress(String id) async =>
        (await repo.api.json('GET', '/api/v1/packs/$id'))['progress'];
    void historyRows(int n) {
      expect(find.byType(MediaHistoryRow), findsNWidgets(n));
      expect(find.byKey(const Key('video-search')), findsNothing);
      expect(find.byKey(const Key('pack-search')), findsNothing);
    }

    await videoReady(2);
    await until(
      () => repo.libraryPreparation.value.ready,
      'initial preparation',
    );
    final ids = catalog().data.items.map((v) => v.id).toList();
    final allPacks = await repo.loadPacks(PackQuery());
    final kimono = allPacks.items.singleWhere(
      (p) => p.displayTitle.contains('加藤惠'),
    );
    final summer = allPacks.items.singleWhere((p) => p.displayTitle == '夏日祭');
    final initialProgress = await progress(summer.id);
    expect(repo.playbackIdentity, isEmpty);
    await tap(find.byKey(const Key('nav-recent')));
    await videoReady(0);
    expect(find.text('还没有观看记录'), findsOneWidget);
    await capture('recent-empty-video');
    await tap(find.byKey(const Key('kind-pack')));
    await packReady(0);
    expect(find.text('还没有观看记录'), findsOneWidget);
    expect(await progress(summer.id), initialProgress);
    await capture('recent-empty-pack');

    await tap(find.byKey(const Key('nav-library')));
    await tap(find.byKey(const Key('kind-video')));
    await videoReady(2);
    await search('风里的花园', false);
    await tap(find.byKey(Key('tile-${ids.first}')));
    await decoded();
    await until(
      () async => (await repo.api.json('GET', '/api/v1/recent'))['total'] == 1,
      'first frame recorded',
    );
    await returnVideo(1);
    await tap(find.byKey(const Key('nav-recent')));
    await tap(find.byKey(const Key('kind-video')));
    await videoReady(1);
    await until(
      () => find.byType(MediaHistoryRow).evaluate().length == 1,
      'one history row',
    );
    historyRows(1);
    expect(catalog().entry.entry.source, BrowseSource.recent);
    expect(catalog().data.items.single.id, ids.first);
    expect(catalog().data.items.single.durationLabel, '0:05');
    await capture('recent-video-one');
    await tap(find.byKey(Key('recent-video-${ids.first}')));
    await decoded();
    expect(repo.playbackTotal, 1);
    expect(repo.savedPreviewEntry!.source, BrowseSource.recent);
    final recentRound = repo.playbackIdentity;
    await capture('recent-video-preview');
    if (find
        .byKey(const Key('preview-scope'))
        .hitTestable()
        .evaluate()
        .isEmpty) {
      await t.tap(find.byKey(const Key('video-gesture-surface')).last);
    }
    await tap(find.byKey(const Key('preview-scope')));
    final entries =
        (await repo.api.json(
              'GET',
              '/api/v1/rounds/$recentRound/entries',
              query: {'limit': '100'},
            ))['items']
            as List;
    expect(entries.map((r) => r['video']['id']).toList(), [ids.first]);
    await capture('recent-video-queue');
    await tap(find.byTooltip('关闭面板'));
    await returnVideo(1);

    await tap(find.byKey(const Key('nav-library')));
    await videoReady(1);
    expect(catalog().search.text, '风里的花园');
    await clearSearch(false);
    await search('水边的花', false);
    await tap(find.byKey(Key('tile-${ids.last}')));
    await decoded();
    await until(
      () async => (await repo.api.json('GET', '/api/v1/recent'))['total'] == 2,
      'second history video',
    );
    await returnVideo(1);
    await clearSearch(false);
    await search('风里的花园', false);
    await tap(find.byKey(const Key('nav-recent')));
    await videoReady(2);
    await until(
      () => find.byType(MediaHistoryRow).evaluate().length == 2,
      'two history rows',
    );
    historyRows(2);
    expect(
      catalog().data.items.map((v) => v.id).toList(),
      ids.reversed.toList(),
    );
    await capture('recent-video-two');
    await tap(find.byKey(const Key('nav-library')));
    await videoReady(1);
    expect(catalog().search.text, '风里的花园');
    await control('/recent-failure/video/on', post: true);
    await tap(find.byKey(const Key('nav-recent')));
    await until(
      () => !catalog().data.loading && catalog().data.error.isNotEmpty,
      'video failure retains rows',
    );
    expect(catalog().data.items.length, 2);
    await capture('recent-video-error');
    await control('/recent-failure/video/off', post: true);
    await tap(find.byKey(const Key('library-return-retry')));
    await videoReady(2);
    expect(catalog().data.error, isEmpty);
    await capture('recent-video-retry');

    await tap(find.byKey(const Key('nav-library')));
    await tap(find.byKey(const Key('kind-pack')));
    await packReady(4);
    await search('加藤惠', true);
    await openPack(kimono.id);
    await returnPack(1);
    await clearSearch(true);
    await search('夏日祭', true);
    await openPack(summer.id);
    expect(reader().session.index, 2);
    await returnPack(1);
    await tap(find.byKey(const Key('nav-recent')));
    await tap(find.byKey(const Key('kind-pack')));
    await packReady(2);
    await until(
      () => find.byType(MediaHistoryRow).evaluate().length == 2,
      'two pack rows',
    );
    historyRows(2);
    expect(packs().data.items.map((p) => p.id).toList(), [
      summer.id,
      kimono.id,
    ]);
    final beforeRead = await progress(summer.id);
    await capture('recent-packs-two');
    await tap(find.byKey(Key('recent-pack-${summer.id}')));
    await until(
      () =>
          find.byType(PackReaderPage).evaluate().length == 1 &&
          reader().session.opened &&
          !reader().session.busy,
      'recent reader first frame',
    );
    expect(reader().session.index, 2);
    expect(reader().session.range!.candidateCount, 2);
    expect(reader().session.entry.source, BrowseSource.recent);
    final recentPackRange = reader().session.range!.id;
    await capture('recent-pack-reader');
    await tap(find.byTooltip('图包更多'));
    await tap(find.text('本次图包范围'));
    await until(
      () =>
          reader().session.queuePage != null && !reader().session.loadingQueue,
      'recent pack queue',
    );
    expect(reader().session.queuePage!.entries.map((p) => p.pack.id).toList(), [
      summer.id,
      kimono.id,
    ]);
    await capture('recent-pack-range');
    await tap(find.byTooltip('关闭面板'));
    await returnPack(2);
    await capture('recent-pack-return');
    final beforeRetry = await progress(summer.id);
    await tap(find.byKey(const Key('nav-library')));
    await packReady(1);
    expect(packs().search.text, '夏日祭');
    await control('/recent-failure/pack/on', post: true);
    await tap(find.byKey(const Key('nav-recent')));
    await until(
      () => !packs().data.loading && packs().data.error.isNotEmpty,
      'pack failure retains rows',
    );
    expect(packs().data.items.length, 2);
    expect(await progress(summer.id), beforeRetry);
    await capture('recent-pack-error');
    await control('/recent-failure/pack/off', post: true);
    await tap(find.byKey(const Key('pack-list-retry')));
    await packReady(2);
    expect(packs().data.error, isEmpty);
    expect(await progress(summer.id), beforeRetry);
    await capture('recent-pack-retry');
    await tap(find.byKey(const Key('nav-library')));
    await packReady(1);
    expect(packs().search.text, '夏日祭');
    await capture('recent-isolation');
    await tap(find.byKey(const Key('kind-video')));
    await videoReady(1);
    expect(catalog().search.text, '风里的花园');
    debugPrint(
      'RECENT_HISTORY_VERIFIED:${jsonEncode({
        'video_ids': ids,
        'recent_round': recentRound,
        'recent_video_entries': entries.length,
        'recent_pack_range': recentPackRange,
        'pack_ids': [summer.id, kimono.id],
        'initial_progress': initialProgress,
        'before_read': beforeRead,
        'before_retry': beforeRetry,
        'after_retry': await progress(summer.id),
        'library_video_search': catalog().search.text,
      })}',
    );
    debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
  });
}
