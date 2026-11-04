import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/file_command_store.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_api.dart';

import 'support/pack_purge_fixture.dart';

class FailingSelectionStore extends MemoryFileCommandStore {
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> write(String value) async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('disk unavailable');
    await super.write(value);
  }
}

List<String> selectionIds(int count) =>
    List.generate(count, (i) => 'trash-${i.toString().padLeft(5, '0')}');
PackFileCommand batchCommand(
  PackPurgeSelection selection,
  String request, {
  List<String>? ids,
}) => PackFileCommand.permanent(
  request,
  planId: 'plan-$request',
  digest: purgeHash,
  trashIds: ids ?? selection.remaining.take(1000),
  imageCount: (ids ?? selection.remaining.take(1000).toList()).length * 3,
  selectionId: selection.id,
);

void main() {
  late FailingSelectionStore store;
  late PackFiles files;
  late PackPurgeSelections selections;
  late List<String> calls;
  var current = true;
  late PackFileCall call;
  setUp(() {
    store = FailingSelectionStore();
    calls = [];
    current = true;
    call = (method, path, {body}) async {
      calls.add('$method $path');
      final pending = await PackFileJournal(store).pending('server');
      final command = pending.single;
      final draft = (await PackFileJournal(store).purgeSelections('server'))
          .single;
      // Both the full selection and the exact command must be on disk BEFORE POST.
      expect(draft.batches.single.command.signature, command.signature);
      return purgeTaskJson(command.targets, id: 'op-${command.requestId}');
    };
    files = PackFiles(
      journal: PackFileJournal(store),
      scope: 'server',
      isCurrent: () => current,
      call: (m, p, {body}) => call(m, p, body: body),
    );
    selections = PackPurgeSelections(files);
  });
  test('1027 snapshot and exact batch atomically persist; new journal only reads original IDs', () async {
    final draft = await selections.save(selectionIds(1027));
    expect(calls, isEmpty);
    final command = batchCommand(draft, 'first');
    final task = await files.send(command);
    await files.acknowledgeTask(task);
    expect(await files.pending(), isEmpty);
    final reopened = PackPurgeSelections(
      PackFiles(
        journal: PackFileJournal(store),
        scope: 'server',
        isCurrent: () => true,
        call: (_, _, {body}) async =>
            throw StateError('opening must not call server'),
      ),
    );
    final saved = await reopened.read(draft.id);
    expect(saved.ids, draft.ids);
    expect(saved.remaining, draft.ids.skip(1000));
    expect(saved.batches.single.taskId, 'op-first');
    expect(calls, ['POST /api/v1/pack-trash/permanent']);
    expect((await reopened.save(saved.remaining)).id, draft.id);
  });
  test('cancel preparation does not claim a batch; duplicate and overlapping choices stay visible', () async {
    final draft = await selections.save(selectionIds(1027));
    expect((await selections.save(selectionIds(1027).reversed)).id, draft.id);
    expect(await selections.list(), hasLength(1));
    await expectLater(
      selections.save(selectionIds(2)),
      throwsA(isA<LibraryFailure>()),
    );
    expect((await selections.read(draft.id)).remaining, draft.ids);
    expect(calls, isEmpty);
  });
  test(
    'failed persistence never posts or consumes unsubmitted choice',
    () async {
      store.fail = true;
      await expectLater(selections.save(selectionIds(1027)), throwsStateError);
      store.fail = false;
      final draft = await selections.save(selectionIds(1027));
      store.fail = true;
      await expectLater(
        files.send(batchCommand(draft, 'first')),
        throwsStateError,
      );
      store.fail = false;
      expect(
        (await PackFileJournal(store).purgeSelections('server'))
            .single
            .remaining,
        draft.ids,
      );
      expect(await files.pending(), isEmpty);
      expect(calls, isEmpty);
    },
  );
  test('unknown response retains exact 1000 plus 27 unsubmitted; reopen GET 404 never posts', () async {
    final draft = await selections.save(selectionIds(1027));
    final command = batchCommand(draft, 'unknown');
    call = (m, p, {body}) async {
      calls.add('$m $p');
      throw ApiFailure('lost', code: 'lost', status: m == 'POST' ? 503 : 404);
    };
    await expectLater(files.send(command), throwsA(isA<ApiFailure>()));
    final again = PackFiles(
      journal: PackFileJournal(store),
      scope: 'server',
      isCurrent: () => true,
      call: (m, p, {body}) => call(m, p, body: body),
    );
    expect(await again.receipt((await again.pending()).single), isNull);
    final saved = (await PackPurgeSelections(again).list()).single;
    expect(saved.remaining, draft.ids.skip(1000));
    expect(saved.batches.single.taskId, isNull);
    expect(calls, [
      'POST /api/v1/pack-trash/permanent',
      'GET /api/v1/pack-file-requests/unknown',
    ]);
    expect(await again.pending(), hasLength(1));
  });
  test('known rejection releases batch into unsubmitted selection; next review has new command', () async {
    final draft = await selections.save(selectionIds(1027));
    final old = batchCommand(draft, 'expired');
    call = (m, p, {body}) async {
      calls.add('$m $p');
      throw const ApiFailure('expired', code: 'plan_expired', status: 409);
    };
    await expectLater(files.send(old), throwsA(isA<ApiFailure>()));
    final saved = await selections.read(draft.id);
    expect(saved.remaining, draft.ids);
    expect(saved.batches.single.rejected, isTrue);
    expect(await files.pending(), isEmpty);
    await expectLater(files.send(old), throwsA(isA<LibraryFailure>()));
    expect(calls, hasLength(1));
    expect((await selections.save(saved.remaining)).id, saved.id);
  });
  test(
    'stale or forged batch cannot consume different remaining targets',
    () async {
      final draft = await selections.save(selectionIds(1027));
      final task = await files.send(batchCommand(draft, 'first'));
      await files.acknowledgeTask(task);
      await expectLater(
        files.send(batchCommand(draft, 'stale')),
        throwsA(isA<LibraryFailure>()),
      );
      await expectLater(
        files.send(batchCommand(draft, 'outside', ids: ['unrelated'])),
        throwsA(isA<LibraryFailure>()),
      );
      expect(calls, hasLength(1));
      expect((await selections.read(draft.id)).remaining, draft.ids.skip(1000));
      expect(await files.pending(), isEmpty);
    },
  );
  test('stale discard cannot remove a new batch; explicit discard retains actual command', () async {
    final draft = await selections.save(selectionIds(1027));
    call = (_, _, {body}) async =>
        throw const ApiFailure('lost', code: 'lost', status: 503);
    await expectLater(
      files.send(batchCommand(draft, 'unknown')),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      selections.discard(draft),
      throwsA(isA<LibraryFailure>()),
    );
    final latest = await selections.read(draft.id);
    await selections.discard(latest);
    expect(await selections.list(), isEmpty);
    expect((await files.pending()).single.requestId, 'unknown');
  });
  test(
    'historical choices cannot grant new deletion and scopes do not mix',
    () async {
      final draft = await selections.save(selectionIds(2));
      await files.journal.historicalPurgeSelections(files.scope);
      await expectLater(
        files.send(batchCommand(draft, 'old')),
        throwsA(isA<LibraryFailure>()),
      );
      expect(calls, isEmpty);
      expect((await selections.read(draft.id)).historical, isTrue);
      final other = PackPurgeSelections(
        PackFiles(
          journal: files.journal,
          scope: 'another-server',
          isCurrent: () => true,
          call: call,
        ),
      );
      expect(await other.list(), isEmpty);
      await other.save(selectionIds(2));
      expect(await other.list(), hasLength(1));
      expect(await selections.list(), hasLength(1));
    },
  );
  test('late write remains in original scope; stale gateway cannot publish or delete', () async {
    store.gate = Completer<void>();
    final saving = selections.save(selectionIds(2));
    await Future<void>.delayed(Duration.zero);
    current = false;
    store.gate!.complete();
    await expectLater(saving, throwsA(isA<RequestCancelled>()));
    expect(
      (await PackFileJournal(store).purgeSelections('server')).single.ids,
      selectionIds(2),
    );
    expect(
      await PackFileJournal(store).purgeSelections('another-server'),
      isEmpty,
    );
    expect(calls, isEmpty);
  });
  test('corrupt selection metadata is preserved and fails visibly; old unknown fields survive', () async {
    store.value = jsonEncode({
      'version': 1,
      'scopes': {},
      'future': {'kept': true},
    });
    final draft = await selections.save(selectionIds(2));
    expect(jsonDecode(store.value!)['future'], {'kept': true});
    final json = jsonDecode(store.value!);
    json['purge_selections_v1']['server'][draft.id]['ids'].add('trash-00000');
    store.value = jsonEncode(json);
    final corrupt = PackPurgeSelections(
      PackFiles(
        journal: PackFileJournal(store),
        scope: 'server',
        isCurrent: () => true,
        call: call,
      ),
    );
    final before = store.value;
    await expectLater(corrupt.list(), throwsA(isA<LibraryFailure>()));
    expect(store.value, before);
    expect(calls, isEmpty);
  });
}
