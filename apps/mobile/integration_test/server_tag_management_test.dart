import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/tag_catalog_page.dart';
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
    'LF8 independent tag definitions, AND results, retained edits and paging',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '标签图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final videoIds = (await repo.loadVideos(limit: 2)).items
          .map((v) => v.id)
          .toList();
      final packId = (await repo.loadPacks(
        PackQuery(),
        limit: 1,
      )).items.single.id;
      final ids = <String>[];
      for (var i = 0; i < 61; i++) {
        final result = await repo.api.json(
          'POST',
          '/api/v1/tags',
          body: {
            'request_id': 'tag-ui-seed-$i',
            'name': '分页${i.toString().padLeft(2, '0')}',
          },
        );
        ids.add(result['id']);
      }
      final packTag =
          (await repo.api.json(
                'POST',
                '/api/v1/pack-tags',
                body: {'request_id': 'tag-ui-pack', 'name': '分页00'},
              ))['id']
              as String;
      await repo.setVideoTags(videoIds.toSet(), {ids.first});
      await repo.setVideoTags({videoIds.first}, {ids[1]});
      await repo.setPackTags({packId}, {packTag});
      final source = await fixture('/__fixture/actions/pack-trash-hashes');
      final media = await fixture('/__fixture/files', method: 'GET');
      final playback = await repo.api.json('GET', '/api/v1/playback');
      debugPrint(
        'TAG_MANAGEMENT_BASELINE:${jsonEncode({'video_ids': videoIds, 'pack_id': packId, 'tag_ids': ids, 'pack_tag': packTag, 'playback': playback, 'media': media})}',
      );
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );
      Future<void> until(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 70));
        }
        await t.pump(const Duration(milliseconds: 160));
        expect(t.takeException(), isNull);
      }

      Future<void> idle() => until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'reads settled',
      );
      Future<void> tap(Finder target) async {
        await revealAction(t, target);
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 200));
        await idle();
      }

      Future<void> shot(String state) async {
        await idle();
        final view = MediaQueryData.fromView(t.view);
        debugPrint(
          'TAG_MANAGEMENT_METRICS:${jsonEncode({
            'state': state,
            'window': [view.size.width, view.size.height],
            'dpr': view.devicePixelRatio,
            'text13': view.textScaler.scale(13),
            'keyboard': view.viewInsets.bottom,
            'dark': preferences.dark,
          })}',
        );
        await fixture('/__fixture/checkpoint/tag-ui-$state');
        await t.pump(const Duration(seconds: 1));
      }

      Future<void> hideKeyboard() async {
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await until(
          () => MediaQueryData.fromView(t.view).viewInsets.bottom == 0,
          'keyboard closed',
        );
      }

      Future<void> enterName(String value) async {
        final field = find.byKey(const Key('tag-name'));
        await tap(field);
        await t.enterText(field, value);
        await t.pumpAndSettle();
        await until(
          () => t.widget<TextField>(field).controller!.text == value,
          'edited name delivered',
        );
        await hideKeyboard();
        expect(t.widget<TextField>(field).controller!.text, value);
      }

      Future<void> save() async {
        final key = find.byKey(const Key('tag-definition-save'));
        await tap(key.evaluate().isNotEmpty ? key : find.text('保存').last);
      }

      TagCatalogPageState state() =>
          t.state<TagCatalogPageState>(find.byType(TagCatalogPage));
      await idle();
      await tap(find.byKey(const Key('nav-tags')));
      await tap(find.byKey(Key('video-tag-${ids.first}')));
      await tap(find.byKey(Key('video-tag-${ids[1]}')));
      await until(() => state().matching == 1, 'two tag intersection');
      await shot('video');
      await tap(find.byKey(const Key('kind-pack')));
      await tap(find.byKey(Key('pack-tag-$packTag')));
      await until(() => state().matching == 1, 'pack namespace');
      await shot('pack');
      await preferences.setDark(true);
      await t.pumpAndSettle();
      await shot('dark');
      await preferences.setDark(false);
      await t.pumpAndSettle();
      await tap(find.byTooltip('新建图包标签'));
      await tap(find.byKey(const Key('tag-name')));
      await t.enterText(find.byKey(const Key('tag-name')), '分页00');
      await until(
        () => MediaQueryData.fromView(t.view).viewInsets.bottom > 0,
        'real keyboard',
      );
      await shot('create-keyboard');
      await hideKeyboard();
      await save();
      await until(
        () => find.textContaining('已有同名').evaluate().isNotEmpty,
        'duplicate tag stays open',
      );
      expect(
        t.widget<TextField>(find.byKey(const Key('tag-name'))).controller!.text,
        '分页00',
      );
      await shot('create-error');
      await enterName('仅图包新标签');
      await save();
      await until(
        () => state().tags.any((v) => v.name == '仅图包新标签'),
        'created definition',
      );
      await shot('created');
      await tap(find.byTooltip('管理图包标签 分页00'));
      await enterName('图包改名');
      await save();
      await until(() => state().tags.any((v) => v.name == '图包改名'), 'rename');
      expect(state().selected, {packTag});
      expect(
        (await repo.loadPackTags(search: '图包改名')).items.single.id,
        packTag,
      );
      await shot('renamed');
      await tap(find.byTooltip('管理图包标签 图包改名'));
      await tap(find.text('移除这个标签'));
      await shot('remove-confirm');
      final cancel = find.text('取消').last;
      if (cancel.evaluate().isNotEmpty) {
        await tap(cancel);
      } else {
        await tap(find.byTooltip('关闭面板').last);
      }
      expect(
        (await repo.loadPackTags(search: '图包改名')).items.single.id,
        packTag,
      );
      await tap(find.text('移除这个标签'));
      await tap(find.text('确认移除标签'));
      await until(
        () => state().tags.every((v) => v.id != packTag),
        'removed definition',
      );
      expect(state().selected, isEmpty);
      expect(
        (await repo.loadVideoTags(search: '分页00')).items.single.id,
        ids.first,
      );
      await shot('removed');
      await tap(find.byKey(const Key('kind-video')));
      expect(state().selected, {ids.first, ids[1]});
      await fixture('/__fixture/actions/fail-tag-page');
      await tap(find.text('更多标签'));
      await shot('page-error');
      await tap(find.byKey(const Key('tag-read-retry')));
      await until(
        () => state().tags.length == state().total,
        'all tags loaded',
      );
      await revealAction(t, find.byKey(Key('video-tag-${ids.last}')));
      await shot('paged');
      await tap(find.byKey(const Key('tag-view-results')));
      await until(
        () => find.text('标签结果').evaluate().isNotEmpty,
        'library results',
      );
      await shot('results');
      expect(await fixture('/__fixture/actions/pack-trash-hashes'), source);
      final finalMedia = await fixture('/__fixture/files', method: 'GET');
      final finalPlayback = await repo.api.json('GET', '/api/v1/playback');
      expect(finalMedia, media);
      expect(finalPlayback, playback);
      debugPrint(
        'TAG_MANAGEMENT_FINAL:${jsonEncode({'playback': finalPlayback, 'media': finalMedia})}',
      );
      final stats = await fixture('/__fixture/actions/tag-management-stats');
      final links = (stats['video_links'] as List).cast<Map<String, dynamic>>();
      expect(
        links
            .where((v) => v['tag_id'] == ids.first)
            .map((v) => v['video_id'])
            .toSet(),
        videoIds.toSet(),
      );
      expect(
        links
            .where((v) => v['tag_id'] == ids[1])
            .map((v) => v['video_id'])
            .toSet(),
        {videoIds.first},
      );
      expect(
        (stats['pack_links'] as List).where((v) => v['tag_id'] == packTag),
        isEmpty,
      );
      debugPrint(
        'TAG_MANAGEMENT_VERIFIED:separate same names, duplicate preserved, rename retained id, cancelled removal, pack-only removal, two-tag AND=1, source and playback unchanged',
      );
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
