import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/library/video_catalog_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';
import 'package:shika/ui/preferences.dart';

import 'native_workspace_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'preview order opens its own chooser and preserves native playback',
    (t) async {
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 500));
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect('http://10.0.2.2', 8768, 'client-ui-owned-only');
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      Future<void> until(bool Function() condition, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) fail(reason);
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        await until(
          () => target.hitTestable().evaluate().length == 1,
          '$target',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 400));
      }

      Future<void> capture(String name) async {
        await control('/checkpoint/$name', post: true);
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) fail('Missing capture $name');
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      await until(() {
        final page = find.byType(VideoCatalogPage);
        if (page.evaluate().length != 1) return false;
        final catalog = t.state<VideoCatalogPageState>(page);
        return repo.libraryPreparation.value.ready &&
            catalog.initialized &&
            !catalog.busy &&
            !catalog.data.loading &&
            catalog.data.items.isNotEmpty;
      }, 'library catalog ready for preview');
      await tap(find.byKey(const Key('video-quick-cleanup')));
      await until(
        () =>
            find.byType(MovieStage).evaluate().length == 1 &&
            t
                .widget<MovieStage>(find.byType(MovieStage))
                .session!
                .debugPlayers
                .any(
                  (player) =>
                      player.value.isInitialized && player.value.isPlaying,
                ),
        'native video playback',
      );
      final session = t.widget<MovieStage>(find.byType(MovieStage)).session!;
      final player = session.debugPlayers.single;
      final range = repo.playbackIdentity;
      final current = repo.current!.id;
      final total = repo.playbackTotal;
      final defaultOrder = preferences.videoOrder;

      for (final quick in [true, false]) {
        if (!quick) await tap(find.byKey(const Key('preview-quick')));
        for (final order in [PlayOrder.sequential, PlayOrder.random]) {
          await tap(find.byKey(const Key('preview-order')));
          expect(find.text('预览顺序'), findsOneWidget);
          expect(find.byKey(const Key('preview-queue')), findsNothing);
          expect(player.value.isPlaying, isFalse);
          if (quick && order == PlayOrder.sequential) {
            await capture('order-chooser');
          }
          await tap(find.byKey(Key('preview-order-${order.name}')));
          await until(
            () => repo.snapshot.order == order && player.value.isPlaying,
            'order changed and playback resumed',
          );
          expect(find.text('预览顺序'), findsNothing);
          expect(repo.playbackIdentity, range);
          expect(repo.current!.id, current);
          expect(repo.playbackTotal, total);
          expect(preferences.videoOrder, defaultOrder);
          expect(session.debugPlayers.single, same(player));
        }
      }
      await tap(find.byKey(const Key('preview-order')));
      await tap(find.byTooltip('关闭面板'));
      await until(() => player.value.isPlaying, 'cancel preserves playback');
      // A user-paused video must stay paused after switching order as well.
      await tap(
        find
            .descendant(
              of: find.byKey(const Key('playback-controls')),
              matching: find.byType(TextButton),
            )
            .first,
      );
      expect(player.value.isPlaying, isFalse);
      await player.seekTo(const Duration(seconds: 2));
      await tap(find.byKey(const Key('preview-order')));
      await tap(find.byKey(const Key('preview-order-sequential')));
      await until(
        () => repo.snapshot.order == PlayOrder.sequential,
        'paused order',
      );
      expect(player.value.isPlaying, isFalse);
      expect(
        player.value.position,
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      expect(session.debugPlayers.single, same(player));
      await capture('order-sequential');
      await tap(find.byKey(const Key('preview-scope')));
      expect(find.byKey(const Key('preview-queue')), findsOneWidget);
      expect(find.text('预览顺序'), findsNothing);
      await capture('order-range');
      await tap(find.byTooltip('关闭面板'));
      await tap(find.byKey(const Key('preview-back')));
      expect(find.byKey(const Key('video-preview-route')), findsNothing);
      expect(session.debugPlayers, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
}
