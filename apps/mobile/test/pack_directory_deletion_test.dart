import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_directory_deletion.dart';
import 'package:video_viewer/features/packs/pack_purge_review.dart';
import 'package:video_viewer/features/packs/pack_trash_page.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/pack_purge_fixture.dart';

Json directoryTask(List<String> ids, {bool done = false}) => {
  'id': 'directory-task-${ids.first}',
  'kind': 'pack_directory_delete',
  'status': done ? 'completed' : 'queued',
  'error': null,
  'result': done
      ? {
          'operation_id': 'directory-task-${ids.first}',
          'total': ids.length,
          'processed': ids.length,
          'succeeded': ids.length,
          'failed': 0,
          'partial': false,
          'needs_attention': false,
          'items': [
            for (final id in ids)
              {
                'requested_id': id,
                'trash_id': id,
                'pack_id': 'pack-$id',
                'phase': 'committed',
                'outcome': 'succeeded',
                'error': null,
              },
          ],
          'reading_restored': false,
          'reading_transition': null,
          'undo_expires_at': null,
        }
      : <String, dynamic>{},
};

class DirectoryLibrary extends PurgeLibrary {
  DirectoryLibrary({super.count});
  final directoryPosts = <Json>[];
  final directoryReceipts = <String, Json>{};
  Completer<void>? acceptance;
  bool loseReply = false;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    'pack_directory_delete',
  ]);
  @override
  PackFiles createPackFiles() {
    final fallback = super.createPackFiles(), identity = owner;
    return PackFiles(
      journal: journal,
      scope: 'trash-fixture',
      isCurrent: () => identical(identity, owner),
      call: (method, path, {body}) async {
        if (method == 'POST' &&
            path == '/api/v1/pack-trash/directories/permanent') {
          expect(commandStore.value, contains(body!['request_id']));
          directoryPosts.add(body);
          if (acceptance != null) await acceptance!.future;
          final ids = (body['trash_ids'] as List).cast<String>();
          final result = directoryTask(ids);
          directoryReceipts[body['request_id']] = result;
          for (final id in ids) {
            records.remove(id);
          }
          if (loseReply) {
            loseReply = false;
            throw const ApiFailure('lost', code: 'timeout');
          }
          return result;
        }
        if (method == 'GET' &&
            directoryReceipts.containsKey(path.split('/').last)) {
          return directoryReceipts[path.split('/').last]!;
        }
        return fallback.call(method, path, body: body);
      },
    );
  }
}

void main() {
  testWidgets(
    'selected folders submit without a review sheet or waiting for server acceptance',
    (t) async {
      final repo = DirectoryLibrary(count: 2)..acceptance = Completer<void>();
      await repo.initialize();
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(body: PackTrashPage(repository: repo, active: true)),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pack-trash-item-trash-0')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('pack-trash-permanent')));
      await t.tap(find.byKey(const Key('pack-trash-permanent')));
      await t.pump();
      expect(find.byType(PackPurgeReview), findsNothing);
      expect(repo.preparations, isEmpty);
      expect(repo.directoryPosts.length, 1);
      expect(repo.directoryPosts.single['trash_ids'], ['trash-0']);
      expect(
        (await repo.createPackFiles().pending()).single.kind,
        'directory_delete',
      );
      // The browser can close while HTTP acceptance is still pending.
      await t.pumpWidget(const SizedBox());
      repo.acceptance!.complete();
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull);
      repo.dispose();
    },
  );

  test('all large-selection batches are persisted before network and submitted once', () async {
    final repo = DirectoryLibrary(count: 1027)..acceptance = Completer<void>();
    final files = repo.createPackFiles();
    final commands = await enqueueDirectoryDeletion(
      repo,
      files,
      repo.records.keys.toList(),
    );
    expect(commands.map((c) => c.targets.length), [1000, 27]);
    expect((await files.pending()).length, 2);
    for (var i = 0; i < 50 && repo.directoryPosts.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(repo.directoryPosts.length, 1);
    repo.acceptance!.complete();
    for (var i = 0; i < 20 && repo.directoryPosts.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(repo.directoryPosts.length, 2);
    expect(repo.preparations, isEmpty);
    expect(repo.physicalPosts, isEmpty);
    repo.dispose();
  });

  test('lost acceptance reply only GETs original task and a fresh journal recovers it', () async {
    final repo = DirectoryLibrary()..loseReply = true;
    final files = repo.createPackFiles();
    final commands = await enqueueDirectoryDeletion(repo, files, ['trash-0']);
    for (var i = 0; i < 20 && repo.directoryReceipts.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.directoryPosts.length, 1);
    final store = MemoryFileCommandStore()..value = repo.commandStore.value;
    final fresh = PackFiles(
      journal: PackFileJournal(store),
      scope: files.scope,
      isCurrent: () => true,
      call: (method, path, {body}) async {
        expect(method, 'GET');
        return directoryTask(['trash-0'], done: true);
      },
    );
    final pending = (await fresh.pending()).single;
    expect(pending.signature, commands.single.signature);
    final result = await fresh.receipt(pending);
    expect(result!.kind, 'pack_directory_delete');
    await fresh.acknowledgeTask(result);
    expect(await fresh.pending(), isEmpty);
    expect(repo.directoryPosts.length, 1);
    repo.dispose();
  });
}
