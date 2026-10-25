import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/features/packs/pack_trash_session.dart';

import 'support/restore_plan_fixture.dart';

class FailingPlanStore extends MemoryFileCommandStore {
  bool fail = true;
  @override
  Future<void> write(String value) async {
    if (fail) throw const LibraryFailure('写入失败');
    await super.write(value);
  }
}

void main() {
  test('persist all 1027 targets before POST; current server owns subsequent work and GET settles only that plan', () async {
    final f = RestoreServerFixture();
    await f.start();
    addTearDown(f.close);
    final api = f.repo.createPackRestorePlans();
    final ids = List.generate(1027, (i) => 'trash-$i');
    final value = await api.send(RestorePlanCommand.restore('all', ids));
    expect(value!.total, 1027);
    expect(value.settled, isFalse);
    expect(f.server.writes.where((v) => v.path.contains('restore')).length, 1);
    expect(
      (f.server.writes.last.body['trash_ids'] as List).toSet(),
      ids.toSet(),
    );
    expect((await api.pending()).single.command.ids.length, 1027);
    expect(f.repo.maintenancePendingCount, 1);
    final book = jsonDecode(f.packs.value!);
    expect(book['version'], 1);
    expect(
      book['restore_plans_v1'][f.scope]['restore:all']['task_id'],
      value.id,
    );
    final writes = f.server.writes.length;
    await expectLater(
      f.repo.createPackFiles().send(
        PackFileCommand.restore('overlap', ['trash-1']),
      ),
      throwsA(isA<LibraryFailure>()),
    );
    expect(f.server.writes.length, writes);
    expect(await f.repo.packFileJournal.pending(f.scope), isEmpty);
    await api.send(RestorePlanCommand.restore('independent', ['other']));
    f.complete(value.id);
    expect((await api.task(value.id)).succeeded, 1027);
    expect((await api.pending()).single.command.requestId, 'independent');
    expect(
      f.server.writes
          .where((v) => v.path == '/api/v1/pack-restore-plans')
          .length,
      2,
    );
  });
  test('lost accepted response reopens via original GET; explicitly sending same intent never posts twice', () async {
    final f = RestoreServerFixture();
    await f.start();
    addTearDown(f.close);
    f.losePlan = true;
    final command = RestorePlanCommand.restore('lost', ['a', 'b']);
    await expectLater(
      f.repo.createPackRestorePlans().send(command),
      throwsA(isA<LibraryFailure>()),
    );
    final catalog = f.repo.createMaintenanceTasks();
    final pending = await catalog.pending();
    expect(pending.single.family, 'pack');
    expect(pending.single.taskId, isNull);
    final result = await catalog.reconcile(pending.single);
    expect(result!.kind, 'pack_restore_plan');
    final gateway = f.repo.createPackRestorePlans();
    expect((await gateway.send(command))!.id, result.id);
    expect(f.server.writes.length, 1);
    f.complete(result.id);
    expect((await gateway.receipt(command))!.settled, isTrue);
    expect(await gateway.pending(), isEmpty);
    expect(f.requests.where((s) => s.startsWith('POST')).length, 1);
    catalog.dispose();
  });
  test('unknown 404 and malformed receipt retain exact intent and never fall through to POST', () async {
    final f = RestoreServerFixture();
    await f.start();
    addTearDown(f.close);
    f.missBefore = true;
    final command = RestorePlanCommand.restore('not-accepted', ['a']);
    final api = f.repo.createPackRestorePlans();
    await expectLater(api.send(command), throwsA(isA<LibraryFailure>()));
    expect(await api.send(command), isNull);
    expect(await api.receipt(command), isNull);
    expect((await api.pending()).single.command.ids, ['a']);
    expect(f.server.writes.length, 1);
    f.planBook['wrong'] = planJson('wrong', 'wrong-request', 1);
    f.originals['not-accepted'] = 'wrong';
    await expectLater(api.receipt(command), throwsA(isA<LibraryFailure>()));
    expect((await api.pending()).single.taskId, isNull);
    expect(f.server.writes.length, 1);
  });
  test('stop is durably separate; lost reply is queried by original stop ID and cannot stop another plan', () async {
    final f = RestoreServerFixture();
    await f.start();
    addTearDown(f.close);
    final api = f.repo.createPackRestorePlans();
    final parent = (await api.send(RestorePlanCommand.restore('root', ['a'])))!;
    f.loseStop = true;
    final command = RestorePlanCommand.stop('stop-lost', parent.id);
    await expectLater(api.send(command), throwsA(isA<LibraryFailure>()));
    expect((await api.pending()).length, 2);
    await expectLater(
      api.send(RestorePlanCommand.stop('another-key', parent.id)),
      throwsA(isA<LibraryFailure>()),
    );
    final requests = f.server.writes.length;
    expect((await api.receipt(command))!.stopRequested, isTrue);
    expect(f.server.writes.length, requests);
    expect((await api.pending()).single.command.kind, 'restore');
    expect(f.requests.last, 'GET /api/v1/pack-restore-stop-requests/stop-lost');
    f.complete(parent.id, stopped: 1);
    final stopped = await api.task(parent.id);
    expect(stopped.succeeded, 0);
    expect(stopped.stopped, 1);
    expect(await api.pending(), isEmpty);
  });
  test('write failure and invalid persisted namespace block POST and do not erase old video/pack receipts', () async {
    final store = FailingPlanStore();
    final journal = PackFileJournal(store);
    final calls = <String>[];
    final api = PackRestorePlans(
      journal: journal,
      scope: 's',
      isCurrent: () => true,
      call: (method, path, {body}) async {
        calls.add(method);
        return planJson('p', body!['request_id'], 1);
      },
    );
    final command = RestorePlanCommand.restore('first', ['a']);
    await expectLater(api.send(command), throwsA(isA<LibraryFailure>()));
    expect(calls, isEmpty);
    store.fail = false;
    await api.send(command);
    expect(calls, ['POST']);
    final corrupt = MemoryFileCommandStore()
      ..value = jsonEncode({
        'version': 1,
        'scopes': {},
        'restore_plans_v1': {
          's': {
            'restore:x': {'bad': 'keep'},
          },
        },
      });
    final broken = PackRestorePlans(
      journal: PackFileJournal(corrupt),
      scope: 's',
      isCurrent: () => true,
      call: (m, p, {body}) async {
        fail('must not submit');
      },
    );
    final before = corrupt.value;
    await expectLater(
      broken.send(RestorePlanCommand.restore('new', ['b'])),
      throwsA(isA<LibraryFailure>()),
    );
    expect(corrupt.value, before);
  });
  test('file receipt and plan admission use one serialized resource guard in either order', () async {
    final store = MemoryFileCommandStore(),
        journal = PackFileJournal(MemoryFileCommandStore());
    await journal.remember('s', PackFileCommand.restore('old', ['a']));
    final plans = PackRestorePlans(
      journal: journal,
      scope: 's',
      isCurrent: () => true,
      call: (m, p, {body}) async {
        fail('must not submit');
      },
    );
    await expectLater(
      plans.send(RestorePlanCommand.restore('new', ['a'])),
      throwsA(isA<LibraryFailure>()),
    );
    expect((await journal.pending('s')).single.requestId, 'old');
    expect(await plans.pending(), isEmpty);
    store.value = jsonEncode({
      'version': 1,
      'scopes': {
        's': {
          'old': {
            'command': PackFileCommand.restore('old', ['z']).toJson(),
          },
        },
      },
      'future-kept': {'keep': true},
    });
    final next = PackRestorePlans(
      journal: PackFileJournal(store),
      scope: 's',
      isCurrent: () => true,
      call: (m, p, {body}) async => planJson('p', 'n', 1),
    );
    await next.send(RestorePlanCommand.restore('n', ['x']));
    expect(jsonDecode(store.value!)['future-kept'], {'keep': true});
    expect((await next.journal.pending('s')).single.requestId, 'old');
  });
  test('late response after connection replacement preserves scoped journal and cannot publish old result', () async {
    final f = RestoreServerFixture();
    await f.start();
    addTearDown(f.close);
    f.postStarted = Completer();
    f.postRelease = Completer();
    final api = f.repo.createPackRestorePlans(),
        command = RestorePlanCommand.restore('late', ['a']);
    final work = api.send(command);
    final assertion = expectLater(work, throwsA(anything));
    await f.postStarted!.future;
    await f.repo.connect('http://127.0.0.1', f.server.server.port, 'test');
    f.postRelease!.complete();
    await assertion;
    f.complete(f.originals['late']!);
    final fresh = f.repo.createPackRestorePlans();
    expect(await fresh.pending(), isEmpty);
    final history = f.repo.createMaintenanceTasks();
    final receipt = (await history.pending()).single;
    expect(receipt.historical, isTrue);
    expect(receipt.requestId, 'late');
    expect((await history.reconcile(receipt))!.historical, isTrue);
    expect(
      (await f.repo.packFileJournal.restorePending(f.scope))
          .single
          .command
          .requestId,
      'late',
    );
    history.dispose();
    expect(
      f.server.writes
          .where((v) => v.path.endsWith('/pack-restore-plans'))
          .length,
      1,
    );
  });
  test('historical completed restore and accepted stop keep both original receipts', () async {
    final f = RestoreServerFixture();
    await f.start();
    addTearDown(f.close);
    final gateway = f.repo.createPackRestorePlans();
    final restore = RestorePlanCommand.restore('historical-restore', [
      'a',
      'b',
    ]);
    final plan = (await gateway.send(restore))!;
    final stop = RestorePlanCommand.stop('historical-stop', plan.id);
    f.loseStop = true;
    await expectLater(gateway.send(stop), throwsA(isA<LibraryFailure>()));
    f.complete(plan.id, stopped: 1);
    await f.repo.connect('http://127.0.0.1', f.server.server.port, 'test');
    final writes = f.server.writes.length;
    final catalog = f.repo.createMaintenanceTasks();
    final records = await catalog.pending();
    expect(records, hasLength(2));
    for (final row in records) {
      expect(row.historical, isTrue);
      expect((await catalog.reconcile(row))!.historical, isTrue);
    }
    final readOnly = PackRestorePlans(
      journal: f.repo.packFileJournal,
      scope: f.scope,
      readOnly: true,
      isCurrent: () => true,
      call: (method, path, {body}) async =>
          throw StateError('No new request permitted'),
    );
    await expectLater(readOnly.send(restore), throwsA(isA<LibraryFailure>()));
    expect(
      (await f.repo.packFileJournal.restorePending(f.scope))
          .map((r) => r.command.requestId)
          .toSet(),
      {'historical-restore', 'historical-stop'},
    );
    expect(await f.repo.createPackRestorePlans().pending(), isEmpty);
    expect(f.server.writes.length, writes);
    catalog.dispose();
  });
  test('new server session submits one durable whole selection; disposal does not own server continuation', () async {
    final repo = RestoreLibrary(count: 1027);
    addTearDown(repo.dispose);
    final session = PackTrashSession(repo);
    await session.load();
    await session.selectAll();
    session.toggle('trash-0');
    await session.restoreSelected();
    expect(repo.planBodies.length, 1);
    expect((repo.planBodies.single['trash_ids'] as List).length, 1026);
    expect(repo.posts, isEmpty);
    expect(session.restoring, isFalse);
    expect(session.selection.ids, isEmpty);
    expect(session.lastPlan!.remaining, 1026);
    expect(repo.records.length, 1027);
    final command = session.pendingPlans.single.command;
    session.dispose();
    final next = PackTrashSession(repo);
    addTearDown(next.dispose);
    await next.load();
    expect(next.pendingPlans.single.command.signature, command.signature);
    expect((await next.plans!.receipt(command))!.remaining, 1026);
    expect(repo.planBodies.length, 1);
  });
  test('leaving while acceptance is in flight keeps all original targets, errors do not clear selection', () async {
    final repo = RestoreLibrary(count: 1001)..losePlan = true;
    addTearDown(repo.dispose);
    final session = PackTrashSession(repo);
    addTearDown(session.dispose);
    await session.load();
    await session.selectAll();
    await session.restoreSelected();
    expect(session.selection.ids.length, 1001);
    expect(session.pendingPlans.single.command.ids.length, 1001);
    expect(session.error, isNotEmpty);
    expect(repo.planBodies.length, 1);
    await session.restoreSelected();
    expect(repo.planBodies.length, 1);
    expect(session.selection.ids.length, 1001);
  });
  test('reject inconsistent counters and stopped members are distinct from failures', () {
    final stopped = planJson(
      'p',
      'r',
      3,
      succeeded: 1,
      stopped: 2,
      stopRequested: true,
    );
    expect(RestorePlan.fromJson(stopped).settled, isTrue);
    final summary = MaintenanceTask(planSummary(stopped));
    expect(summary.progressLabel, contains('已停止 2'));
    for (final key in [
      'total',
      'processed',
      'succeeded',
      'failed',
      'stopped',
      'remaining',
      'batches',
    ]) {
      final raw = jsonDecode(jsonEncode(stopped)) as Map<String, dynamic>;
      (raw['result'] as Map)[key] = -1;
      expect(() => RestorePlan.fromJson(raw), throwsA(isA<LibraryFailure>()));
    }
  });
}
