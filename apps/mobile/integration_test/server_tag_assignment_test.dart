import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import '../test/support/reveal_action.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF8 native single assignments, independent creation and complete batch append',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final store = MemoryCredentialStore();
      final preferences = UiPreferences(preloadAdjacent: false);
      final repo = ServerLibraryRepository(store, port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '全选图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      for (var i = 0; i < 61; i++) {
        final name = '分页${i.toString().padLeft(2, '0')}';
        for (final namespace in ['tags', 'pack-tags']) {
          await repo.api.json(
            'POST',
            '/api/v1/$namespace',
            body: {'request_id': 'assignment-$namespace-$i', 'name': name},
          );
        }
      }
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
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );

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
        await revealAction(t, finder);
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
        final view = MediaQueryData.fromView(t.view);
        debugPrint(
          'TAG_ASSIGNMENT_METRICS:${jsonEncode({
            'state': phase,
            'window': [view.size.width, view.size.height],
            'dpr': view.devicePixelRatio,
            'text13': view.textScaler.scale(13),
            'keyboard': view.viewInsets.bottom,
            'dark': preferences.dark,
          })}',
        );
        await fixture('/__fixture/checkpoint/tag-ui-assign-$phase');
        await t.pump(const Duration(seconds: 2));
      }

      Future<void> hideKeyboard() async {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await until(
          () => MediaQueryData.fromView(t.view).viewInsets.bottom == 0,
          'keyboard closed',
        );
      }

      Future<void> single(bool pack) async {
        await until(() {
          final page = find.byType(pack ? PackCatalogPage : VideoCatalogPage);
          if (page.evaluate().isEmpty) return false;
          return pack
              ? t.state<PackCatalogPageState>(page).data.items.isNotEmpty
              : t.state<VideoCatalogPageState>(page).data.items.isNotEmpty;
        }, 'catalogue loaded actual items before single assignment');
        final id = pack
            ? t
                  .state<PackCatalogPageState>(find.byType(PackCatalogPage))
                  .data
                  .items
                  .first
                  .id
            : t
                  .state<VideoCatalogPageState>(find.byType(VideoCatalogPage))
                  .data
                  .items
                  .first
                  .id;
        if (pack) {
          final item = t
              .state<PackCatalogPageState>(find.byType(PackCatalogPage))
              .data
              .items
              .first;
          await tap(find.byTooltip('图包操作 ${item.displayTitle}'));
          await tap(find.text('整包标签'));
        } else {
          final item = t
              .state<VideoCatalogPageState>(find.byType(VideoCatalogPage))
              .data
              .items
              .first;
          await tap(find.byTooltip('编辑标签 ${item.name}'));
        }
        final type = pack ? 'pack' : 'video';
        await shot('$type-single');
        if (!pack) {
          await preferences.setDark(true);
          await t.pumpAndSettle();
          await shot('video-dark');
          await preferences.setDark(false);
          await t.pumpAndSettle();
        }
        await tap(find.widgetWithText(FilterChip, '保留'));
        final search = find.byKey(const Key('tag-assignment-search'));
        await tap(search);
        await t.enterText(search, '追加');
        await idle();
        await tap(find.widgetWithText(FilterChip, '追加'));
        final input = find.byKey(const Key('tag-assignment-new'));
        await tap(input);
        await t.enterText(input, '追加');
        await tap(find.byKey(const Key('tag-assignment-add')));
        expect(t.widget<TextField>(input).controller!.text, '追加');
        expect(find.byKey(const Key('tag-assignment-error')), findsOneWidget);
        await hideKeyboard();
        await shot('$type-error');
        await tap(input);
        await t.enterText(input, '现场新标签');
        await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        await until(
          () => MediaQueryData.fromView(t.view).viewInsets.bottom > 0,
          'native keyboard opened',
        );
        await shot('$type-keyboard');
        await hideKeyboard();
        await tap(find.byKey(const Key('tag-assignment-save')));
        await until(
          () => find.byKey(const Key('tag-assignment-save')).evaluate().isEmpty,
          'assignment saved and sheet closed',
        );
        final stats = await fixture('/__fixture/actions/tag-management-stats');
        final defs = (stats[pack ? 'pack_tags' : 'video_tags'] as List)
            .cast<Map>();
        final created = defs.singleWhere((tag) => tag['name'] == '现场新标签')['id'];
        final linked = (stats[pack ? 'pack_links' : 'video_links'] as List)
            .cast<Map>()
            .where((link) => link[pack ? 'pack_id' : 'video_id'] == id)
            .map((link) => link['tag_id'])
            .toSet();
        expect(linked, {pack ? packAdded.id : added, created});
        await shot('$type-saved');
      }

      await idle();
      await single(false);
      await tap(find.byKey(const Key('kind-pack')));
      await single(true);
      final separate = await fixture('/__fixture/actions/tag-management-stats');
      final videoNew = (separate['video_tags'] as List).cast<Map>().singleWhere(
        (t) => t['name'] == '现场新标签',
      )['id'];
      final packNew = (separate['pack_tags'] as List).cast<Map>().singleWhere(
        (t) => t['name'] == '现场新标签',
      )['id'];
      expect(videoNew, isNot(packNew));
      // Reset known fixture assignments before testing the complete 27-ID batch.
      await repo.setVideoTags(videos, {kept}, replace: true);
      await repo.setPackTags(packs, {packKept.id}, replace: true);
      await tap(find.byKey(const Key('kind-video')));
      final videoState = t.state<VideoCatalogPageState>(
        find.byType(VideoCatalogPage),
      );
      await until(
        () => videoState.data.items.length == 24,
        'video catalogue first 24 members loaded',
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
      await shot('video-batch');
      await tap(find.byKey(const Key('tag-assignment-search')));
      await t.enterText(find.byKey(const Key('tag-assignment-search')), '追加');
      await idle();
      await hideKeyboard();
      await tap(find.widgetWithText(FilterChip, '追加'));
      await tap(find.byKey(const Key('tag-assignment-save')));
      await until(
        () => find.byKey(const Key('tag-assignment-save')).evaluate().isEmpty,
        'assignment saved and sheet closed',
      );
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
      await until(
        () => packState.data.items.length == 24,
        'pack catalogue first 24 members loaded',
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
      await shot('pack-batch');
      await tap(find.byKey(const Key('tag-assignment-search')));
      await t.enterText(find.byKey(const Key('tag-assignment-search')), '追加');
      await idle();
      await hideKeyboard();
      await tap(find.widgetWithText(FilterChip, '追加'));
      await tap(find.byKey(const Key('tag-assignment-save')));
      await until(
        () => find.byKey(const Key('tag-assignment-save')).evaluate().isEmpty,
        'assignment saved and sheet closed',
      );
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
      final stats = await fixture('/__fixture/actions/tag-management-stats');
      for (final pack in [false, true]) {
        final all = pack ? packs : videos;
        final excluded = pack ? excludedPack : excludedVideo;
        final preserved = pack ? packKept.id : kept;
        final appended = pack ? packAdded.id : added;
        final links = (stats[pack ? 'pack_links' : 'video_links'] as List)
            .cast<Map>();
        for (final id in all) {
          final tags = links
              .where((r) => r[pack ? 'pack_id' : 'video_id'] == id)
              .map((r) => r['tag_id'])
              .toSet();
          expect(tags, id == excluded ? {preserved} : {preserved, appended});
        }
      }
      debugPrint(
        'TAG_ASSIGNMENT_VERIFIED:${jsonEncode({'videos': videos.toList(), 'packs': packs.toList(), 'excluded_video': excludedVideo, 'excluded_pack': excludedPack, 'video_preserved': kept, 'video_appended': added, 'pack_preserved': packKept.id, 'pack_appended': packAdded.id, 'video_created': videoNew, 'pack_created': packNew})}',
      );
      await shot('verified');
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
