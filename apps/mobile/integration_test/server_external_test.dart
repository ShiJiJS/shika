import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';

import 'support/fixture.dart';
import 'support/server_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'I5 real external identity, missing pages, roots and interrupted scans',
    (t) async {
      final store = SecureCredentialStore(key: 'video_viewer.e2e.external.v1');
      final repo = ServerLibraryRepository(store, port: 8761);
      final preferences = UiPreferences(preloadAdjacent: false);
      final ui = ServerUi(t, repo);
      ServerApi? observer;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 300));
        repo.dispose();
        preferences.dispose();
        observer?.close();
      });
      Future<List<dynamic>> videos([String status = 'available']) async =>
          (await observer!.json(
                'GET',
                '/api/v1/videos',
                query: {'status': status, 'limit': '200'},
              ))['items']
              as List;
      Future<Map<String, dynamic>> files() async {
        final rows =
            (await fixture('/__fixture/files', method: 'GET'))['items'] as List;
        return {
          for (final r in rows)
            r['path'] as String: {'size': r['size'], 'sha256': r['sha256']},
        };
      }

      Future<void> roots() async {
        await ui.nav('settings');
        await ui.text('媒体目录');
        await ui.idle();
      }

      Future<void> scan({bool failure = false}) async {
        await roots();
        await ui.text('刷新媒体目录');
        if (failure) {
          expect(find.byKey(const Key('operation-error')), findsOneWidget);
        } else {
          expect(find.byKey(const Key('operation-error')), findsNothing);
          expect(repo.scanStatus.value, startsWith('扫描完成'));
        }
      }

      if (const bool.fromEnvironment('E2E_RESUME')) {
        final saved = (await store.read())!;
        observer = ServerApi(Uri.parse(fixtureBase), token: saved.token);
        final round = await observer.json('GET', '/api/v1/playback');
        final missing = await videos('missing');
        await t.pumpWidget(
          ShikaApp(
            repository: repo,
            preferences: preferences,
            initializeRepository: true,
          ),
        );
        await ui.until(() => repo.snapshot.connected, 'session restores');
        if (repo.current != null) await ui.ready();
        expect(repo.missingCount, missing.length);
        expect(missing.length, 26);
        expect(repo.snapshot.roots, hasLength(3));
        expect(
          (await observer.json('GET', '/api/v1/playback'))['id'],
          round['id'],
        );
        await roots();
        expect(find.textContaining('原标签'), findsWidgets);
        await t.scrollUntilVisible(
          find.text('加载更多缺失视频'),
          450,
          scrollable: find.byType(Scrollable).first,
        );
        await ui.text('加载更多缺失视频');
        expect(
          repo.snapshot.videos.where((v) => v.status.name == 'missing'),
          hasLength(26),
        );
        debugPrint(
          'EXTERNAL_REOPEN_RESULT {"same_round":true,"missing_26":true,"root_configuration":true,"tag_names":true,"session":true}',
        );
        await fixture('/__fixture/checkpoint/recovered');
        await t.pump(const Duration(seconds: 2));
        return;
      }
      await store.clear();
      await repo.connect('10.0.2.2', 8761, fixturePassword);
      observer = ServerApi(
        Uri.parse(fixtureBase),
        token: (await store.read())!.token,
      );
      final initial = await videos();
      String id(String name) =>
          initial.singleWhere((r) => (r['path'] as String).endsWith(name))['id']
              as String;
      final first = id('片段01.mp4'),
          second = id('片段02.mp4'),
          third = id('片段03.mp4'),
          fourth = id('片段04.mp4'),
          camera = id('相机片段.mov');
      final tag =
          (await observer.json(
                'POST',
                '/api/v1/tags',
                body: {'request_id': requestId(), 'name': '原标签'},
              ))['id']
              as String;
      await observer.json(
        'PATCH',
        '/api/v1/video-tags',
        body: {
          'request_id': requestId(),
          'video_ids': [first, second, third, fourth, camera],
          'tag_ids': [tag],
          'mode': 'add',
        },
      );
      await repo.refresh();
      await t.pumpWidget(
        ShikaApp(repository: repo, preferences: preferences),
      );
      await ui.ready();
      await ui.nav('library');
      await ui.search('片段01', 1);
      await ui.tap(find.byKey(Key('tile-$first')));
      await ui.ready();
      final roundId = (await observer.json('GET', '/api/v1/playback'))['id'];
      var expected = await files();
      Future<void> assertIdentity(String videoId, String ending) async {
        final row = (await videos()).singleWhere((r) => r['id'] == videoId);
        expect(row['path'], endsWith(ending));
        expect(row['tag_ids'], [tag]);
        expect(
          (await observer!.json('GET', '/api/v1/playback'))['id'],
          roundId,
        );
      }

      await fixture('/__fixture/actions/rename');
      await scan();
      expected['/media/shorts/改名/新的名称.mp4'] = expected.remove(
        '/media/shorts/自然/花卉/片段01.mp4',
      );
      await assertIdentity(first, '/改名/新的名称.mp4');
      expect(await files(), expected);
      await ui.nav('browse');
      await ui.ready();
      expect(repo.current!.id, first);
      expect(find.text('新的名称.mp4'), findsOneWidget);
      await fixture('/__fixture/actions/rename-in-place');
      await scan();
      expected['/media/shorts/自然/花卉/片段04_改名.mp4'] = expected.remove(
        '/media/shorts/自然/花卉/片段04.mp4',
      );
      await assertIdentity(fourth, '片段04_改名.mp4');
      await fixture('/__fixture/actions/move-cross');
      await scan();
      expected['/media/camera/移动/跨目录片段.mp4'] = expected.remove(
        '/media/shorts/改名/新的名称.mp4',
      );
      await assertIdentity(first, '/camera/移动/跨目录片段.mp4');
      expect(await files(), expected);
      await ui.nav('library');
      await ui.search('跨目录片段', 1);
      await ui.tap(find.byKey(Key('tile-$first')));
      await ui.ready();
      expect(repo.current!.rootId, 'camera');
      // Opening a known item explicitly starts its own round. Subsequent scans keep it.
      final movedRound = (await observer.json('GET', '/api/v1/playback'))['id'];
      await fixture('/__fixture/actions/remove');
      await scan();
      expected['/media/detached-samples/片段03.mp4'] = expected.remove(
        '/media/shorts/自然/花卉/片段03.mp4',
      );
      expect(repo.missingCount, 1);
      expect((await videos('missing')).single['id'], third);
      expect(find.byKey(Key('missing-$third')), findsOneWidget);
      await fixture('/__fixture/actions/return-removed');
      await scan();
      expected['/media/shorts/自然/花卉/片段03.mp4'] = expected.remove(
        '/media/detached-samples/片段03.mp4',
      );
      expect(repo.missingCount, 0);
      final restored = (await videos()).singleWhere((r) => r['id'] == third);
      expect(restored['tag_ids'], [tag]);
      await fixture('/__fixture/actions/duplicate');
      await scan();
      expected['/media/shorts/副本/重复副本.mp4'] =
          expected['/media/camera/移动/跨目录片段.mp4'];
      final duplicate = (await videos()).singleWhere(
        (r) => (r['path'] as String).endsWith('重复副本.mp4'),
      );
      expect(duplicate['id'], isNot(first));
      expect(duplicate['tag_ids'], isEmpty);
      await fixture('/__fixture/actions/replace');
      await scan();
      expected['/media/shorts/自然/花卉/片段02.mp4'] =
          expected['/media/camera/旅行/横版片段.mp4'];
      final replacement = (await videos()).singleWhere(
        (r) => (r['path'] as String).endsWith('片段02.mp4'),
      );
      expect(replacement['id'], isNot(second));
      expect(replacement['tag_ids'], isEmpty);
      final old = (await videos('missing'))
          .singleWhere((r) => r['id'] == second);
      expect(old['tag_ids'], [tag]);
      expect(await files(), expected);
      await fixture('/__fixture/actions/disconnect');
      await scan(failure: true);
      expect(
        repo.snapshot.roots.singleWhere((r) => r.id == 'camera').available,
        isFalse,
      );
      expect(repo.missingCount, 1);
      expect(find.textContaining('目录暂不可用'), findsWidgets);
      expect((await videos()).any((r) => r['root_id'] == 'camera'), isFalse);
      await fixture('/__fixture/checkpoint/roots');
      await t.pump(const Duration(seconds: 2));
      await fixture('/__fixture/actions/reconnect');
      await scan();
      expect(repo.snapshot.roots.every((r) => r.available), isTrue);
      expect(repo.missingCount, 1);
      expect(
        (await videos()).singleWhere((r) => r['id'] == camera)['tag_ids'],
        [tag],
      );
      expect(await files(), expected);
      await fixture('/__fixture/actions/fail-next-scan');
      await scan(failure: true);
      expect(repo.scanStatus.value, contains('扫描未完成'));
      expect((await videos()).singleWhere((r) => r['id'] == first)['tag_ids'], [
        tag,
      ]);
      await scan();
      expect(
        (await observer.json('GET', '/api/v1/playback'))['id'],
        movedRound,
      );
      final moves =
          (await fixture('/__fixture/actions/move-many-out'))['moved'] as List;
      for (final move in moves) {
        expected[move['to']] = expected.remove(move['from']);
      }
      await scan();
      expect(repo.missingCount, 26);
      expect(await files(), expected);
      await t.scrollUntilVisible(
        find.text('加载更多缺失视频'),
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await ui.text('加载更多缺失视频');
      expect(
        repo.snapshot.videos.where((v) => v.status.name == 'missing'),
        hasLength(26),
      );
      await fixture('/__fixture/checkpoint/library');
      await t.pump(const Duration(seconds: 2));
      await t.scrollUntilVisible(
        find.text('添加目录'),
        -500,
        scrollable: find.byType(Scrollable).first,
      );
      await ui.text('添加目录');
      await t.enterText(find.byType(TextField).at(0), '额外空目录');
      await t.enterText(find.byType(TextField).at(1), '/media/shorts/空目录');
      for (
        var attempt = 0;
        attempt < 3 && repo.snapshot.roots.length < 3;
        attempt++
      ) {
        await ui.text('保存');
        await ui.until(
          () =>
              repo.snapshot.roots.length == 3 ||
              find.textContaining('暂时无法连接服务').evaluate().isNotEmpty,
          'root save response',
        );
        if (repo.snapshot.roots.length < 3) {
          expect(
            t.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
            '额外空目录',
          );
          expect(
            t.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
            '/media/shorts/空目录',
          );
        }
      }
      await ui.until(
        () => repo.snapshot.roots.length == 3,
        'new server-generated root',
      );
      expect(
        repo.snapshot.roots.singleWhere((r) => r.name == '额外空目录').id,
        isNotEmpty,
      );
      expect(await files(), expected);
      await fixture('/__fixture/actions/slow-next-scan');
      await t.tap(find.text('刷新媒体目录'));
      await t.pump(const Duration(milliseconds: 150));
      await ui.until(
        () =>
            find.byKey(const Key('scan-status')).evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty,
        'observable running scan',
      );
      await fixture('/__fixture/checkpoint/outage');
      var down = false;
      for (var i = 0; i < 80 && !down; i++) {
        try {
          await fixture('/health', method: 'GET');
        } on IOException {
          down = true;
        }
        if (!down) await t.pump(const Duration(milliseconds: 100));
      }
      expect(down, isTrue);
      var up = false;
      for (var i = 0; i < 160 && !up; i++) {
        try {
          await fixture('/health', method: 'GET');
          up = true;
        } on IOException {
          await t.pump(const Duration(milliseconds: 150));
        }
      }
      expect(up, isTrue);
      await ui.idle();
      for (var attempt = 0; attempt < 3; attempt++) {
        await ui.text('刷新媒体目录');
        if ((repo.scanStatus.value ?? '').startsWith('扫描完成')) break;
      }
      expect(repo.scanStatus.value, startsWith('扫描完成'));
      expect(find.byKey(const Key('operation-error')), findsNothing);
      expect(repo.missingCount, 26);
      expect(await files(), expected);
      debugPrint(
        'EXTERNAL_RESULT ${jsonEncode({'rename_same_directory': true, 'move_within_root': true, 'move_between_roots': true, 'identity_tags_round_preserved': true, 'missing_and_return': true, 'duplicate_not_inherited': true, 'replacement_not_inherited': true, 'root_unavailable_not_mass_missing': true, 'scan_failure_no_fake_success': true, 'missing_26_paged': true, 'new_root_creation': true, 'running_scan_and_docker_recovery': true, 'exact_file_paths_sizes_hashes': true})}',
      );
      await fixture('/__fixture/checkpoint/done');
      expect(t.takeException(), isNull);
    },
  );
}
