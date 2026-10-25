import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const resume = bool.fromEnvironment('E2E_RESUME');
  testWidgets(
    resume
        ? 'LF7 secure restore reopens original request and explicitly stops later batches'
        : 'LF7 secure unknown restore is interrupted in a live Android process',
    (t) async {
      final store = SecureFileCommandStore(
        key: 'video_viewer.pack_commands.lf7-native.v1',
      );
      final credentials = SecureCredentialStore(
        key: 'video_viewer.connection.lf7-native.v1',
      );
      final repo = ServerLibraryRepository(
        credentials,
        packCommands: store,
        fileCommands: SecureFileCommandStore(
          key: 'video_viewer.file_commands.lf7-native.v1',
        ),
        port: 8761,
      );
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
      });
      if (!resume) {
        await credentials.clear();
        await store.write(jsonEncode({'version': 1, 'scopes': {}}));
        await SecureFileCommandStore(
          key: 'video_viewer.file_commands.lf7-native.v1',
        ).write('{}');
        await fixture('/__fixture/actions/reset-login-limit');
        final seed = await fixture('/__fixture/actions/workspace-packs');
        await repo.connect('http://10.0.2.2', 8761, fixturePassword);
        await repo.saveRoot(
          MediaRoot('', '整份恢复图包', seed['path'], kind: MediaKind.pack),
        );
        await repo.refresh();
        final all = await repo.loadPacks(PackQuery(), limit: 100);
        expect(all.total, 27);
        final tag = await repo.createPackTag('整份恢复保留');
        await repo.setPackTags(all.items.map((p) => p.id).toSet(), {tag.id});
        final files = repo.createPackFiles();
        final command = PackFileCommand.trash(
          'native-restore-seed',
          all.items.map((p) => p.id),
        );
        final result = await files.resolve(command, submit: true);
        expect(result!.result!.succeeded, 27);
        await files.acknowledge(command);
      } else {
        // No passphrase or in-memory credentials survive the host's force-stop.
        await repo.initialize();
        expect(repo.snapshot.connected, isTrue);
        final pending = await repo.createPackRestorePlans().pending();
        expect(pending.length, 1);
        expect(pending.single.command.ids.length, 27);
        expect(pending.single.taskId, isNull);
        debugPrint('VV_E2E_RESTORE_REOPENED');
      }
      await t.pumpWidget(VideoViewerApp(repository: repo));
      Future<void> until(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint(
              t
                  .widgetList<Text>(find.byType(Text))
                  .map((w) => w.data)
                  .join(' | '),
            );
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        await t.pump(const Duration(milliseconds: 180));
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
        await t.pump(const Duration(milliseconds: 180));
        await Scrollable.ensureVisible(t.element(target), alignment: .5);
        await t.pump(const Duration(milliseconds: 180));
        await until(
          () =>
              target.hitTestable().evaluate().isNotEmpty &&
              ModalRoute.of(t.element(target))?.animation?.status ==
                  AnimationStatus.completed,
          'stable tap',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 250));
      }

      Future<void> shot(String phase) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled',
        );
        await fixture('/__fixture/checkpoint/restore-$phase');
        await t.pump(const Duration(seconds: 1));
      }

      Future<void> trashPage() async {
        await tap(find.text('回收站'));
        await tap(find.byKey(const Key('trash-kind-pack')));
        await until(
          () => find.text('共 27 个图包').evaluate().isNotEmpty,
          '27 trash records',
        );
        await tap(find.byKey(const Key('pack-trash-select-all')));
        await until(
          () => find.text('已选 27').evaluate().isNotEmpty,
          'complete selection',
        );
      }

      await tap(find.byKey(const Key('nav-settings')));
      if (!resume) {
        await trashPage();
        await shot('selected');
        await fixture('/__fixture/actions/hold-restore-plan');
        await fixture('/__fixture/actions/lose-file-response');
        await fixture('/__fixture/actions/reset-task-trace');
        await tap(find.byKey(const Key('pack-trash-restore')));
        await tap(find.byKey(const Key('pack-restore-plan-confirm')));
        await until(
          () => find
              .byKey(const Key('pack-trash-plans-pending'))
              .evaluate()
              .isNotEmpty,
          'persisted unknown result',
        );
        final persisted = await repo.createPackRestorePlans().pending();
        expect(persisted.single.taskId, isNull);
        expect(persisted.single.command.ids.length, 27);
        expect(
          (jsonDecode((await store.read())!) as Map)['restore_plans_v1'],
          isNotEmpty,
        );
        await shot('unknown');
        debugPrint('VV_E2E_RESTORE_FORCE_STOP');
        // The host must terminate this live engine. Reaching tearDown would not
        // establish crash persistence, so the first phase intentionally cannot pass.
        while (true) {
          await t.pump(const Duration(milliseconds: 200));
        }
      }
      final original =
          (await repo.createPackRestorePlans().pending()).single.command;
      await tap(find.text('操作任务'));
      await tap(find.byKey(Key('task-receipt-restore-plan:${original.key}')));
      await until(
        () => find
            .byKey(const Key('maintenance-detail-state'))
            .evaluate()
            .isNotEmpty,
        'original plan detail',
      );
      await until(
        () => find.textContaining('完成 27').evaluate().isNotEmpty,
        '27 completed members',
      );
      expect(await repo.createPackRestorePlans().pending(), isEmpty);
      await shot('reopened');
      await tap(find.text('全部'));
      await tap(find.byKey(const Key('task-items-next')));
      await shot('paged');
      final first = await fixture('/__fixture/actions/restore-plan-stats');
      expect((first['batches'] as List).length, 14);
      expect(first['member_counts'], {'succeeded': 27});
      expect((first['packs'] as List).map((p) => p['generation']).toSet(), {3});
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(trace.where((e) => e['method'] == 'POST').length, 1);
      expect(
        trace.where((e) => e['method'] == 'POST').single['path'],
        '/api/v1/pack-restore-plans',
      );
      final all = await repo.loadPacks(PackQuery(), limit: 100);
      expect(all.total, 27);
      expect(all.items.every((p) => p.tags.isNotEmpty), isTrue);
      final hashes = (await fixture(
        '/__fixture/actions/pack-trash-hashes',
      ))['hashes'];
      final files = repo.createPackFiles();
      final trash = PackFileCommand.trash(
        'native-restore-stop-seed',
        all.items.map((p) => p.id),
      );
      expect((await files.resolve(trash, submit: true))!.result!.succeeded, 27);
      await files.acknowledge(trash);
      await tap(find.byTooltip('返回操作任务'));
      await tap(find.byTooltip('返回设置'));
      await trashPage();
      await fixture('/__fixture/actions/hold-restore-plan');
      await tap(find.byKey(const Key('pack-trash-restore')));
      await tap(find.byKey(const Key('pack-restore-plan-confirm')));
      await until(
        () => find
            .byKey(const Key('pack-trash-plan-result'))
            .evaluate()
            .isNotEmpty,
        'whole acceptance',
      );
      await tap(find.byKey(const Key('pack-trash-plan-result')));
      await until(
        () => find.byKey(const Key('restore-plan-stop')).evaluate().isNotEmpty,
        'stop control',
      );
      await fixture('/__fixture/actions/lose-file-response');
      await tap(find.byKey(const Key('restore-plan-stop')));
      await tap(find.byKey(const Key('restore-plan-stop-confirm')));
      await until(
        () => find.textContaining('停止结果待核对').evaluate().isNotEmpty,
        'unknown stop preserved',
      );
      await shot('stop-unknown');
      await tap(find.byTooltip('查询原结果'));
      await until(
        () => find.textContaining('停止请求已受理').evaluate().isNotEmpty,
        'original stop receipt',
      );
      await fixture('/__fixture/actions/release-restore-plan');
      Map<String, dynamic> stopped = {};
      for (var i = 0; i < 200; i++) {
        stopped = await fixture('/__fixture/actions/restore-plan-stats');
        if (stopped['plan']['status'] == 'completed') break;
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(stopped['member_counts'], {'succeeded': 2, 'stopped': 25});
      expect((stopped['batches'] as List).length, 1);
      await tap(find.byTooltip('查询原结果'));
      await until(
        () => find.textContaining('已停止 25').evaluate().isNotEmpty,
        'accurate stopped count',
      );
      await shot('stopped');
      expect(await repo.createPackRestorePlans().pending(), isEmpty);
      expect(
        (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes'],
        hashes,
      );
      final finalTrace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        finalTrace
            .where(
              (e) =>
                  e['method'] == 'POST' &&
                  (e['path'] as String).endsWith('/stop'),
            )
            .length,
        1,
      );
      expect(
        finalTrace
            .where(
              (e) =>
                  e['method'] == 'GET' &&
                  (e['path'] as String).contains(
                    '/pack-restore-stop-requests/',
                  ),
            )
            .length,
        1,
      );
    },
  );
}
