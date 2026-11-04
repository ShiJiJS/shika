import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shika/library/backup_work_store.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/file_command_store.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/home.dart';
import 'package:shika/ui/preferences.dart';

import 'support/fixture.dart';
import 'support/server_ui.dart';

/// Actual Android disk bytes through the public file-selection boundary.
/// OS document-provider behavior remains covered separately from transport.
class DiskBackupFiles implements BackupFiles {
  DiskBackupFiles(this.file) : selected = file;
  final File file;
  File selected;
  bool cancelSave = false, cancelOpen = false;
  String? presented;
  @override
  Future<bool> save(String text) async {
    presented = text;
    if (cancelSave) return false;
    await file.writeAsString(text, flush: true);
    return true;
  }

  @override
  Future<String?> open() async =>
      cancelOpen ? null : utf8.decode(await selected.readAsBytes());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'I6 real backup file, rollback, process recovery and fresh mapped instance',
    (t) async {
      final folder = Directory(
        '${(await getApplicationSupportDirectory()).path}/server-backup-e2e',
      );
      await folder.create(recursive: true);
      final disk = DiskBackupFiles(File('${folder.path}/export.json'));
      final sidecar = File('${folder.path}/expected.json');
      final store = SecureCredentialStore(
        key: 'video_viewer.e2e.backups.connection.v1',
      );
      final fileCommands = SecureFileCommandStore(
        key: 'video_viewer.e2e.backups.files.v1',
      );
      final work = SecureBackupWorkStore(
        key: 'video_viewer.e2e.backups.work.v1',
      );
      final repo = ServerLibraryRepository(
        store,
        port: 8761,
        fileCommands: fileCommands,
        backupWork: work,
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
      Future<Map<String, dynamic>> files() async {
        final list =
            (await fixture('/__fixture/files', method: 'GET'))['items'] as List;
        return {
          for (final row in list)
            row['path'] as String: {
              'size': row['size'],
              'sha256': row['sha256'],
            },
        };
      }

      Future<List<dynamic>> tags() async =>
          (await observer!.json('GET', '/api/v1/tags'))['items'] as List;
      Future<void> backupPage() async {
        await ui.nav('settings');
        await ui.text('备份与恢复');
      }

      Future<void> chooseValid() async {
        disk.selected = disk.file;
        await ui.text('选择备份文件');
        await ui.until(
          () => find.byKey(const Key('restore-confirm')).evaluate().isNotEmpty,
          'validated mapping form',
        );
      }

      Future<void> confirmRestore() async {
        await ui.tap(find.byKey(const Key('restore-confirm')));
        await ui.tap(find.byKey(const Key('restore-submit')));
      }

      Future<void> waitHealth(bool available) async {
        var reached = false;
        for (var i = 0; i < 160 && !reached; i++) {
          var up = true;
          try {
            await fixture('/health', method: 'GET');
          } on IOException {
            up = false;
          }
          reached = up == available;
          if (!reached) await t.pump(const Duration(milliseconds: 150));
        }
        expect(reached, isTrue);
      }

      Future<void> assertRestored(
        Map<String, dynamic> expected, {
        required bool mapped,
      }) async {
        await ui.until(
          () => repo.libraryPreparation.value.ready,
          'restored directories finish preparation',
        );
        expect((await tags()).map((r) => r['name']).toSet(), {'原标签', '补充标签'});
        final round = await observer!.json('GET', '/api/v1/playback');
        expect(round['id'], expected['round_id']);
        expect(round['position'], expected['position']);
        expect(round['current']['id'], expected['current_id']);
        final trash =
            (await observer!.json('GET', '/api/v1/trash'))['items'] as List;
        expect(trash, hasLength(1));
        expect(trash.single['video']['id'], expected['first']);
        expect(
          Set<String>.from(trash.single['video']['tag_ids']),
          Set<String>.from(expected['tag_ids']),
        );
        expect(repo.fileOperationPending, isFalse);
        expect(repo.snapshot.lastDelete, isNull);
        expect(repo.backupRestorePending, isFalse);
        final receipt = jsonDecode((await fileCommands.read())!) as Map;
        expect(receipt.containsKey('pending'), isFalse);
        expect(receipt.containsKey('lastDelete'), isFalse);
        expect(
          repo.snapshot.roots.singleWhere((r) => r.id == 'shorts').path,
          mapped ? '/media/shorts/重新映射' : '/media/shorts',
        );
        expect(await files(), expected['files']);
      }

      if (const bool.fromEnvironment('E2E_RESUME')) {
        final expected = Map<String, dynamic>.from(
          jsonDecode(await sidecar.readAsString()) as Map,
        );
        final saved = (await store.read())!;
        observer = ServerApi(Uri.parse(fixtureBase), token: saved.token);
        await t.pumpWidget(
          ShikaApp(
            repository: repo,
            preferences: preferences,
            backupFiles: disk,
            initializeRepository: true,
          ),
        );
        await ui.until(
          () => repo.snapshot.connected,
          'encrypted session restores',
        );
        if (const bool.fromEnvironment('E2E_FRESH_RESUME')) {
          await ui.ready();
          await assertRestored(expected, mapped: true);
          expect(saved.serverId, expected['fresh_server_id']);
          expect(
            sha256.convert(await disk.file.readAsBytes()).toString(),
            expected['backup_sha256'],
          );
          expect(repo.snapshot.query.folder, startsWith('/media/shorts/重新映射/'));
          debugPrint(
            'BACKUP_FINAL_REOPEN_RESULT {"fresh_session":true,"mapped_roots":true,"same_round_and_position":true,"trash_and_tags":true,"no_old_commands":true,"actual_file_preserved":true}',
          );
          await ui.nav('settings');
          await ui.text('媒体目录');
          await ui.idle();
          await fixture('/__fixture/checkpoint/recovered');
          await t.pump(const Duration(seconds: 2));
          return;
        }
        await ui.until(
          () => find.byKey(const Key('backup-query')).evaluate().isNotEmpty,
          'durable pending restore',
        );
        await ui.tap(find.byKey(const Key('backup-query')));
        await ui.until(
          () => !repo.backupRestorePending,
          'query completed restore',
        );
        await assertRestored(expected, mapped: false);
        final trace =
            (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
        expect(
          trace.where(
            (r) =>
                r['method'] == 'POST' &&
                [
                  '/api/v1/backup-restores',
                  '/api/v1/videos/trash',
                ].contains(r['path']),
          ),
          isEmpty,
        );
        final restored = await observer.json(
          'GET',
          '/api/v1/tasks/${expected['restore_id']}',
        );
        expect(restored['result']['historical_operations_replayed'], 0);
        final snapshot = await observer.request(
          'GET',
          '/api/v1/backups/${restored['result']['pre_snapshot_id']}/download',
          maximumBytes: 32 * 1024 * 1024,
        );
        final prior = jsonDecode(utf8.decode(snapshot.bytes)) as Map;
        expect(
          (prior['payload']['tables']['tags'] as List).any(
            (r) => r['name'] == '恢复前新增',
          ),
          isTrue,
        );
        await backupPage();
        disk.cancelSave = true;
        await ui.text('导出备份');
        disk.cancelSave = false;
        expect(
          sha256.convert(await disk.file.readAsBytes()).toString(),
          expected['backup_sha256'],
        );
        expect(find.text('已导出管理数据备份'), findsNothing);
        final current = jsonDecode(disk.presented!) as Map;
        expect(
          (current['payload']['tables']['file_operations'] as List).every(
            (r) => r['historical'] == true,
          ),
          isTrue,
        );
        final relocated = await fixture(
          '/__fixture/actions/relocate-shorts-root',
        );
        expect(relocated['mapped_path'], '/media/shorts/重新映射');
        final movedFiles = <String, dynamic>{
          for (final entry in (expected['files'] as Map).entries)
            (entry.key as String).startsWith('/media/shorts/')
                    ? (entry.key as String).replaceFirst(
                        '/media/shorts/',
                        '/media/shorts/重新映射/',
                      )
                    : entry.key as String:
                entry.value,
        };
        expected['files'] = movedFiles;
        expect(await files(), movedFiles);
        await fixture('/__fixture/checkpoint/fresh-instance');
        await waitHealth(false);
        await waitHealth(true);
        await ui.nav('settings');
        await ui.text('服务连接');
        await t.enterText(find.byType(TextField).at(2), fixturePassword);
        await ui.text('连接');
        final fresh = (await store.read())!;
        expect(fresh.serverId == expected['old_server_id'], isFalse);
        observer.close();
        observer = ServerApi(Uri.parse(fixtureBase), token: fresh.token);
        expect(await tags(), isEmpty);
        await backupPage();
        await chooseValid();
        await t.enterText(
          find.byKey(const Key('mapping-shorts')),
          '/media/shorts/重新映射',
        );
        await confirmRestore();
        await ui.until(
          () => find.byKey(const Key('restore-submit')).evaluate().isEmpty,
          'fresh mapped restore',
        );
        expected['fresh_server_id'] = fresh.serverId;
        await assertRestored(expected, mapped: true);
        await sidecar.writeAsString(jsonEncode(expected), flush: true);
        debugPrint(
          'BACKUP_FRESH_RESULT {"read_only_recovery":true,"pre_restore_snapshot":true,"cancel_save_preserves_file":true,"new_server_id":true,"explicit_mapping":true,"tags_round_trash_restored":true,"no_media_moved_by_restore":true}',
        );
        await fixture('/__fixture/checkpoint/fresh-done');
        await t.pump(const Duration(seconds: 2));
        return;
      }

      await store.clear();
      await work.write('{}');
      await fileCommands.write('{}');
      await repo.connect('10.0.2.2', 8761, fixturePassword);
      final saved = (await store.read())!;
      observer = ServerApi(Uri.parse(fixtureBase), token: saved.token);
      final initial =
          (await observer.json(
                'GET',
                '/api/v1/videos',
                query: {'limit': '200'},
              ))['items']
              as List;
      String id(int n) =>
          initial.singleWhere(
                (r) => (r['path'] as String).endsWith(
                  '片段${n.toString().padLeft(2, '0')}.mp4',
                ),
              )['id']
              as String;
      final tagIds = <String>[];
      for (final name in ['原标签', '补充标签']) {
        tagIds.add(
          (await observer.json(
            'POST',
            '/api/v1/tags',
            body: {'request_id': requestId(), 'name': name},
          ))['id'],
        );
      }
      await observer.json(
        'PATCH',
        '/api/v1/video-tags',
        body: {
          'request_id': requestId(),
          'video_ids': [for (var n = 1; n <= 5; n++) id(n)],
          'tag_ids': [tagIds.first],
          'mode': 'add',
        },
      );
      await observer.json(
        'PATCH',
        '/api/v1/video-tags',
        body: {
          'request_id': requestId(),
          'video_ids': [id(1), id(2)],
          'tag_ids': [tagIds.last],
          'mode': 'add',
        },
      );
      await repo.refresh();
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          backupFiles: disk,
        ),
      );
      await ui.ready();
      await ui.folder(['端到端短视频', '自然', '花卉']);
      await ui.nav('library');
      await ui.tap(find.byTooltip('筛选视频'));
      await ui.tagChip('原标签');
      await ui.text('应用筛选');
      // The later assertion deliberately moves to position 1. A random
      // anchored item can be last, whose adjacent window need not contain 1.
      await repo.setScope(repo.snapshot.query, order: PlayOrder.sequential);
      await ui.search('片段01', 1);
      await ui.tap(find.byKey(Key('tile-${id(1)}')));
      await ui.ready();
      await ui.tap(find.byTooltip('更多'));
      await ui.text('进入快速整理');
      await fixture('/__fixture/actions/lose-file-response');
      await ui.tap(find.byKey(const Key('quick-delete')));
      expect(repo.fileOperationPending, isTrue);
      var round = await observer.json('GET', '/api/v1/playback');
      final next = (round['window'] as List).singleWhere(
        (r) => r['position'] == 1,
      )['video']['id'];
      round = await observer.json(
        'PATCH',
        '/api/v1/rounds/${round['id']}/position',
        body: {'expected_revision': round['revision'], 'video_id': next},
      );
      expect(round['position'], 1);
      final expected = <String, dynamic>{
        'round_id': round['id'],
        'position': round['position'],
        'current_id': round['current']['id'],
        'tag_ids': tagIds,
        'first': id(1),
        'files': await files(),
        'old_server_id': saved.serverId,
      };
      await backupPage();
      await ui.text('导出备份');
      expect(await disk.file.exists(), isTrue);
      final raw = await disk.file.readAsString();
      final document = jsonDecode(raw) as Map;
      expect(document['format'], 'video-viewer-management');
      expect(raw.contains(fixturePassword), isFalse);
      expect(raw.contains(saved.token), isFalse);
      expect(raw.contains('passphrase_hash'), isFalse);
      expected['backup_sha256'] = sha256
          .convert(await disk.file.readAsBytes())
          .toString();
      expect(
        document['payload']['settings']['active_round'],
        expected['round_id'],
      );
      await ui.nav('tags');
      await ui.text('新建标签');
      await t.enterText(find.byKey(const Key('tag-name')), '恢复前新增');
      await ui.text('保存');
      await ui.tap(find.byTooltip('重命名标签 原标签'));
      await t.enterText(find.byKey(const Key('tag-name')), '后来改名');
      await ui.text('保存');
      expect(await tags(), hasLength(3));
      await backupPage();
      disk.cancelOpen = true;
      await ui.text('选择备份文件');
      disk.cancelOpen = false;
      expect(find.byKey(const Key('restore-confirm')), findsNothing);
      expect(await files(), expected['files']);
      final bad = File('${folder.path}/bad.json');
      disk.selected = bad;
      for (final variant in ['json', 'version', 'checksum']) {
        final damaged = jsonDecode(raw) as Map;
        if (variant == 'version') damaged['version'] = 99;
        if (variant == 'checksum') {
          damaged['payload']['tables']['tags'][0]['name'] = '损坏';
        }
        await bad.writeAsString(
          variant == 'json' ? '{bad' : jsonEncode(damaged),
          flush: true,
        );
        await ui.text('选择备份文件');
        expect(find.byKey(const Key('operation-error')), findsOneWidget);
        expect(find.byKey(const Key('restore-confirm')), findsNothing);
        expect(await tags(), hasLength(3));
      }
      await chooseValid();
      expect(find.textContaining('视频 27 · 标签 2 · 回收站 1'), findsOneWidget);
      await ui.tap(find.byKey(const Key('restore-submit')));
      expect(find.text('请确认替换现有管理数据'), findsWidgets);
      await fixture('/__fixture/checkpoint/preview');
      await t.pump(const Duration(seconds: 2));
      await ui.tap(find.byKey(const Key('restore-cancel')));
      expect(await tags(), hasLength(3));
      expect(await files(), expected['files']);
      await chooseValid();
      await fixture('/__fixture/actions/fail-next-restore');
      await confirmRestore();
      expect(find.byKey(const Key('restore-submit')), findsOneWidget);
      expect(repo.backupRestorePending, isFalse);
      expect(await tags(), hasLength(3));
      expect(await files(), expected['files']);
      await ui.tap(find.byKey(const Key('restore-cancel')));
      await chooseValid();
      await fixture('/__fixture/actions/slow-next-restore');
      await ui.tap(find.byKey(const Key('restore-confirm')));
      await t.tap(find.byKey(const Key('restore-submit')));
      await t.pump(const Duration(milliseconds: 100));
      await ui.until(
        () => (repo.backupStatus.value ?? '').contains('已保存恢复前快照'),
        'observable maintenance phase',
      );
      await binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('restore-submit')), findsOneWidget);
      await fixture('/__fixture/checkpoint/outage');
      await waitHealth(false);
      await waitHealth(true);
      await ui.idle();
      await ui.until(
        () => find.widgetWithText(FilledButton, '查询恢复结果').evaluate().isNotEmpty,
        'restore failure returns query action',
      );
      expect(repo.backupRestorePending, isTrue);
      await ui.tap(find.byKey(const Key('restore-cancel')));
      await ui.nav('tags');
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '新建标签')).onPressed,
        isNull,
      );
      await ui.nav('settings');
      await ui.text('备份与恢复');
      List<dynamic> successful = [];
      for (var attempt = 0; attempt < 100 && successful.isEmpty; attempt++) {
        final tasks =
            (await observer.json(
                  'GET',
                  '/api/v1/tasks',
                  query: {'limit': '100'},
                ))['items']
                as List;
        successful = tasks
            .where(
              (r) =>
                  r['kind'] == 'backup_restore' && r['status'] == 'completed',
            )
            .toList();
        if (successful.isEmpty) await t.pump(const Duration(milliseconds: 200));
      }
      expect(successful, hasLength(1));
      expected['restore_id'] = successful.single['id'];
      expect(successful.single['result']['historical_operations_replayed'], 0);
      expect(await files(), expected['files']);
      await sidecar.writeAsString(jsonEncode(expected), flush: true);
      debugPrint(
        'BACKUP_RESULT ${jsonEncode({'actual_android_file': true, 'no_credentials_in_package': true, 'cancel_import_and_confirmation': true, 'bad_json_version_checksum': true, 'rollback_keeps_original_data': true, 'maintenance_blocks_writes_and_back': true, 'docker_restart_during_restore': true, 'pending_receipt_saved': true, 'no_media_changes': true})}',
      );
      await fixture('/__fixture/checkpoint/done');
      expect(t.takeException(), isNull);
    },
  );
}
