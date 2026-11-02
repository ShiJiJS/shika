import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/home.dart' show BackupFiles;

import 'support/fixture.dart';

class TaskBackupFiles implements BackupFiles {
  final saved = <String>[];
  bool accept = false;
  @override
  Future<String?> open() async => null;
  @override
  Future<bool> save(String value) async {
    saved.add(value);
    return accept;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF7 task center queries original work, paginates, preserves history and downloads original backup',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      final firstVideo = await repo.loadVideos(limit: 1);
      expect(firstVideo.total, greaterThan(0));
      await repo.deleteVideos({
        firstVideo.items.single.id,
      }, requestId: 'native-tasks-video-history');
      final document = await repo.exportBackupFile();
      final before = await repo.inspectBackupFile(document);
      await repo.restoreBackup(document, {
        for (final r in before.snapshot.roots) r.id: r.path,
      });
      final historical =
          (await repo.api.json(
                'GET',
                '/api/v1/maintenance-tasks',
                query: {'family': 'video', 'state': 'historical'},
              ))['items']
              as List;
      expect(historical.length, 1);
      final historyId = historical.single['id'] as String;
      final backupRows =
          (await repo.api.json(
                'GET',
                '/api/v1/maintenance-tasks',
                query: {'family': 'backup'},
              ))['items']
              as List;
      final exportId =
          backupRows.firstWhere((v) => v['kind'] == 'backup_export')['id']
              as String;
      final seed = await fixture('/__fixture/actions/workspace-packs');
      await repo.saveRoot(
        MediaRoot('', '操作任务图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final all = await repo.loadPacks(PackQuery(), limit: 100);
      expect(all.total, 27);
      final originals = (await fixture(
        '/__fixture/actions/pack-trash-hashes',
      ))['hashes'];
      final commands = repo.createPackFiles();
      for (var i = 0; i < 26; i++) {
        final command = PackFileCommand.trash('native-tasks-$i', [
          all.items[i].id,
        ]);
        final value = await commands.resolve(command, submit: true);
        expect(value!.result!.succeeded, 1);
        await commands.acknowledge(command);
      }
      await fixture('/__fixture/actions/lose-file-response');
      await expectLater(
        commands.send(
          PackFileCommand.trash('native-tasks-unknown', [all.items.last.id]),
        ),
        throwsA(isA<LibraryFailure>()),
      );
      expect((await commands.pending()).length, 1);
      final picker = TaskBackupFiles();
      await t.pumpWidget(VideoViewerApp(repository: repo, backupFiles: picker));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint(
              t
                  .widgetList<Text>(find.byType(Text))
                  .map((v) => v.data)
                  .join(' | '),
            );
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 60));
        }
        await t.pump(const Duration(milliseconds: 150));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        if (target.evaluate().isEmpty) {
          await t.scrollUntilVisible(
            target,
            350,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 60,
          );
        }
        await until(() => target.evaluate().isNotEmpty, 'target exists');
        await t.ensureVisible(target);
        await t.pump(const Duration(milliseconds: 160));
        await Scrollable.ensureVisible(t.element(target), alignment: .5);
        await t.pump(const Duration(milliseconds: 160));
        await until(
          () =>
              target.hitTestable().evaluate().isNotEmpty &&
              ModalRoute.of(t.element(target))?.animation?.status ==
                  AnimationStatus.completed,
          'stable target',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 180));
      }

      Future<void> shot(String state) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled',
        );
        await fixture('/__fixture/checkpoint/tasks-$state');
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }

      Future<void> family(String label) async {
        await tap(find.byKey(const Key('task-family')));
        await tap(find.text(label).last);
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'family page',
        );
      }

      await tap(find.byKey(const Key('nav-settings')));
      await fixture('/__fixture/actions/reset-task-trace');
      await tap(find.text('操作任务'));
      await until(
        () => find
            .byKey(const Key('task-receipt-pack:native-tasks-unknown'))
            .evaluate()
            .isNotEmpty,
        'unknown original receipt',
      );
      await shot('pending');
      await tap(
        find.byKey(const Key('task-receipt-pack:native-tasks-unknown')),
      );
      await until(
        () => find
            .byKey(const Key('maintenance-detail-state'))
            .evaluate()
            .isNotEmpty,
        'original task detail',
      );
      final detailState = find.byKey(const Key('maintenance-detail-state'));
      await until(
        () =>
            ModalRoute.of(t.element(detailState))?.animation?.status ==
                AnimationStatus.completed &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'detail route and reads settled',
      );
      expect(t.widget<Text>(detailState).data, '已完成');
      expect(await commands.pending(), isEmpty);
      await tap(find.text('全部'));
      await until(
        () => find.text(all.items.last.name).evaluate().isNotEmpty,
        'real operation member',
      );
      await shot('detail');
      await tap(find.byTooltip('查询原结果'));
      await tap(find.byTooltip('返回操作任务'));
      await family('图包');
      await shot('list');
      await tap(find.byKey(const Key('tasks-next')));
      await until(
        () => find.text('2 / 2').evaluate().isNotEmpty,
        'server task tail',
      );
      await shot('paged');
      await tap(find.byKey(const Key('task-filter-historical')));
      await family('视频');
      await tap(find.byKey(Key('maintenance-task-$historyId')));
      expect(find.textContaining('不重新执行原删除或恢复'), findsOneWidget);
      expect(find.text('重试原任务'), findsNothing);
      await shot('historical');
      await tap(find.byTooltip('返回操作任务'));
      await tap(find.byKey(const Key('task-filter-all')));
      await family('备份');
      await tap(find.byKey(Key('maintenance-task-$exportId')));
      await until(
        () =>
            find.byKey(const Key('task-download-backup')).evaluate().isNotEmpty,
        'original artifact',
      );
      await tap(find.byKey(const Key('task-download-backup')));
      await until(
        () => picker.saved.length == 1,
        'cancel original download save',
      );
      picker.accept = true;
      await tap(find.byKey(const Key('task-download-backup')));
      await until(() => picker.saved.length == 2, 'save original download');
      expect(picker.saved, [document, document]);
      await shot('backup-saved');
      expect(
        (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes'],
        originals,
      );
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(trace.where((r) => r['method'] == 'POST'), isEmpty);
      expect(
        trace
            .where(
              (r) =>
                  r['path'] ==
                  '/api/v1/pack-file-requests/native-tasks-unknown',
            )
            .length,
        1,
      );
      expect(
        trace
            .where((r) => r['path'] == '/api/v1/backups/$exportId/download')
            .length,
        2,
      );
      expect(
        trace.any(
          (r) =>
              r['path'] == '/api/v1/maintenance-tasks' &&
              r['query']['offset'] == '24' &&
              r['query']['family'] == 'pack',
        ),
        isTrue,
      );
    },
  );
}
