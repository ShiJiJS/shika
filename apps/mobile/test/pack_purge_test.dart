import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_purge_review_session.dart';
import 'package:shika/features/packs/pack_trash_session.dart';
import 'package:shika/library/file_command_store.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_api.dart';

import 'support/pack_purge_fixture.dart';

void main() {
  test('earlier result acknowledgement cannot forget a subsequently accepted retry', () async {
    var queued = false;
    final files = PackFiles(
      journal: PackFileJournal(MemoryFileCommandStore()),
      scope: 'server',
      isCurrent: () => true,
      call: (_, _, {body}) async => queued
          ? {
              'id': 'purge-op',
              'kind': 'pack_permanent',
              'status': 'queued',
              'result': {},
              'error': null,
            }
          : purgeTaskJson(['trash-0'], failed: true),
    );
    final original = PackFileCommand.permanent(
      'old',
      planId: 'plan',
      digest: purgeHash,
      trashIds: ['trash-0'],
      imageCount: 3,
    );
    final earlier = await files.send(original);
    queued = true;
    final retry = PackFileCommand.retry(
      'new',
      earlier.id,
      targets: ['trash-0'],
      expectedTaskKind: 'pack_permanent',
    );
    await files.send(retry);
    await files.acknowledgeTask(earlier);
    expect((await files.pending()).single.requestId, 'new');
    queued = false;
    final latest = await files.receipt(retry);
    await files.acknowledgeTask(latest!);
    expect(await files.pending(), isEmpty);
  });
  test('trash acceptance retains uncertain permanent command and selected failures', () async {
    final repo = PurgeLibrary();
    final files = PackFiles(
      journal: repo.journal,
      scope: 'trash-fixture',
      isCurrent: () => true,
      call: (_, _, {body}) async => purgeTaskJson(['trash-0'], attention: true),
    );
    final trash = PackTrashSession(repo, files: files);
    addTearDown(trash.dispose);
    await trash.load();
    trash.toggle('trash-0');
    final command = PackFileCommand.permanent(
      'uncertain',
      planId: 'plan',
      digest: purgeHash,
      trashIds: ['trash-0'],
      imageCount: 3,
    );
    await trash.accept(command, await files.send(command));
    expect(trash.selection.ids, {'trash-0'});
    expect(trash.pending.single.requestId, 'uncertain');
    expect(trash.message, contains('待核对'));
    expect(trash.message, isNot(contains('已恢复')));
  });
  test('preparation lost reply recovers same key with GET; authorization sends nothing', () async {
    final repo = PurgeLibrary()..losePreparation = true;
    final gateway = repo.createPackPurge() as PurgeGateway;
    final review = PackPurgeReviewSession(gateway, ['trash-0']);
    addTearDown(review.dispose);
    await review.load(submit: true);
    expect(gateway.receiptReads, 1);
    expect(repo.preparations.length, 1);
    expect(review.checked, isFalse);
    expect(() => review.authorize(), throwsA(isA<LibraryFailure>()));
    review.check(true);
    final command = review.authorize();
    expect(command.body, {
      'plan_id': 'plan',
      'digest': purgeHash,
      'confirmed': true,
    });
    expect(command.resources, {'trash:trash-0', 'plan:plan'});
    expect(command.expectedImages, 3);
    expect(repo.physicalPosts, isEmpty);
    expect(repo.commandStore.value, isNull);
  });
  test('expired review and renewed plan reset checkbox; invalid owner blocks authorization', () async {
    final repo = PurgeLibrary();
    final review = PackPurgeReviewSession(repo.createPackPurge(), ['trash-0']);
    addTearDown(review.dispose);
    await review.load(submit: true);
    review.check(true);
    repo.expired = true;
    await review.load(renew: true);
    expect(review.checked, isFalse);
    expect(review.canConfirm, isFalse);
    review.check(true);
    expect(() => review.authorize(), throwsA(isA<LibraryFailure>()));
    repo.expired = false;
    await review.load(renew: true);
    expect(review.checked, isFalse);
    review.check(true);
    repo.replaceConnection();
    expect(() => review.authorize(), throwsA(isA<LibraryFailure>()));
    expect(repo.physicalPosts, isEmpty);
  });
  test(
    'closing during preparation cannot publish or authorize its late result',
    () async {
      final repo = PurgeLibrary()..preparationGate = Completer<void>();
      final review = PackPurgeReviewSession(repo.createPackPurge(), [
        'trash-0',
      ]);
      final pending = review.load(submit: true);
      review.dispose();
      repo.preparationGate!.complete();
      await pending;
      expect(review.plan, isNull);
      expect(() => review.authorize(), throwsA(isA<LibraryFailure>()));
      expect(repo.physicalPosts, isEmpty);
    },
  );
  test(
    '1000-pack review leaves 27 selected until a separate confirmation',
    () async {
      final repo = PurgeLibrary(count: 1027);
      final trash = PackTrashSession(repo);
      addTearDown(trash.dispose);
      await trash.load();
      await trash.selectAll();
      final review = PackPurgeReviewSession(
        repo.createPackPurge(),
        trash.selection.ids,
      );
      addTearDown(review.dispose);
      await review.load(submit: true);
      review.check(true);
      final command = review.authorize();
      expect(command.targets.length, 1000);
      final task = await trash.files.send(command);
      await trash.accept(command, task);
      expect(trash.selection.ids.length, 27);
      expect(repo.physicalPosts.length, 1);
      expect(await trash.files.pending(), isEmpty);
    },
  );
  test('physical intent persists before POST and survives lost reply plus fresh journal', () async {
    final store = MemoryFileCommandStore();
    var posts = 0;
    final command = PackFileCommand.permanent(
      'once',
      planId: 'plan',
      digest: purgeHash,
      trashIds: ['trash-0'],
      imageCount: 3,
    );
    Future<Json> call(String method, String path, {Json? body}) async {
      if (method == 'POST') {
        expect(store.value, contains('once'));
        expect(body, {
          'request_id': 'once',
          'plan_id': 'plan',
          'digest': purgeHash,
          'confirmed': true,
        });
        posts++;
        throw const ApiFailure('lost', code: 'reply_lost', status: 503);
      }
      return purgeTaskJson(['trash-0']);
    }

    PackFiles client() => PackFiles(
      journal: PackFileJournal(store),
      scope: 'server',
      isCurrent: () => true,
      call: call,
    );
    await expectLater(client().send(command), throwsA(isA<ApiFailure>()));
    final fresh = client();
    final recovered = (await fresh.pending()).single;
    expect(recovered.signature, command.signature);
    final task = await fresh.resolve(recovered);
    expect(posts, 1);
    await fresh.acknowledgeTask(task!);
    expect(await fresh.pending(), isEmpty);
  });
  test('uncertain purge keeps original record and locks resources; bound retry clears both only after settlement', () async {
    final store = MemoryFileCommandStore(),
        journal = PackFileJournal(MemoryFileCommandStore());
    var attention = true;
    late PackFiles files;
    files = PackFiles(
      journal: journal,
      scope: 'server',
      isCurrent: () => true,
      call: (method, path, {body}) async =>
          purgeTaskJson(['trash-0'], attention: attention),
    );
    final command = PackFileCommand.permanent(
      'first',
      planId: 'plan',
      digest: purgeHash,
      trashIds: ['trash-0'],
      imageCount: 3,
    );
    final task = await files.send(command);
    expect(task.result!.pagesDeleted, 1);
    expect(task.result!.pagesPending, 1);
    await expectLater(
      files.acknowledge(command),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(
      files.send(PackFileCommand.restore('restore', ['trash-0'])),
      throwsA(isA<LibraryFailure>()),
    );
    final retry = PackFileCommand.retry(
      'retry',
      task.id,
      targets: ['trash-0'],
      expectedTaskKind: 'pack_permanent',
    );
    attention = false;
    final completed = await files.send(retry);
    expect((await files.pending()).length, 2);
    await files.acknowledgeTask(completed);
    expect(await files.pending(), isEmpty);
    expect(store.value, isNull);
  });
  test(
    'permanent command rejects tampered local scope and result counts',
    () async {
      final command = PackFileCommand.permanent(
        'once',
        planId: 'plan',
        digest: purgeHash,
        trashIds: ['trash-0'],
        imageCount: 3,
      );
      final raw = jsonDecode(jsonEncode(command.toJson())) as Json;
      raw['targets'] = ['trash-0', 'trash-0'];
      expect(
        () => PackFileCommand.fromJson(raw),
        throwsA(isA<LibraryFailure>()),
      );
      final task = purgeTaskJson(['trash-0'], attention: true);
      task['result']['pages_deleted'] = 3;
      expect(() => PackFileTask.fromJson(task), throwsA(isA<LibraryFailure>()));
      final files = PackFiles(
        journal: PackFileJournal(MemoryFileCommandStore()),
        scope: 'server',
        isCurrent: () => true,
        call: (_, _, {body}) async => purgeTaskJson(['other']),
      );
      await expectLater(files.send(command), throwsA(isA<LibraryFailure>()));
      expect((await files.pending()).length, 1);
    },
  );
  test(
    'ready plan binds membership, aggregates, fingerprint and image path',
    () {
      final raw = purgePlanJson(['trash-0']);
      final plan = PackPurgePlan(raw);
      expect(() => plan.bind(['other']), throwsA(isA<LibraryFailure>()));
      raw['result']['image_count'] = 4;
      expect(() => PackPurgePlan(raw), throwsA(isA<LibraryFailure>()));
      expect(
        () => PackPurgeImage({
          'id': 'p',
          'path': '/packs/trash-0/../outside.jpg',
          'relative_path': '../outside.jpg',
          'size': 1,
          'sha256': purgeHash,
          'signature': [1, 2, 3, 4, 5],
        }, plan.members.single),
        throwsA(isA<LibraryFailure>()),
      );
    },
  );
}
