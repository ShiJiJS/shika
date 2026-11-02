import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/backup_work_store.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const resume = bool.fromEnvironment('E2E_RESUME');
  const strongStop = bool.fromEnvironment('E2E_STRONG_STOP');
  testWidgets(
    'LF7 original secure journals survive an actual management restore',
    (t) async {
      final credentials = SecureCredentialStore(
        key: 'video_viewer.connection.authority.v1',
      );
      final packs = SecureFileCommandStore(
        key: 'video_viewer.pack_commands.authority.v1',
      );
      final videos = SecureFileCommandStore(
        key: 'video_viewer.file_commands.authority.v1',
      );
      final backup = SecureBackupWorkStore(
        key: 'video_viewer.backup_work.authority.v1',
      );
      final metadata = SecureFileCommandStore(
        key: 'video_viewer.fixture.authority.v1',
      );
      ServerLibraryRepository make() => ServerLibraryRepository(
        credentials,
        packCommands: packs,
        fileCommands: videos,
        backupWork: backup,
        port: 8761,
      );
      var repo = make();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
      });
      Map<String, dynamic> original;
      if (!resume) {
        await credentials.clear();
        await packs.write(jsonEncode({'version': 1, 'scopes': {}}));
        await videos.write(jsonEncode({'version': 2, 'scopes': {}}));
        await backup.write(jsonEncode({'version': 2, 'scopes': {}}));
        await fixture('/__fixture/actions/reset-login-limit');
        await fixture('/__fixture/actions/reset-task-trace');
        final prepared = await fixture('/__fixture/authority/prepare');
        await repo.connect('http://10.0.2.2', 8761, fixturePassword);
        final saved = (await credentials.read())!;
        final scope = jsonEncode([
          saved.endpoint.toString(),
          saved.serverId,
          saved.managementEpoch,
        ]);
        expect(saved.managementEpoch, prepared['old_epoch']);
        await repo.packFileJournal.remember(
          scope,
          PackFileCommand.restore('authority-pack-old', ['trash-file-old']),
        );
        await repo.packFileJournal.rememberRestore(
          scope,
          RestorePlanCommand.restore('authority-plan-old', ['trash-plan-old']),
        );
        await repo.packFileJournal.rememberMissing(
          scope,
          'authority-missing-old',
        );
        final selection = await PackPurgeSelections(repo.createPackFiles())
            .save([for (var i = 0; i < 27; i++) 'trash-unsubmitted-$i']);
        await videos.write(
          jsonEncode({
            'version': 2,
            'scopes': {
              scope: {
                'scope': scope,
                'pending': {
                  'key': 'authority-video-old',
                  'path': '/api/v1/videos/trash',
                  'body': {
                    'video_ids': ['video-old'],
                  },
                },
              },
            },
          }),
        );
        await backup.write(
          jsonEncode({
            'version': 2,
            'scopes': {
              scope: {
                'scope': scope,
                'export': {'key': 'authority-export-old'},
              },
            },
          }),
        );
        original = {
          'scope': scope,
          'epoch': saved.managementEpoch,
          'selection': selection.id,
        };
        await metadata.write(jsonEncode(original));
        repo.dispose();
        repo = make();
      } else {
        original = Map<String, dynamic>.from(
          jsonDecode((await metadata.read())!) as Map,
        );
      }
      await repo.initialize();
      expect(repo.snapshot.connected, isTrue);
      await t.pumpWidget(VideoViewerApp(repository: repo));

      Future<void> until(bool Function() done, String why) async {
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (!done()) {
          if (DateTime.now().isAfter(end)) {
            debugPrint(
              t
                  .widgetList<Text>(find.byType(Text))
                  .map((v) => v.data)
                  .join(' | '),
            );
            fail('Timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 150));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        for (final direction in [1, -1]) {
          for (
            var i = 0;
            target.hitTestable().evaluate().isEmpty && i < 40;
            i++
          ) {
            final scroll = find.byType(Scrollable).hitTestable();
            if (scroll.evaluate().isEmpty) break;
            await t.drag(scroll.last, Offset(0, -180.0 * direction));
            await t.pump(const Duration(milliseconds: 100));
          }
          if (target.hitTestable().evaluate().isNotEmpty) break;
        }
        await t.ensureVisible(target.last);
        await t.pump(const Duration(milliseconds: 150));
        expect(target.last.hitTestable(), findsOneWidget);
        await t.tap(target.last);
        await t.pump(const Duration(milliseconds: 200));
      }

      Future<void> shot(String phase) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled',
        );
        await fixture('/__fixture/checkpoint/$phase');
        await t.pump(const Duration(seconds: 2));
      }

      await until(() => find.text('设置').evaluate().isNotEmpty, 'workspace');
      await tap(find.text('设置'));
      await tap(find.text('操作任务'));
      await until(
        () => find
            .text(resume ? '本机 6 项历史记录' : '本机 6 项待处理记录')
            .evaluate()
            .isNotEmpty,
        'all six durable original intents',
      );
      if (!resume) {
        final oldTasks = repo.createMaintenanceTasks(),
            oldReader = repo.createPackReader();
        final oldApi = repo.api;
        expect((await oldTasks.pending()).every((v) => !v.historical), isTrue);
        await shot('authority-before');
        if (strongStop) {
          debugPrint('VV_E2E_AUTHORITY_FORCE_STOP');
          while (true) {
            await t.pump(const Duration(milliseconds: 250));
          }
        }
        await fixture('/__fixture/authority/restore');
        await expectLater(
          oldApi.json('GET', '/api/v1/info'),
          throwsA(isA<ApiFailure>()),
        );
        await repo.managementSynchronization;
        expect(oldTasks.isCurrent, isFalse);
        expect(oldReader.isCurrent, isFalse);
        await until(
          () => find.text('设置').evaluate().isNotEmpty,
          'recovered workspace leaves the connection form',
        );
        expect(find.text('个人口令'), findsNothing);
        await tap(find.text('设置'));
        await tap(find.text('操作任务'));
      } else {
        debugPrint('VV_E2E_AUTHORITY_REOPENED');
      }
      final completed = await fixture(
        '/__fixture/authority/stats',
        method: 'GET',
      );
      final currentEpoch = (completed['completed'] as Map)['new_epoch'];
      expect(repo.api.managementEpoch, currentEpoch);
      expect(currentEpoch, isNot(original['epoch']));
      expect((await credentials.read())!.managementEpoch, currentEpoch);
      expect(
        ((await repo.api.json('GET', '/api/v1/tags'))['items'] as List).any(
          (v) => v['name'] == '恢复目标',
        ),
        isTrue,
      );
      final catalog = repo.createMaintenanceTasks();
      final pending = await catalog.pending();
      expect(pending, hasLength(6));
      expect(
        pending.every(
          (v) => v.historical && v.journalScope == original['scope'],
        ),
        isTrue,
      );
      final before = [
        await videos.read(),
        await backup.read(),
        await packs.read(),
      ];
      for (final receipt in pending.where(
        (v) => v.source != MaintenanceReceiptSource.purgeSelection,
      )) {
        expect(await catalog.reconcile(receipt), isNull);
      }
      expect([
        await videos.read(),
        await backup.read(),
        await packs.read(),
      ], before);
      await tap(find.byKey(const Key('task-filter-historical')));
      await until(
        () => find.text('本机 6 项历史记录').evaluate().isNotEmpty,
        'historical filter',
      );
      await shot('authority-history');
      await tap(find.text('图包删除选择 · 27 个未提交'));
      await until(
        () => find
            .byKey(const Key('purge-selection-remaining'))
            .evaluate()
            .isNotEmpty,
        'saved selection',
      );
      expect(find.textContaining('历史选择：管理数据已恢复'), findsOneWidget);
      expect(find.byKey(const Key('purge-selection-next')), findsNothing);
      expect(find.text('27 个未提交'), findsOneWidget);
      await shot('authority-selection');
      await t.pageBack();
      await t.pump(const Duration(milliseconds: 200));
      // A fresh current-generation export must not replace the old export key.
      expect(await repo.exportBackupFile(), isNotEmpty);
      final book = jsonDecode((await backup.read())!) as Map;
      final scopes = book['scopes'] as Map;
      expect(scopes.length, 2);
      expect(
        (scopes[original['scope']] as Map)['export']['key'],
        'authority-export-old',
      );
      expect(
        (await catalog.pending()).where((v) => v.historical),
        hasLength(6),
      );
      await tap(find.byKey(const Key('tasks-refresh')));
      await shot('authority-current');
      catalog.dispose();
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      final app = trace.where((v) => v['fixture_actor'] == null).toList();
      expect(app.where((v) => v['path'] == '/api/v1/auth/login'), hasLength(1));
      expect(
        app
            .where(
              (v) =>
                  ['POST', 'PATCH', 'PUT', 'DELETE'].contains(v['method']) &&
                  v['path'] != '/api/v1/auth/login',
            )
            .every((v) => v['management_epoch'] == currentEpoch),
        isTrue,
      );
      expect(
        app.where(
          (v) => v['path'] == '/api/v1/backups' && v['method'] == 'POST',
        ),
        hasLength(1),
      );
      expect(app.where((v) => v['path'] == '/api/v1/backup-restores'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
}
