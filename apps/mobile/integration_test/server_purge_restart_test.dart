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
        ? 'LF7 real secure purge resumes original 1000 and keeps 3 unsubmitted'
        : 'LF7 real secure purge is interrupted after immutable batch persistence',
    (t) async {
      final credentials = SecureCredentialStore(
        key: 'video_viewer.connection.purge-restart.v1',
      );
      final commands = SecureFileCommandStore(
        key: 'video_viewer.pack_commands.purge-restart.v1',
      );
      final videos = SecureFileCommandStore(
        key: 'video_viewer.file_commands.purge-restart.v1',
      );
      final metadata = SecureFileCommandStore(
        key: 'video_viewer.fixture.purge-restart.v1',
      );
      final repo = ServerLibraryRepository(
        credentials,
        packCommands: commands,
        fileCommands: videos,
        port: 8761,
      );
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
      });
      Map<String, dynamic> original;
      if (!resume) {
        await credentials.clear();
        await commands.write(jsonEncode({'version': 1, 'scopes': {}}));
        await videos.write('{}');
        await fixture('/__fixture/actions/reset-login-limit');
        final seed = await fixture('/__fixture/actions/purge-restart-packs');
        await repo.connect('http://10.0.2.2', 8761, fixturePassword);
        await repo.saveRoot(
          MediaRoot('', '批量删除图包', seed['path'], kind: MediaKind.pack),
        );
        // Large scans remain server jobs after the client's bounded wait.
        // Refresh again queries that SAME _scanTask, rather than reseeding or
        // bypassing the scanner to make the 1003-pack fixture cheaper.
        for (var attempt = 0; ; attempt++) {
          try {
            await repo.refresh();
            break;
          } on LibraryFailure catch (failure) {
            if (failure.message != '扫描仍在服务端进行，可稍后刷新查询进度' || attempt >= 2) {
              rethrow;
            }
          }
        }
        final setupTrace =
            (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
        expect(
          setupTrace
              .where(
                (e) => e['method'] == 'POST' && e['path'] == '/api/v1/scans',
              )
              .length,
          1,
        );
        final packIds = (await repo.selectPackIds(PackQuery())).toList()
          ..sort();
        expect(packIds.length, 1003);
        final files = repo.createPackFiles();
        for (var at = 0; at < packIds.length; at += 1000) {
          final command = PackFileCommand.trash(
            'purge-restart-seed-$at',
            packIds.skip(at).take(1000),
          );
          final result = await files.resolve(
            command,
            submit: true,
            timeout: const Duration(minutes: 2),
          );
          expect(result?.result?.failed, 0);
          expect(result?.settled, isTrue);
          await files.acknowledge(command);
        }
        final catalog = repo.createPackTrash();
        final ids = (await catalog.select('')).toList()..sort();
        catalog.dispose();
        expect(ids.length, 1003);
        final hashes =
            (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes']
                as Map;
        expect(hashes.length, 2006);
        original = {'ids': ids, 'hashes': hashes};
        await metadata.write(jsonEncode(original));
      } else {
        // No passphrase is supplied after the host terminates the live engine.
        await repo.initialize();
        expect(repo.snapshot.connected, isTrue);
        original = Map<String, dynamic>.from(
          jsonDecode((await metadata.read())!) as Map,
        );
        final pending = await repo.createPackFiles().pending();
        expect(pending.length, 1);
        expect(pending.single.kind, 'permanent');
        expect(pending.single.requestId, original['request_id']);
        expect(pending.single.targets.length, 1000);
        expect(
          await repo.packFileJournal.identity(
            repo.createPackFiles().scope,
            pending.single.requestId,
          ),
          isNull,
        );
        final draft = (await PackPurgeSelections(
          repo.createPackFiles(),
        ).list()).single;
        expect(draft.id, original['selection_id']);
        expect(draft.ids, original['ids']);
        expect(draft.remaining, original['remaining']);
        expect(draft.remaining.length, 3);
        debugPrint('VV_E2E_PURGE_REOPENED');
      }
      await t.pumpWidget(VideoViewerApp(repository: repo));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
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
          await t.pump(const Duration(milliseconds: 80));
        }
        await t.pump(const Duration(milliseconds: 250));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target, {double scroll = 300}) async {
        if (target.evaluate().isEmpty) {
          await until(
            () =>
                target.evaluate().isNotEmpty ||
                find.byType(LinearProgressIndicator).evaluate().isEmpty &&
                    find.byType(Scrollable).evaluate().isNotEmpty,
            'view ready before scrolling',
          );
          if (target.evaluate().isEmpty) {
            await t.scrollUntilVisible(
              target,
              scroll,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 60,
            );
          }
        }
        await until(() => target.evaluate().isNotEmpty, 'target $target');
        await t.ensureVisible(target);
        await t.pump(const Duration(milliseconds: 250));
        await until(
          () =>
              target.hitTestable().evaluate().isNotEmpty &&
              ModalRoute.of(t.element(target))?.animation?.status ==
                  AnimationStatus.completed,
          'stable target',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 250));
      }

      Future<void> shot(String phase) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled',
        );
        await fixture('/__fixture/checkpoint/bulk-$phase');
        await t.pump(const Duration(seconds: 1));
      }

      await tap(find.byKey(const Key('nav-settings')));
      if (!resume) {
        await tap(find.text('回收站'));
        await tap(find.byKey(const Key('trash-kind-pack')));
        await until(
          () => find.text('共 1003 个图包').evaluate().isNotEmpty,
          '1003 trash packs',
        );
        await tap(find.byKey(const Key('pack-trash-select-all')));
        await until(
          () => find.text('已选 1003').evaluate().isNotEmpty,
          'complete selection',
        );
        await shot('selected');
        await fixture('/__fixture/actions/reset-task-trace');
        await tap(find.byKey(const Key('pack-trash-permanent')));
        final confirmation = find.byKey(const Key('pack-purge-confirmation'));
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (confirmation.evaluate().isEmpty ||
            t.widget<CheckboxListTile>(confirmation).onChanged == null) {
          if (DateTime.now().isAfter(deadline)) {
            fail('1000-member exact preview did not finish');
          }
          final query = find.widgetWithText(TextButton, '查询原清单');
          if (query.evaluate().isNotEmpty &&
              t.widget<TextButton>(query).onPressed != null) {
            await tap(query);
          }
          await t.pump(const Duration(milliseconds: 200));
        }
        expect(find.text('1000 个图包 · 1000 张图片'), findsOneWidget);
        expect(t.widget<CheckboxListTile>(confirmation).value, isFalse);
        await shot('review');
        await fixture('/__fixture/actions/hold-purge-restart');
        await fixture('/__fixture/actions/lose-file-response');
        await tap(confirmation);
        await tap(find.byKey(const Key('pack-purge-submit')));
        await until(
          () => find
              .byKey(const Key('pack-operation-error'))
              .evaluate()
              .isNotEmpty,
          'unknown accepted purge',
        );
        final files = repo.createPackFiles(),
            pending = await repo.createPackFiles().pending();
        expect(pending.length, 1);
        expect(pending.single.targets.length, 1000);
        final draft = (await PackPurgeSelections(files).list()).single;
        expect(draft.ids, original['ids']);
        expect(draft.remaining.length, 3);
        original = {
          ...original,
          'request_id': pending.single.requestId,
          'selection_id': draft.id,
          'remaining': draft.remaining,
          'command': pending.single.toJson(),
        };
        await metadata.write(jsonEncode(original));
        final persisted = jsonDecode((await commands.read())!) as Map;
        expect(persisted['purge_selections_v1'], isNotEmpty);
        expect(persisted['scopes'], isNotEmpty);
        await shot('unknown');
        debugPrint('VV_E2E_PURGE_FORCE_STOP');
        // Only the host's live-process termination can end this phase.
        while (true) {
          await t.pump(const Duration(milliseconds: 200));
        }
      }
      await tap(find.text('操作任务'));
      await tap(find.byKey(Key('task-receipt-pack:${original['request_id']}')));
      await until(
        () => find.text('已确认删除 1000/1000 张').evaluate().isNotEmpty,
        'original 1000 completed',
      );
      expect(await repo.createPackFiles().pending(), isEmpty);
      await shot('receipt');
      await tap(find.text('全部'));
      await tap(find.byKey(const Key('task-items-next')));
      await shot('paged');
      await tap(find.byTooltip('返回操作任务'));
      await tap(
        find.byKey(
          Key('task-receipt-purge-selection:${original['selection_id']}'),
        ),
        scroll: -300,
      );
      await until(
        () => find.text('3 个未提交').evaluate().isNotEmpty,
        'remaining original choice',
      );
      await shot('selection');
      await tap(find.byKey(const Key('purge-selection-next')));
      await until(
        () => find.text('3 个图包 · 3 张图片').evaluate().isNotEmpty,
        'fresh remaining preview',
      );
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const Key('pack-purge-confirmation')),
            )
            .value,
        isFalse,
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('pack-purge-submit')))
            .onPressed,
        isNull,
      );
      await shot('next-review');
      await tap(find.text('取消').last);
      final catalog = repo.createPackTrash();
      expect(
        (await catalog.select('')).toList()..sort(),
        original['remaining'],
      );
      catalog.dispose();
      final hashes =
          (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes']
              as Map;
      expect(hashes.length, 1006);
      expect(
        hashes.keys.where((v) => (v as String).endsWith('notes.txt')).length,
        1003,
      );
      final initial = original['hashes'] as Map;
      for (final e in hashes.entries) {
        expect(e.value, initial[e.key]);
      }
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace
            .where(
              (e) =>
                  e['method'] == 'POST' &&
                  e['path'] == '/api/v1/pack-trash/permanent',
            )
            .length,
        1,
      );
      expect(
        trace
            .where(
              (e) =>
                  e['method'] == 'GET' &&
                  (e['path'] as String).endsWith(
                    '/pack-file-requests/${original['request_id']}',
                  ),
            )
            .length,
        1,
      );
      expect(
        trace
            .where(
              (e) =>
                  e['method'] == 'POST' &&
                  e['path'] == '/api/v1/pack-purge-plans',
            )
            .length,
        2,
      );
    },
  );
}
