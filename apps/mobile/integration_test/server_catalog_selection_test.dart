import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF4 complete native selection, individual exclusion and append',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final store = SecureCredentialStore(key: 'video_viewer.e2e.selection.v1');
      await store.clear();
      final repo = ServerLibraryRepository(store, port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
        await store.clear();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '全选图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      await repo.editTag(name: '保留');
      await repo.editTag(name: '追加');
      String videoTag(String name) =>
          repo.snapshot.tags.singleWhere((id) => repo.tagName(id) == name);
      final kept = videoTag('保留'), added = videoTag('追加');
      final packKept = await repo.createPackTag('保留');
      final packAdded = await repo.createPackTag('追加');
      final videos = await repo.selectVideoIds(VideoEntryScope());
      final packs = await repo.selectPackIds(PackQuery());
      expect(videos.length, 27);
      expect(packs.length, 27);
      await repo.setVideoTags(videos, {kept});
      await repo.setPackTags(packs, {packKept.id});
      await t.pumpWidget(VideoViewerApp(repository: repo));

      Future<void> until(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            await fixture('/__fixture/checkpoint/error');
            await t.pump(const Duration(seconds: 2));
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 200));
      }

      Future<void> idle() => until(
        () =>
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        'catalog settled',
      );
      Future<void> tap(Finder finder) async {
        await t.ensureVisible(finder);
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 300));
        await idle();
      }

      Future<void> multi() async {
        await tap(find.byTooltip('更多'));
        await tap(find.text('多选内容'));
      }

      Future<void> shot(String phase) async {
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/selection-$phase');
        await t.pump(const Duration(seconds: 2));
      }

      await idle();
      final videoState = t.state<VideoCatalogPageState>(
        find.byType(VideoCatalogPage),
      );
      expect(videoState.data.items.length, 24);
      final excludedVideo = videoState.data.items.first.id;
      await multi();
      await tap(find.byKey(const Key('video-select-all')));
      await until(
        () => videoState.selected.length == 27,
        'complete video membership',
      );
      await tap(find.byKey(Key('tile-$excludedVideo')));
      expect(videoState.selected.length, 26);
      expect(videoState.selected, isNot(contains(excludedVideo)));
      await shot('videos');
      await tap(find.text('追加标签'));
      await tap(find.widgetWithText(FilterChip, '追加'));
      await tap(find.text('完成'));
      expect(repo.tagVideoCount(added), 26);
      final updated = await repo.loadVideos(limit: 200);
      for (final video in updated.items) {
        expect(video.tags, contains(kept));
        expect(video.tags.contains(added), video.id != excludedVideo);
      }
      await tap(find.byKey(const Key('kind-pack')));
      final packState = t.state<PackCatalogPageState>(
        find.byType(PackCatalogPage),
      );
      expect(packState.data.items.length, 24);
      final excludedPack = packState.data.items.first.id;
      await multi();
      await tap(find.byKey(const Key('pack-select-all')));
      await until(
        () => packState.selected.length == 27,
        'complete pack membership',
      );
      await tap(find.byKey(Key('pack-tile-$excludedPack')));
      expect(packState.selected.length, 26);
      await shot('packs');
      await tap(find.text('追加标签'));
      await tap(find.widgetWithText(FilterChip, '追加'));
      await tap(find.text('追加所选标签'));
      final packPage = await repo.loadPacks(PackQuery(), limit: 200);
      for (final pack in packPage.items) {
        expect(pack.tags, contains(packKept.id));
        expect(pack.tags.contains(packAdded.id), pack.id != excludedPack);
      }
      // Switching types preserves independent selected IDs and mode.
      await tap(find.byKey(const Key('kind-video')));
      expect(videoState.selected.length, 26);
      expect(videoState.selecting, isTrue);
      expect(packState.selected.length, 26);
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
