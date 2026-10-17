import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';
import 'package:video_viewer/ui/sheets.dart';

import 'support/fixture.dart';
import 'support/server_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('I3 real tags, batches, AND scope, retry and persistent links', (
    t,
  ) async {
    final store = SecureCredentialStore(key: 'video_viewer.e2e.tags.v1');
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
    if (const bool.fromEnvironment('E2E_RESUME')) {
      final saved = await store.read();
      expect(saved, isNotNull);
      observer = ServerApi(Uri.parse(fixtureBase), token: saved!.token);
      final before = await observer.json('GET', '/api/v1/playback');
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: true,
        ),
      );
      await ui.until(
        () => repo.snapshot.connected,
        'encrypted session reopens',
      );
      await ui.ready();
      expect(repo.snapshot.query.tags, hasLength(1));
      expect(repo.tagName(repo.snapshot.query.tags.single), '自然改名');
      expect(repo.playbackTotal, 2);
      expect(
        (await observer.json('GET', '/api/v1/playback'))['id'],
        before['id'],
      );
      await ui.nav('tags');
      expect(find.text('自然改名'), findsOneWidget);
      expect(find.text('2 个视频'), findsOneWidget);
      expect(find.text('待保留'), findsOneWidget);
      expect(find.text('花卉'), findsNothing);
      debugPrint(
        'TAGS_REOPEN_RESULT {"links":true,"scope":true,"renamed_id":true}',
      );
      return;
    }
    await store.clear();
    await repo.connect('10.0.2.2', 8761, fixturePassword);
    observer = ServerApi(
      Uri.parse(fixtureBase),
      token: (await store.read())!.token,
    );
    final beforeFiles = await fixture('/__fixture/files', method: 'GET');
    await t.pumpWidget(
      VideoViewerApp(repository: repo, preferences: preferences),
    );
    await ui.ready();

    Future<void> create(String name) async {
      await ui.text('新建标签');
      await t.enterText(find.byKey(const Key('tag-name')), name);
      await ui.text('保存');
      await ui.until(
        () => repo.snapshot.tags.any((id) => repo.tagName(id) == name),
        'tag saved',
      );
    }

    Future<Set<String>> links(String id) async {
      final videos =
          (await observer!.json(
                'GET',
                '/api/v1/videos',
                query: {'limit': '200'},
              ))['items']
              as List;
      return Set<String>.from(
        videos.singleWhere((v) => v['id'] == id)['tag_ids'],
      );
    }

    Future<void> editCurrent(List<String> names) async {
      await ui.tap(find.byTooltip('更多'));
      await ui.text('打标签');
      for (final name in names) {
        await ui.tagChip(name);
      }
      await ui.text('完成');
      await ui.until(
        () => find.byType(TagEditor).evaluate().isEmpty,
        'tags committed',
      );
      await ui.ready();
    }

    Future<void> filter({bool empty = false}) async {
      await ui.tap(find.byTooltip('筛选视频'));
      for (final name in ['自然', '花卉']) {
        final id = repo.snapshot.tags.singleWhere(
          (id) => repo.tagName(id) == name,
        );
        if (!repo.snapshot.query.tags.contains(id)) await ui.tagChip(name);
      }
      if (repo.snapshot.query.orientation.isEmpty) {
        await ui.select('全部方向', '竖版');
      }
      if (repo.snapshot.query.duration.isEmpty) {
        await ui.select('全部时长', '10 秒以内');
      }
      final nextType = empty ? 'MOV' : 'MP4';
      if (repo.snapshot.query.type != nextType) {
        await ui.select(
          repo.snapshot.query.type.isEmpty ? '全部类型' : repo.snapshot.query.type,
          nextType,
        );
      }
      await ui.text('应用筛选');
      await ui.until(
        () => find.text('${empty ? 0 : 1} 个视频').evaluate().isNotEmpty,
        'AND and attribute results',
      );
      expect(repo.snapshot.query.folder, '/media/shorts/自然/花卉');
    }

    await ui.nav('tags');
    for (final name in ['自然', '花卉', '待保留']) {
      await create(name);
    }
    final nature = repo.snapshot.tags.singleWhere(
      (id) => repo.tagName(id) == '自然',
    );
    final flower = repo.snapshot.tags.singleWhere(
      (id) => repo.tagName(id) == '花卉',
    );
    final keep = repo.snapshot.tags.singleWhere(
      (id) => repo.tagName(id) == '待保留',
    );
    await ui.text('新建标签');
    await t.enterText(find.byKey(const Key('tag-name')), '自然');
    await ui.text('保存');
    await ui.until(
      () => find.textContaining('已有同名标签').evaluate().isNotEmpty,
      'duplicate tag feedback',
    );
    expect(
      t.widget<TextField>(find.byKey(const Key('tag-name'))).controller!.text,
      '自然',
    );
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 300));

    await ui.nav('library');
    await ui.folder(['端到端短视频', '自然', '花卉']);
    await ui.search('片段01', 1);
    final all =
        (await observer.json(
              'GET',
              '/api/v1/videos',
              query: {'limit': '200'},
            ))['items']
            as List;
    final first =
        all.singleWhere((v) => v['name'] == '片段01.mp4')['id'] as String;
    final second =
        all.singleWhere((v) => v['name'] == '片段02.mp4')['id'] as String;
    await ui.tap(find.byKey(Key('tile-$first')));
    await ui.ready();
    await editCurrent(['自然', '花卉', '待保留']);
    expect(await links(first), {nature, flower, keep});
    await ui.tap(find.byKey(Key('filter-tag-$nature')));
    await ui.ready();
    await ui.tap(find.byKey(Key('filter-tag-$flower')));
    await ui.ready();
    expect(repo.snapshot.query.tags, {nature, flower});
    expect(repo.playbackTotal, 1);
    await ui.nav('library');
    await filter(empty: true);
    expect(repo.current, isNull);
    expect(repo.playbackTotal, 0);
    await filter();
    expect(repo.playbackTotal, 1);
    await ui.clearScope();
    await ui.folder(['端到端短视频', '自然', '花卉']);
    await ui.search('片段0', 9);

    Future<void> batch({
      required bool remove,
      bool loseResponse = false,
    }) async {
      await ui.text('多选');
      await ui.tap(find.byKey(Key('tile-$first')));
      await ui.tap(find.byKey(Key('tile-$second')));
      await ui.text('打标签');
      if (remove) await ui.text('移除标签');
      await ui.tagChip('花卉');
      if (!remove) await ui.tagChip('自然');
      if (loseResponse) await fixture('/__fixture/actions/lose-tag-response');
      await ui.text('完成');
      if (loseResponse) {
        await ui.until(
          () => find.textContaining('连接已中断').evaluate().isNotEmpty,
          'accepted write lost response',
        );
        expect(await links(second), {nature, flower});
        await ui.text('完成');
      }
      await ui.until(
        () => find.byType(TagEditor).evaluate().isEmpty,
        'batch completes',
      );
      await ui.until(
        () => find.text('多选').evaluate().isNotEmpty,
        'batch selection closes after saving',
      );
    }

    await batch(remove: false, loseResponse: true);
    expect(await links(first), {nature, flower, keep});
    expect(await links(second), {nature, flower});
    await batch(remove: true);
    expect(await links(first), {nature, keep});
    expect(await links(second), {nature});
    await ui.search('片段01', 1);
    await ui.tap(find.byKey(Key('tile-$first')));
    await ui.ready();
    await editCurrent(['花卉']);
    await ui.nav('library');
    await filter();
    await ui.nav('tags');
    await ui.tap(find.byTooltip('重命名标签 自然'));
    await t.enterText(find.byKey(const Key('tag-name')), '自然改名');
    await ui.text('保存');
    await ui.until(() => repo.tagName(nature) == '自然改名', 'rename keeps tag ID');
    expect(repo.snapshot.query.tags, {nature, flower});
    await ui.tap(find.byTooltip('删除标签 花卉'));
    await ui.text('删除标签');
    await ui.until(
      () => !repo.snapshot.tags.contains(flower),
      'delete tag association',
    );
    expect(repo.snapshot.query.tags, {nature});
    expect(repo.playbackTotal, 2);
    expect(await links(first), {nature, keep});
    expect(await links(second), {nature});
    final trace =
        (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
    final retries = trace.where((r) => r['command_hash'] != null).toList();
    final lost = retries.indexWhere((r) => r['status'] == 503);
    expect(lost, greaterThanOrEqualTo(0));
    expect(retries[lost]['command_hash'], retries[lost + 1]['command_hash']);
    expect(await fixture('/__fixture/files', method: 'GET'), beforeFiles);
    await fixture('/__fixture/checkpoint/library');
    await t.pump(const Duration(seconds: 2));
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
    expect(await links(first), {nature, keep});
    expect(await links(second), {nature});
    expect(await fixture('/__fixture/files', method: 'GET'), beforeFiles);
    debugPrint(
      'TAGS_RESULT ${jsonEncode({'single': true, 'batch_add_remove': true, 'unrelated_tag_preserved': true, 'AND_and_attributes': true, 'empty_scope': true, 'retry_same_command': true, 'rename_keeps_id': true, 'delete_updates_scope': true, 'files_unchanged': true, 'docker_restart_links': true})}',
    );
    await fixture('/__fixture/checkpoint/done');
    expect(t.takeException(), isNull);
  });
}
