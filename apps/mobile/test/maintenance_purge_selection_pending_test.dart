import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_repository.dart';

import 'server_maintenance_tasks_test.dart' show TaskServerFixture;
import 'support/maintenance_fixture.dart' show taskSummary;
import 'support/pack_purge_fixture.dart' show purgeHash, purgeTaskJson;

void main() {
  late TaskServerFixture f;
  setUp(() async {
    f = TaskServerFixture();
    await f.start();
  });
  tearDown(() => f.close());

  Future<PackFileCommand> claim(
    PackPurgeSelection selection,
    String request, {
    int maximum = 1000,
    bool accepted = true,
  }) async {
    final ids = selection.remaining.take(maximum).toList();
    final command = PackFileCommand.permanent(
      request,
      planId: 'plan-$request',
      digest: purgeHash,
      trashIds: ids,
      imageCount: ids.length * 3,
      selectionId: selection.id,
    );
    await f.repo.packFileJournal.remember(f.scope, command);
    if (accepted) {
      await f.repo.packFileJournal.accepted(f.scope, command, 'op-$request');
      f.receipts[request] = 'op-$request';
      f.full['op-$request'] = purgeTaskJson(ids, id: 'op-$request');
      f.summaries['op-$request'] = taskSummary(
        'op-$request',
        kind: 'pack_permanent',
      );
    }
    return command;
  }

  Future<void> acknowledge(PackFileCommand command) async {
    final files = f.repo.createPackFiles();
    final task = await files.receipt(command);
    expect(task, isNotNull);
    await files.acknowledgeTask(task!);
  }

  test(
    'seven finished choices do not hide an unknown original request',
    () async {
      final selections = PackPurgeSelections(f.repo.createPackFiles());
      for (var index = 0; index < 7; index++) {
        final saved = await selections.save(['trash-$index']);
        await acknowledge(await claim(saved, 'finished-$index'));
      }
      final unknown = await selections.save(['trash-unknown']);
      await claim(unknown, 'unknown', accepted: false);
      final before = f.packs.value;
      final catalog = f.repo.createMaintenanceTasks();
      addTearDown(catalog.dispose);
      final pending = await catalog.pending();
      expect(pending.single.requestId, 'unknown');
      expect(pending.single.source, MaintenanceReceiptSource.pack);
      expect(f.repo.maintenancePendingCount, 1);
      expect(await catalog.reconcile(pending.single), isNull);
      expect((await catalog.pending()).single.requestId, 'unknown');
      expect(f.packs.value, before);
      expect(await selections.list(), hasLength(8));
      expect((await catalog.page()).items, hasLength(7));
      expect((await catalog.task('op-finished-0')).kind, 'pack_permanent');
      expect(f.server.writes, isEmpty);
    },
  );

  test(
    '1027 choice keeps 27 for fresh review, then only original batch receipts',
    () async {
      final selections = PackPurgeSelections(f.repo.createPackFiles());
      final original = await selections.save(
        List.generate(1027, (i) => 'trash-$i'),
      );
      await acknowledge(await claim(original, 'first'));
      final catalog = f.repo.createMaintenanceTasks();
      addTearDown(catalog.dispose);
      expect((await catalog.pending()).single.title, '图包删除选择 · 27 个未提交');
      expect(f.repo.maintenancePendingCount, 1);
      final rest = await selections.read(original.id);
      final second = await claim(rest, 'second', accepted: false);
      expect((await catalog.pending()).single.requestId, 'second');
      expect(f.repo.maintenancePendingCount, 1);
      await f.repo.packFileJournal.rejected(f.scope, second);
      expect((await selections.read(original.id)).remaining, rest.remaining);
      expect((await catalog.pending()).single.purgeSelectionId, original.id);
      expect(f.repo.maintenancePendingCount, 1);
      expect(f.server.writes, isEmpty);
    },
  );

  test(
    'query failure, running and partial results retain the original operation',
    () async {
      final saved = await PackPurgeSelections(f.repo.createPackFiles())
          .save(['trash-0']);
      await claim(saved, 'partial');
      f.full['op-partial'] = purgeTaskJson(
        ['trash-0'],
        id: 'op-partial',
        attention: true,
      );
      f.summaries['op-partial'] = taskSummary(
        'op-partial',
        kind: 'pack_permanent',
        state: 'attention',
      );
      var fail = true;
      f.server.handle = (request, body) async {
        if (fail && request.uri.path.endsWith('/pack-file-requests/partial')) {
          return (
            status: 503,
            body: {
              'error': {'code': 'busy', 'message': '暂时无法查询'},
            },
          );
        }
        return f.handle(request, body);
      };
      final catalog = f.repo.createMaintenanceTasks();
      addTearDown(catalog.dispose);
      final receipt = (await catalog.pending()).single;
      expect(receipt.requestId, 'partial');
      await expectLater(
        catalog.reconcile(receipt),
        throwsA(isA<LibraryFailure>()),
      );
      expect((await catalog.pending()).single.requestId, 'partial');
      fail = false;
      expect(
        (await catalog.reconcile((await catalog.pending()).single))!
            .needsAttention,
        isTrue,
      );
      expect((await catalog.pending()).single.requestId, 'partial');
      expect(f.repo.maintenancePendingCount, 1);
      f.full['op-partial'] = {
        'id': 'op-partial',
        'kind': 'pack_permanent',
        'status': 'running',
        'result': null,
        'error': null,
      };
      f.summaries['op-partial'] = taskSummary(
        'op-partial',
        kind: 'pack_permanent',
        state: 'processing',
      );
      expect(
        (await catalog.reconcile((await catalog.pending()).single))!.state,
        'processing',
      );
      expect((await catalog.pending()).single.requestId, 'partial');
      expect(f.server.writes, isEmpty);
    },
  );

  test(
    'new client reads saved history without reviving finished pending choices',
    () async {
      final selections = PackPurgeSelections(f.repo.createPackFiles());
      final saved = await selections.save(['trash-done']);
      await acknowledge(await claim(saved, 'done'));
      final unknown = await selections.save(['trash-unknown']);
      await claim(unknown, 'unknown', accepted: false);
      f.repo.dispose();
      f.repo = ServerLibraryRepository(
        MemoryCredentialStore(),
        packCommands: f.packs,
        fileCommands: f.videos,
        backupWork: f.backup,
      );
      await f.repo.connect('http://127.0.0.1', f.server.server.port, 'test');
      final catalog = f.repo.createMaintenanceTasks();
      addTearDown(catalog.dispose);
      expect((await catalog.pending()).single.requestId, 'unknown');
      expect(f.repo.maintenancePendingCount, 1);
      expect(
        (await PackPurgeSelections(f.repo.createPackFiles()).read(saved.id))
            .batches
            .single
            .taskId,
        'op-done',
      );
      expect((await catalog.task('op-done')).kind, 'pack_permanent');
      expect(f.server.writes, isEmpty);
    },
  );
}
