import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Preview panels and real native controls preserve the fixed source', (
    t,
  ) async {
    final previousError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('PREVIEW_PANELS_ERROR:$details');
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
              'PREVIEW_PANELS_TIMEOUT_STATE:${jsonEncode({'search': s.search.text, 'entry': s.entry.search, 'loaded_entry': s.data.context.search, 'active': s.widget.active, 'viewing': s.viewing, 'busy': s.busy, 'loading': s.data.loading, 'total': s.data.total, 'error': s.data.error})}',
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
      final root =
          find.byKey(const Key('video-preview-route')).evaluate().isNotEmpty
          ? find.byKey(const Key('video-preview-route'))
          : find.byKey(const Key('app-shell'));
      final media = MediaQuery.of(t.element(root));
      List<double> rect(Rect r) => [r.left, r.top, r.width, r.height];
      final keys = <String, List<double>>{};
      for (final name in [
        'preview-scope',
        'preview-position',
        'playback-controls',
        'playback-time',
        'video-progress-touch',
        'preview-quick',
        'preview-quick-delete',
        'preview-queue',
        'preview-queue-frame',
        'preview-queue-note',
        'preview-end-return',
        'inline-play',
      ]) {
        final f = find.byKey(Key(name));
        if (f.evaluate().length == 1 &&
            f.evaluate().single.renderObject is RenderBox) {
          keys[name] = rect(t.getRect(f));
        }
      }
      final players = find.byType(MovieStage).evaluate().isEmpty
          ? null
          : t.widget<MovieStage>(find.byType(MovieStage)).session!.debugPlayers;
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
          'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
          'textScale': media.textScaler.scale(14) / 14,
          'texts': texts,
          'keys': keys,
          'queue_decoded': find.descendant(of: find.byKey(const Key('preview-queue')), matching: find.byType(RawImage)).evaluate().where((e) => (e.widget as RawImage).image != null).length,
          'queue_order_enabled': find.byKey(const Key('queue-order-sequential')).evaluate().isEmpty ? null : t.widget<ChoiceChip>(find.byKey(const Key('queue-order-sequential'))).onSelected != null,
          'dark': preferences.dark,
          'theme_primary': Theme.of(t.element(root)).colorScheme.primary.toARGB32(),
          'back_color': find.byKey(const Key('preview-back')).evaluate().isEmpty ? null : IconTheme.of(t.element(find.descendant(of: find.byKey(const Key('preview-back')), matching: find.byType(Icon)))).color?.toARGB32(),
          'players': players?.map((p) => {'initialized': p.value.isInitialized, 'playing': p.value.isPlaying, 'position_ms': p.value.position.inMilliseconds, 'speed': p.value.playbackSpeed}).toList(),
          'round': repo.playbackIdentity,
          'current': repo.current?.id,
          'library_ready': repo.libraryPreparation.value.ready,
        })}',
      );
      await control('/checkpoint/$state', post: true);
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while ((await control('/state'))['ack'] != true) {
        if (DateTime.now().isAfter(deadline)) fail('Missing screenshot $state');
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    await until(
      () =>
          find.byType(VideoCatalogPage).evaluate().length == 1 &&
          catalog().initialized &&
          repo.libraryPreparation.value.ready &&
          !catalog().data.loading,
      'initial library',
    );
    final names = catalog().data.items.map((v) => v.name).toList();
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '预览此范围'))
          .onPressed,
      isNotNull,
    );
    expect(names, ['风里的花园.mp4', '水边的花.mp4']);
    final ids = catalog().data.items.map((v) => v.id).toList();
    await until(
      () =>
          find
              .byType(RawImage)
              .evaluate()
              .where((e) => (e.widget as RawImage).image != null)
              .length >=
          2,
      'decoded covers',
    );
    expect(repo.playbackIdentity, isEmpty);
    expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 0);
    expect((await repo.selectVideoIds(catalog().entry.entry)).toList(), ids);
    await capture('preview-library');
    await t.enterText(find.byKey(const Key('video-search')), '风里的花园');
    await until(
      () => !catalog().data.loading && catalog().data.total == 1,
      'one filtered video',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    expect(repo.playbackIdentity, isEmpty);
    await capture('preview-filter');
    await tap(find.text('预览此范围'));
    await decoded();
    final filtered = repo.playbackIdentity;
    expect(repo.playbackTotal, 1);
    expect(repo.savedPreviewEntry!.sort, VideoSort.name);
    expect(repo.savedPreviewEntry!.search, '风里的花园');
    await until(
      () async => (await repo.api.json('GET', '/api/v1/recent'))['total'] == 1,
      'filtered first frame recorded',
    );
    await capture('preview-preview');
    await tap(find.byKey(const Key('preview-back')));
    await until(
      () =>
          find.byKey(const Key('video-preview-route')).evaluate().isEmpty &&
          !catalog().viewing &&
          !catalog().busy &&
          !catalog().data.loading &&
          catalog().pendingReturn == null,
      'return to filtered library',
    );
    expect(catalog().search.text, '风里的花园');
    expect(catalog().data.items.single.id, ids.first);
    await capture('preview-filter-return');
    await t.scrollUntilVisible(
      find.text('清除'),
      -160,
      scrollable: find.descendant(
        of: find.byKey(const Key('video-grid')),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      ),
    );
    await tap(find.text('清除'));
    expect(catalog().search.text, isEmpty);
    await until(
      () => !catalog().data.loading && catalog().data.total == 2,
      'clear search',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await tap(find.byKey(Key('tile-${ids.first}')));
    await decoded();
    final range = repo.playbackIdentity;
    expect(range, isNot(filtered));
    expect(repo.playbackTotal, 2);
    if (find
        .byKey(const Key('preview-scope'))
        .hitTestable()
        .evaluate()
        .isEmpty) {
      await t.tap(find.byKey(const Key('video-gesture-surface')).last);
    }
    await tap(find.byKey(const Key('preview-scope')));
    await tap(find.byKey(const Key('queue-order-sequential')));
    await until(
      () => repo.snapshot.order == PlayOrder.sequential,
      'explicit source order for controls comparison',
    );
    await tap(find.byTooltip('关闭面板'));
    await decoded();
    await until(
      () =>
          find.byType(PlayerSurface).evaluate().length == 1 &&
          t
              .widget<PlayerSurface>(find.byType(PlayerSurface))
              .interactionsEnabled,
      'source order applied and visible player resumed',
    );
    final session = t.widget<MovieStage>(find.byType(MovieStage)).session!;
    final controller = session.debugPlayers.single;
    await tap(
      find
          .descendant(
            of: find.byKey(const Key('playback-controls')),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await until(() => !controller.value.isPlaying, 'native pause');
    await capture('preview-paused');
    final track = t.getRect(find.byKey(const Key('video-progress-touch')));
    expect(track.width, greaterThanOrEqualTo(88));
    await t.dragFrom(
      Offset(track.left + track.width * .25, track.center.dy),
      Offset(track.width * .45, 0),
    );
    await until(
      () =>
          controller.value.position.inMilliseconds >
              controller.value.duration.inMilliseconds * .4 &&
          !controller.value.isPlaying,
      'paused seek through real drag',
    );
    final seekMs = controller.value.position.inMilliseconds;
    await capture('preview-seek');
    await tap(find.byTooltip('播放速度'));
    await capture('preview-speed-menu');
    await tap(find.text('1.5×'));
    await until(
      () => controller.value.playbackSpeed == 1.5,
      'native selected speed',
    );
    await tap(
      find
          .descendant(
            of: find.byKey(const Key('playback-controls')),
            matching: find.byType(TextButton),
          )
          .first,
    );
    await until(() => controller.value.isPlaying, 'resume before hold');
    final surface = t.getRect(
      find.byKey(const Key('video-gesture-surface')).last,
    );
    final hold = await t.startGesture(surface.topLeft + const Offset(24, 24));
    await t.pump(const Duration(milliseconds: 650));
    await until(
      () =>
          controller.value.playbackSpeed == 2 &&
          find.byKey(const Key('hold-speed-hint')).evaluate().isNotEmpty,
      'native hold boost',
    );
    await capture('preview-boost');
    await hold.up();
    await until(
      () =>
          controller.value.playbackSpeed == 1.5 &&
          find.byKey(const Key('hold-speed-hint')).evaluate().isEmpty,
      'restore chosen speed after release',
    );
    await tap(find.byKey(const Key('preview-quick')));
    expect(
      find.byKey(const Key('preview-quick-delete')).hitTestable(),
      findsOneWidget,
    );
    await capture('preview-quick');
    await tap(find.byKey(const Key('preview-quick')));
    await tap(find.text('视频标签'));
    await capture('preview-tags');
    await tap(find.byTooltip('关闭面板'));
    await tap(find.byTooltip('视频操作'));
    await capture('preview-more');
    await tap(find.text('视频详情'));
    await until(
      () => find.text(repo.current!.name).evaluate().length == 1,
      'details entered after preceding sheet closes',
    );
    await capture('preview-details');
    await tap(find.byTooltip('关闭面板'));
    await tap(find.byTooltip('视频操作'));
    await tap(find.text('切换暗黑模式'));
    await until(() => preferences.dark, 'dark preference saved');
    expect(repo.current!.id, ids.first);
    expect(repo.playbackIdentity, range);
    await until(() {
      final route = find.byKey(const Key('video-preview-route'));
      final back = find.descendant(
        of: find.byKey(const Key('preview-back')),
        matching: find.byType(Icon),
      );
      return Theme.of(t.element(route)).colorScheme.primary ==
              const PaperPalette(true).olive &&
          IconTheme.of(t.element(back)).color == const PaperPalette(true).olive;
    }, 'dark theme and rendered back action settled');
    await capture('preview-dark');
    await tap(find.byTooltip('视频操作'));
    await tap(find.text('切换浅色模式'));
    await until(() => !preferences.dark, 'light preference restored');
    await until(
      () =>
          Theme.of(t.element(find.byKey(const Key('video-preview-route'))))
              .colorScheme
              .primary ==
          const PaperPalette(false).olive,
      'light theme settled',
    );
    await capture('preview-light');
    await tap(find.byKey(const Key('preview-scope')));
    await tap(find.byKey(const Key('queue-order-sequential')));
    await until(
      () => repo.snapshot.order == PlayOrder.sequential,
      'sequential original source order',
    );
    final round = await repo.api.json(
      'GET',
      '/api/v1/playback',
      query: {'create': 'false'},
    );
    expect(round['sort'], 'name');
    expect(round['name_locale'], 'zh-CN');
    final rows =
        (await repo.api.json(
              'GET',
              '/api/v1/rounds/$range/entries',
              query: {'limit': '100'},
            ))['items']
            as List;
    final queueIds = rows.map((r) => r['video']['id'] as String).toList();
    expect(queueIds, ids);
    expect(repo.current!.id, ids.first);
    await until(
      () =>
          t
                  .widget<ChoiceChip>(
                    find.byKey(const Key('queue-order-sequential')),
                  )
                  .onSelected !=
              null &&
          find
                  .byKey(Key('queue-video-${ids.first}'))
                  .hitTestable()
                  .evaluate()
                  .length ==
              1 &&
          find
                  .descendant(
                    of: find.byKey(const Key('preview-queue')),
                    matching: find.byType(RawImage),
                  )
                  .evaluate()
                  .where((e) => (e.widget as RawImage).image != null)
                  .length >=
              2,
      'queue operation completed and both real cover frames decoded',
    );
    await capture('preview-queue');
    final queueFrame = t.getRect(find.byKey(const Key('preview-queue-frame')));
    final queueMedia = MediaQuery.of(
      t.element(find.byKey(const Key('preview-queue'))),
    );
    expect(
      queueFrame.width,
      closeTo(queueMedia.size.width - queueMedia.viewPadding.horizontal, 1),
    );
    if (queueMedia.size.width == 390 && queueMedia.textScaler.scale(14) == 14) {
      expect(
        queueFrame.height,
        lessThan(520),
        reason: 'Two-video range fits its contents instead of filling 83% of the screen',
      );
      expect(
        find.byKey(const Key('preview-queue-note')).hitTestable(),
        findsOneWidget,
      );
    }
    await tap(find.byKey(Key('queue-video-${ids.last}')));
    await until(
      () =>
          find.byKey(const Key('preview-queue')).evaluate().isEmpty &&
          repo.current?.id == ids.last,
      'select last ordered video',
    );
    await decoded();
    await until(
      () async => (await repo.api.json('GET', '/api/v1/recent'))['total'] == 2,
      'only actually displayed videos recorded',
    );
    await capture('preview-last');
    await tap(find.byKey(const Key('preview-next')));
    await until(
      () => find.byKey(const Key('preview-end-return')).evaluate().isNotEmpty,
      'range end sheet',
    );
    await capture('preview-end');
    await tap(find.byKey(const Key('preview-end-return')));
    await until(
      () =>
          find.byKey(const Key('video-preview-route')).evaluate().isEmpty &&
          !catalog().viewing &&
          !catalog().busy &&
          !catalog().data.loading &&
          catalog().pendingReturn == null,
      'return to full library',
    );
    expect(session.debugPlayers, isEmpty);
    expect(catalog().data.items.map((v) => v.id), ids);
    expect(catalog().entry.sort, VideoSort.name);
    expect(catalog().search.text, isEmpty);
    await capture('preview-return');
    await tap(find.byKey(const Key('nav-recent')));
    await until(
      () => !catalog().data.loading && catalog().data.total == 2,
      'actual recent videos',
    );
    expect(catalog().entry.source, BrowseSource.recent);
    expect(
      catalog().data.items.map((v) => v.id).toList(),
      ids.reversed.toList(),
    );
    await capture('preview-recent');
    debugPrint(
      'PREVIEW_PANELS_VERIFIED:${jsonEncode({'seek_ms': seekMs, 'restored_speed': controller.value.playbackSpeed, 'names': names, 'ids': ids, 'queue_ids': queueIds, 'filtered_round': filtered, 'full_round': range, 'public_sort': round['sort'], 'name_locale': round['name_locale'], 'recent': catalog().data.items.map((v) => v.id).toList()})}',
    );
    debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
  });
}
