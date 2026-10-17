import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'support/fixture.dart';
import 'support/server_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'preparation gates native playback, synchronizes progress, and paginates automatically',
    (t) async {
      final preparationFixture = await fixture(
        '/__fixture/actions/prepare-library',
      );
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      final preferences = UiPreferences(preloadAdjacent: false);
      final ui = ServerUi(t, repo);
      addTearDown(() async {
        await fixture('/__fixture/actions/normal-pages');
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 500));
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect('10.0.2.2', 8761, fixturePassword);
      expect(repo.libraryPreparation.value.ready, isFalse);
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byKey(const Key('library-preparation')), findsOneWidget);
      await fixture('/__fixture/checkpoint/preparing');
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await ui.text('查看媒体目录');
      expect(find.byKey(const Key('preparation-progress')), findsOneWidget);
      await ui.until(
        () => repo.libraryPreparation.value.ready,
        'first scan readiness synchronizes',
      );
      expect(repo.libraryPreparation.value.processed, 27);
      expect(repo.libraryPreparation.value.failed, 0);
      expect(repo.libraryPreparation.value.thumbnailFailed, 1);
      expect(find.textContaining('1 个缩略图待补充（不影响入库）'), findsOneWidget);
      await fixture('/__fixture/checkpoint/roots');
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await ui.tap(find.byTooltip('返回设置'));
      await ui.nav('library');
      expect(find.text('27 个视频'), findsOneWidget);
      await fixture('/__fixture/actions/slow-pages');
      final grid = find.byKey(const Key('video-grid'));
      await ui.until(
        () => find.byKey(const Key('library-count')).evaluate().isNotEmpty,
        'catalog page',
      );
      await t.drag(grid, const Offset(0, -6000));
      await ui.until(
        () =>
            find.byKey(const Key('library-loading-more')).evaluate().isNotEmpty,
        'animated pagination',
      );
      await fixture('/__fixture/checkpoint/loading-more');
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await ui.until(
        () => find.byKey(const Key('library-loading-more')).evaluate().isEmpty,
        'next page arrives',
      );
      await t.drag(grid, const Offset(0, -1000));
      await ui.until(
        () => find.text('已显示全部视频').evaluate().isNotEmpty,
        'all 27 cards loaded',
      );
      final trace = await fixture('/__fixture/trace', method: 'GET');
      final pages = (trace['items'] as List).where(
        (item) =>
            item['path'] == '/api/v1/videos' && item['query']['offset'] == '24',
      );
      expect(pages.length, 1);
      await fixture('/__fixture/actions/busy-streams');
      await repo.openVideo(preparationFixture['warning_video_id'] as String);
      await ui.nav('browse');
      await ui.ready();
      expect(
        t
            .widget<VideoPlayer>(find.byType(VideoPlayer).last)
            .controller
            .value
            .isInitialized,
        isTrue,
      );
      await fixture('/__fixture/checkpoint/prepared');
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      final playerTrace = await fixture('/__fixture/trace', method: 'GET');
      expect(
        (playerTrace['items'] as List)
            .where(
              (item) =>
                  (item['path'] as String).endsWith('/stream') &&
                  item['status'] == HttpStatus.serviceUnavailable,
            )
            .length,
        4,
      );
      expect(repo.playbackTotal, 27);
    },
  );
}
