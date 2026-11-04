import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/file_command_store.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';
import 'package:shika/ui/sheets.dart';

import 'support/fixture.dart';
import 'support/server_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('I4 real review, precise undo, trash and durable reconciliation', (
    t,
  ) async {
    final store = SecureCredentialStore(key: 'video_viewer.e2e.files.v1');
    final journal = SecureFileCommandStore(
      key: 'video_viewer.e2e.file_commands.v1',
    );
    final repo = ServerLibraryRepository(
      store,
      port: 8761,
      fileCommands: journal,
    );
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
    Future<List<dynamic>> trash() async =>
        (await observer!.json(
              'GET',
              '/api/v1/trash',
              query: {'limit': '200'},
            ))['items']
            as List;
    Future<void> menu(String text) async {
      await ui.tap(find.byTooltip('更多'));
      await ui.text(text);
    }

    Future<Map<String, dynamic>> files() async {
      final items =
          (await fixture('/__fixture/files', method: 'GET'))['items'] as List;
      return {
        for (final item in items)
          item['path'] as String: {
            'size': item['size'],
            'sha256': item['sha256'],
          },
      };
    }

    Future<void> openTrash() async {
      await ui.nav('settings');
      await ui.text('回收站');
      await ui.until(
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        'trash page',
      );
    }

    Future<void> checkTrash(String id) async {
      final target = find.byKey(Key('trash-$id'));
      if (target.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          target,
          450,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await ui.tap(target);
    }

    if (const bool.fromEnvironment('E2E_RESUME')) {
      final saved = (await store.read())!;
      observer = ServerApi(Uri.parse(fixtureBase), token: saved.token);
      final before = await trash();
      expect(before, hasLength(24));
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: true,
        ),
      );
      await ui.until(
        () => repo.snapshot.connected && repo.fileOperationPending,
        'saved pending delete',
      );
      await ui.text('查询结果');
      await ui.until(
        () => !repo.fileOperationPending,
        'read-only result reconciliation',
      );
      final operation = repo.snapshot.lastDelete!;
      expect(operation.ids, hasLength(1));
      final item = before.singleWhere(
        (r) => r['video']['id'] == operation.ids.single,
      );
      expect(operation.id, item['operation_id']);
      await menu('撤销上次删除');
      await ui.until(
        () => repo.snapshot.lastDelete == null,
        'precise persisted undo',
      );
      expect(await trash(), hasLength(23));
      expect(repo.current!.id, operation.ids.single);
      await ui.ready();
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace.where(
          (r) => r['method'] == 'POST' && r['path'] == '/api/v1/videos/trash',
        ),
        isEmpty,
      );
      expect(
        trace.any(
          (r) =>
              r['method'] == 'GET' &&
              (r['path'] as String).contains('/file-requests/'),
        ),
        isTrue,
      );
      debugPrint(
        'FILES_REOPEN_RESULT {"pending_restored":true,"read_only_query":true,"precise_undo":true,"same_video_restored":true}',
      );
      await fixture('/__fixture/checkpoint/recovered');
      await t.pump(const Duration(seconds: 2));
      return;
    }
    await store.clear();
    await journal.write('{}');
    await repo.connect('10.0.2.2', 8761, fixturePassword);
    observer = ServerApi(
      Uri.parse(fixtureBase),
      token: (await store.read())!.token,
    );
    final catalog =
        (await observer.json(
              'GET',
              '/api/v1/videos',
              query: {'limit': '200'},
            ))['items']
            as List;
    String id(String name) =>
        catalog.singleWhere((r) => (r['path'] as String).endsWith(name))['id']
            as String;
    final first = id('片段01.mp4'), second = id('片段02.mp4');
    final beforeFiles = await files();
    final tagIds = <String>[];
    for (final name in ['整理范围', '花卉', '快捷标记']) {
      final tag = await observer.json(
        'POST',
        '/api/v1/tags',
        body: {'request_id': requestId(), 'name': name},
      );
      tagIds.add(tag['id']);
    }
    await observer.json(
      'PATCH',
      '/api/v1/video-tags',
      body: {
        'request_id': requestId(),
        'video_ids': [first, second],
        'tag_ids': tagIds.take(2).toList(),
        'mode': 'add',
      },
    );
    await repo.refresh();
    await t.pumpWidget(
      ShikaApp(repository: repo, preferences: preferences),
    );
    await ui.ready();
    await ui.folder(['端到端短视频', '自然', '花卉']);
    await ui.nav('library');
    await ui.tap(find.byTooltip('筛选视频'));
    for (final name in ['整理范围', '花卉']) {
      await ui.tagChip(name);
    }
    await ui.select('全部方向', '竖版');
    await ui.select('全部时长', '10 秒以内');
    await ui.select('全部类型', 'MP4');
    await ui.text('应用筛选');
    await ui.until(() => repo.playbackTotal == 2, 'two matching candidates');
    await ui.tap(find.byKey(Key('tile-$first')));
    await ui.ready();
    await ui.tap(find.byTooltip('播放模式'));
    await ui.text('顺序播放');
    await ui.ready();
    expect(repo.current!.id, first);
    await menu('进入快速整理');
    expect(find.byKey(const Key('quick-delete')), findsOneWidget);
    await ui.text('打标签');
    await ui.tagChip('快捷标记');
    await ui.tap(find.byKey(const Key('tag-assignment-save')));
    await ui.until(
      () => find.byType(TagEditor).evaluate().isEmpty,
      'quick tag saved',
    );
    expect(repo.current!.id, first);
    final tagged =
        (await observer.json(
              'GET',
              '/api/v1/videos',
              query: {'limit': '200'},
            ))['items']
            as List;
    expect(
      Set<String>.from(tagged.singleWhere((r) => r['id'] == first)['tag_ids']),
      tagIds.toSet(),
    );
    expect(await files(), beforeFiles);
    await ui.ready();
    await fixture('/__fixture/actions/lock-flower');
    try {
      await ui.tap(find.byKey(const Key('quick-delete')));
      expect(repo.current!.id, first);
      expect(find.byKey(const Key('operation-error')), findsOneWidget);
      expect(await trash(), isEmpty);
      expect(await files(), beforeFiles);
    } finally {
      await fixture('/__fixture/actions/unlock-flower');
    }
    await ui.tap(find.byKey(const Key('quick-delete')));
    await ui.until(
      () => repo.current?.id == second,
      'successful delete advances',
    );
    await ui.ready();
    final firstOperation = repo.snapshot.lastDelete!.id;
    expect((await trash()).single['video']['id'], first);
    await ui.text('撤销');
    await ui.until(
      () => repo.current?.id == first,
      'undo restores exact original',
    );
    await ui.ready();
    expect(await files(), beforeFiles);
    await ui.tap(find.byKey(const Key('quick-delete')));
    await ui.until(() => repo.current?.id == second, 'delete first again');
    await ui.tap(find.byKey(const Key('quick-delete')));
    await ui.until(() => repo.current == null, 'last deletion ends scope');
    expect(find.text('没有符合条件的可播放视频'), findsOneWidget);
    await expectLater(
      observer.json(
        'POST',
        '/api/v1/operations/$firstOperation/undo',
        body: {'request_id': requestId()},
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(await trash(), hasLength(2));
    await menu('返回日常浏览');
    expect(find.byKey(const Key('quick-delete')), findsNothing);
    await fixture('/__fixture/actions/conflict-first');
    final conflictFiles = await files();
    await openTrash();
    await checkTrash(first);
    await checkTrash(second);
    await ui.text('恢复');
    await ui.until(() => repo.trashCount == 1, 'partial restore reconciles');
    expect(find.byKey(const Key('operation-error')), findsOneWidget);
    expect((await trash()).single['video']['id'], first);
    final restored =
        (await observer.json(
              'GET',
              '/api/v1/videos',
              query: {'limit': '200'},
            ))['items']
            as List;
    expect(
      Set<String>.from(
        restored.singleWhere((r) => r['id'] == second)['tag_ids'],
      ),
      tagIds.take(2).toSet(),
    );
    expect(
      (await files())['/media/shorts/自然/花卉/片段01.mp4'],
      conflictFiles['/media/shorts/自然/花卉/片段01.mp4'],
    );
    await fixture('/__fixture/actions/clear-conflict-first');
    await checkTrash(first);
    await ui.text('恢复');
    await ui.until(
      () => repo.trashCount == 0,
      'restore after conflict resolved',
    );
    expect(await files(), beforeFiles);

    // Seed a real 25-item recycle bin to exercise paging without repeating 25 taps.
    final bulk = await observer.json(
      'POST',
      '/api/v1/videos/trash',
      body: {
        'request_id': requestId(),
        'video_ids': catalog
            .map((r) => r['id'])
            .where((v) => v != first && v != second)
            .toList(),
      },
    );
    Map<String, dynamic> task;
    do {
      task = await observer.json('GET', '/api/v1/tasks/${bulk['id']}');
      await t.pump(const Duration(milliseconds: 100));
    } while (!['completed', 'failed'].contains(task['status']));
    expect(task['result']['succeeded'], 25);
    await repo.refresh();
    await ui.nav('settings');
    await ui.text('回收站');
    final listed = await trash();
    expect(listed, hasLength(25));
    final a = listed.first['video']['id'] as String,
        b = listed.last['video']['id'] as String;
    await ui.until(
      () => find.byType(CheckboxListTile).evaluate().isNotEmpty,
      'first trash page',
    );
    await checkTrash(a);
    await t.scrollUntilVisible(
      find.text('加载更多'),
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await ui.text('加载更多');
    await checkTrash(b);
    final beforePermanent = await files();
    final chosenTrashIds = listed
        .where((row) => [a, b].contains(row['video']['id']))
        .map((row) => row['id'] as String)
        .toList();
    await ui.text('永久删除');
    await ui.text('取消');
    expect(await trash(), hasLength(25));
    await ui.text('永久删除');
    await ui.tap(find.widgetWithText(TextButton, '永久删除').last);
    await ui.until(
      () => repo.trashCount == 23,
      'permanent deletion reconciles',
    );
    expect(await trash(), hasLength(23));
    final afterPermanent = await files();
    expect(afterPermanent, hasLength(25));
    final expectedFiles = Map<String, dynamic>.from(beforePermanent)
      ..removeWhere(
        (path, _) => chosenTrashIds.any(
          (id) => path.contains('/.video-viewer-trash/$id/'),
        ),
      );
    expect(beforePermanent.length - expectedFiles.length, 2);
    expect(afterPermanent, expectedFiles);
    expect(
      (await trash()).any((row) => [a, b].contains(row['video']['id'])),
      isFalse,
    );
    expect(
      afterPermanent.values.every(
        (v) => beforeFiles.values.any((old) => old['sha256'] == v['sha256']),
      ),
      isTrue,
    );
    await fixture('/__fixture/checkpoint/library');
    await t.pump(const Duration(seconds: 2));

    await ui.nav('browse');
    await ui.ready();
    final pendingVideo = repo.current!.id;
    expect([first, second], contains(pendingVideo));
    await menu('进入快速整理');
    await fixture('/__fixture/actions/lose-file-response');
    await ui.tap(find.byKey(const Key('quick-delete')));
    expect(repo.fileOperationPending, isTrue);
    expect(repo.current!.id, pendingVideo);
    await ui.until(
      () => find.text('查询结果').evaluate().isNotEmpty,
      'unknown outcome remains visible',
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
    expect(await trash(), hasLength(24));
    debugPrint(
      'FILES_RESULT ${jsonEncode({'combined_scope': true, 'quick_tags_keep_paths': true, 'failure_keeps_current': true, 'precise_undo': true, 'last_item_empty': true, 'stale_undo_rejected': true, 'partial_restore_conflict_no_overwrite': true, 'restore_keeps_tags': true, 'trash_paging_25': true, 'permanent_cancel_and_confirm': true, 'file_hashes_verified': true, 'lost_response_pending_after_docker_restart': true})}',
    );
    await fixture('/__fixture/checkpoint/done');
    expect(t.takeException(), isNull);
  });
}
