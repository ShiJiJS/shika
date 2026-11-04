import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_directory_deletion.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/file_command_store.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_repository.dart' hide Json;

import 'server_pack_catalog_test.dart' show PackServer;
import 'pack_directory_deletion_test.dart' show directoryTask;
import 'support/pack_purge_fixture.dart' show Json;

void main() {
  late PackServer server;
  late ServerLibraryRepository repo;
  late MemoryFileCommandStore store;
  late MemoryCredentialStore credentials;
  var finished = false, unavailable = false, posts = 0;
  final receipts = <String, List<String>>{};
  setUp(() async {
    finished = unavailable = false;
    posts = 0;
    receipts.clear();
    store = MemoryFileCommandStore();
    credentials = MemoryCredentialStore();
    server = PackServer();
    server.handle = (HttpRequest request, Json body) async {
      final path = request.uri.path;
      if (path == '/api/v1/info') {
        return (
          status: 200,
          body: {
            'api_version': 1,
            'server_id': 'packs',
            'capabilities': [
              'image_packs',
              'pack_tags',
              'pack_logical_trash',
              'pack_permanent_delete',
              'pack_directory_delete',
            ],
          },
        );
      }
      if (path == '/api/v1/pack-trash/directories/permanent') {
        posts++;
        final ids = (body['trash_ids'] as List).cast<String>();
        receipts[body['request_id']] = ids;
        return (status: 202, body: directoryTask(ids));
      }
      if (path.contains('/pack-file-requests/')) {
        if (unavailable) {
          return (
            status: 503,
            body: {
              'error': {'code': 'busy', 'message': 'later'},
            },
          );
        }
        final ids = receipts[path.split('/').last];
        if (ids != null) {
          return (status: 200, body: directoryTask(ids, done: finished));
        }
      }
      return null;
    };
    await server.start();
    repo = ServerLibraryRepository(credentials, packCommands: store);
    await repo.connect('http://127.0.0.1', server.server.port, 'test');
  });
  tearDown(() async {
    repo.dispose();
    await server.server.close(force: true);
  });
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  test('normal folder deletion automatically drops its pending record after server completion', () async {
    final files = repo.createPackFiles();
    final commands = await enqueueDirectoryDeletion(repo, files, ['trash-0']);
    await until(() => posts == 1 && receipts.isNotEmpty);
    await repo.reconcilePackDeletes();
    expect(await files.pending(), hasLength(1));
    expect(await PackPurgeSelections(files).list(), isEmpty);
    finished = true;
    repo.packFilesChanged();
    await until(() => repo.maintenancePendingCount == 0);
    expect(await files.pending(), isEmpty);
    expect(posts, 1);
    expect(commands.single.purgeSelectionId, isNull);
  });
  test('opening the app cleans up an already finished old request without resubmitting', () async {
    final files = repo.createPackFiles();
    final saved = await PackPurgeSelections(files).save(['trash-0']);
    final command = PackFileCommand.deleteDirectories('old-request', [
      'trash-0',
    ], selectionId: saved.id);
    await files.journal.remember(files.scope, command);
    receipts[command.requestId] = ['trash-0'];
    finished = true;
    repo.dispose();
    repo = ServerLibraryRepository(credentials, packCommands: store);
    await repo.initialize();
    await until(() => repo.maintenancePendingCount == 0);
    expect(await repo.createPackFiles().pending(), isEmpty);
    expect(posts, 0);
  });
  test('temporary read failure retains the original request and later refresh completes it', () async {
    final files = repo.createPackFiles();
    final command = PackFileCommand.deleteDirectories('recover', ['trash-0']);
    await files.journal.remember(files.scope, command);
    receipts[command.requestId] = ['trash-0'];
    unavailable = true;
    await repo.reconcilePackDeletes();
    expect(await files.pending(), hasLength(1));
    unavailable = false;
    finished = true;
    await repo.reconcilePackDeletes();
    expect(await files.pending(), isEmpty);
    expect(posts, 0);
  });
}
