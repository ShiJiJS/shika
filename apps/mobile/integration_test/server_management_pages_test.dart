import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_viewer/ui/preferences.dart';

import '../test/support/reveal_action.dart';

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
  String? selected;
  @override
  Future<String?> open() async => selected;
  @override
  Future<bool> save(String value) async {
    saved.add(value);
    return accept;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF8 backup management, cancelled preview, paged tasks and original results',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
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
      final picker = TaskBackupFiles()..selected = document;
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          backupFiles: picker,
          preferences: preferences,
        ),
      );
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
        await revealAction(t, target);
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 180));
        expect(t.takeException(), isNull);
      }

      Future<void> shot(String state) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled',
        );
        await t.pumpAndSettle();
        final m = MediaQueryData.fromView(t.view);
        if (state == 'restore-keyboard') {
          expect(m.viewInsets.bottom, greaterThan(0));
        }
        debugPrint(
          'MANAGEMENT_METRICS:${jsonEncode({
            'state': 'management-$state',
            'window': [m.size.width, m.size.height],
            'dpr': m.devicePixelRatio,
            'text13': m.textScaler.scale(13),
            'viewPadding': [m.viewPadding.left, m.viewPadding.top, m.viewPadding.right, m.viewPadding.bottom],
            'keyboard': m.viewInsets.bottom,
            'dark': preferences.dark,
          })}',
        );
        await fixture('/__fixture/checkpoint/management-$state');
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

      await fixture('/__fixture/actions/reset-task-trace');
      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('备份与恢复'));
      await shot('backup');
      await tap(find.text('导出备份'));
      await until(() => picker.saved.length == 1, 'cancelled backup save');
      expect(find.text('已导出管理数据备份'), findsNothing);
      await shot('backup-cancel');
      picker.accept = true;
      await tap(find.text('导出备份'));
      await until(() => picker.saved.length == 2, 'saved backup');
      await shot('backup-saved');
      await tap(find.text('选择备份文件'));
      await until(
        () => find.byKey(const Key('restore-confirm')).evaluate().isNotEmpty,
        'backup preview',
      );
      await shot('restore-preview');
      final field = find.byWidgetPredicate((w) => w is TextFormField).first;
      await tap(field);
      await until(
        () => MediaQueryData.fromView(t.view).viewInsets.bottom > 0,
        'actual restore keyboard',
      );
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await shot('restore-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await until(
        () => MediaQueryData.fromView(t.view).viewInsets.bottom == 0,
        'hide restore keyboard',
      );
      await tap(find.byKey(const Key('restore-cancel')));
      final cancelled =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        cancelled.where(
          (e) =>
              e['method'] == 'POST' &&
              (e['path'] as String).contains('/restore'),
        ),
        isEmpty,
      );
      picker.selected = 'not a backup';
      await tap(find.text('选择备份文件'));
      await until(
        () => find.byKey(const Key('operation-error')).evaluate().isNotEmpty,
        'invalid backup error',
      );
      await shot('backup-error');
      await tap(find.byTooltip('关闭错误提示'));
      picker.saved.clear();
      picker.accept = false;
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
      await tap(find.byTooltip('返回设置'));
      await fixture('/__fixture/actions/reset-task-trace');
      await tap(find.text('操作任务'));
      await until(
        () => find
            .byKey(const Key('task-receipt-pack:native-tasks-unknown'))
            .evaluate()
            .isNotEmpty,
        'unknown original receipt',
      );
      await revealAction(
        t,
        find.byKey(const Key('task-receipt-pack:native-tasks-unknown')),
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
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'operation member read settled',
      );
      await revealAction(t, find.text(all.items.last.name));
      await shot('detail');
      await tap(find.byTooltip('查询原结果'));
      await tap(find.byTooltip('返回操作任务'));
      await family('图包');
      await shot('list');
      await tap(find.byKey(const Key('tasks-next')));
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'server task tail read settled',
      );
      await revealAction(t, find.text('2 / 2'));
      await shot('paged');
      await preferences.setDark(true);
      await shot('dark');
      await preferences.setDark(false);
      await t.pumpAndSettle();
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
      await shot('task-backup-saved');
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
      debugPrint(
        'MANAGEMENT_VERIFIED:27 pack tasks, one original receipt GET, two original backup downloads, zero task-phase POST, 81 source hashes preserved',
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
