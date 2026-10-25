import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';

void main() {
  late HttpServer server;
  late ServerLibraryRepository repo;
  late MemoryCredentialStore credentials;
  late MemoryFileCommandStore journal;
  late Map<String, String> states;
  late Map<String, Map<String, dynamic>> receipts;
  late List<Map<String, dynamic>> writes;
  late List<String> reads;
  bool lose = false, conflict = false, taskRunning = false, taskMissing = false;
  String serverId = 'files-fixture';
  Map<String, dynamic> video(String id) => {
    'id': id,
    'root_id': 'root',
    'path': '/media/$id.mp4',
    'width': 100,
    'height': 200,
    'duration': 2.0,
    'type': 'MP4',
    'status': states[id],
    'tag_ids': ['keep'],
    'thumbnail_url': null,
    'media_url': '/api/v1/videos/$id/stream',
  };
  setUp(() async {
    states = {'v1': 'available', 'v2': 'available', 'v3': 'trash'};
    receipts = {};
    writes = [];
    reads = [];
    lose = false;
    conflict = false;
    taskRunning = false;
    taskMissing = false;
    serverId = 'files-fixture';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path, query = request.uri.queryParameters;
      Object response = {};
      if (request.method == 'POST') {
        final body = Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        );
        writes.add({'path': path, ...body});
        final key = body['request_id'] as String;
        if (!receipts.containsKey(key)) {
          final taskId = 'server-operation-${receipts.length}';
          final items = <Map<String, dynamic>>[];
          final ids = path.endsWith('/undo')
              ? ['v1']
              : List<String>.from(body['video_ids'] ?? body['trash_ids'])
                    .map((id) => id.replaceFirst('trash-', ''))
                    .toList();
          for (final id in ids) {
            final failed =
                id == 'missing' ||
                (conflict && path == '/api/v1/trash/restore');
            items.add({
              'video_id': id,
              'requested_id': id,
              'outcome': failed ? 'conflict' : 'succeeded',
              'error': failed ? 'destination_conflict' : null,
            });
            if (!failed) {
              states[id] = path == '/api/v1/videos/trash'
                  ? 'trash'
                  : path == '/api/v1/trash/permanent'
                  ? 'removed'
                  : 'available';
            }
          }
          final succeeded = items
              .where((i) => i['outcome'] == 'succeeded')
              .length;
          receipts[key] = {
            'id': taskId,
            'kind': 'files',
            'status': succeeded > 0 ? 'completed' : 'failed',
            'result': {
              'items': items,
              'succeeded': succeeded,
              'partial': succeeded > 0 && succeeded < items.length,
            },
          };
        }
        response = receipts[key]!;
        if (lose) {
          lose = false;
          (await request.response.detachSocket(writeHeaders: false)).destroy();
          return;
        }
      } else {
        reads.add(path);
        if (path == '/api/v1/info') {
          response = {'api_version': 1, 'server_id': serverId};
        } else if (path.startsWith('/api/v1/file-requests/')) {
          response = receipts[path.split('/').last] ?? {};
          if ((response as Map).isEmpty) {
            request.response.statusCode = 404;
            response = {
              'error': {
                'code': 'operation_not_found',
                'message': '原操作不存在，请核对后重新操作',
              },
            };
          }
        } else if (path.startsWith('/api/v1/tasks/')) {
          if (taskMissing) {
            request.response.statusCode = 404;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'error': {'code': 'not_found', 'message': '原任务不存在'},
              }),
            );
            await request.response.close();
            return;
          }
          response = receipts.values.singleWhere(
            (t) => t['id'] == path.split('/').last,
          );
          if (taskRunning) {
            response = {
              ...Map<String, dynamic>.from(response as Map),
              'status': 'running',
              'result': {'processed': 0, 'total': 1},
            };
          }
        } else if (path == '/api/v1/library-state') {
          response = {'ready': true, 'scanning': false, 'status': 'idle'};
        } else if (path == '/api/v1/roots') {
          response = {
            'items': [
              {
                'id': 'root',
                'name': '媒体',
                'path': '/media',
                'directory_id': 'dir',
                'available': true,
                'error': null,
                'last_scan': null,
              },
            ],
          };
        } else if (path == '/api/v1/playback') {
          final available = states.keys
              .where((id) => states[id] == 'available')
              .toList();
          response = {
            'id': 'round',
            'order': 'sequential',
            'scope': {'tag_ids': []},
            'position': 0,
            'total': available.length,
            'revision': writes.length,
            'current': available.isEmpty ? null : video(available.first),
            'window': [
              for (var i = 0; i < available.length; i++)
                {'position': i, 'video': video(available[i])},
            ],
          };
        } else if (path == '/api/v1/tags') {
          response = {
            'items': [
              {'id': 'keep', 'name': '保留', 'video_count': 3},
            ],
            'total': 1,
          };
        } else if (path == '/api/v1/trash') {
          final items = states.keys
              .where((id) => states[id] == 'trash')
              .toList();
          response = {
            'items': items
                .skip(int.parse(query['offset'] ?? '0'))
                .take(int.parse(query['limit'] ?? '24'))
                .map(
                  (id) => {
                    'id': 'trash-$id',
                    'original_path': '/media/$id.mp4',
                    'video': video(id),
                  },
                )
                .toList(),
            'total': items.length,
          };
        } else {
          response = {'items': [], 'total': 0};
        }
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    credentials = MemoryCredentialStore();
    journal = MemoryFileCommandStore();
    await credentials.save(
      ConnectionCredentials(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        token: 'test-token',
        serverId: serverId,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    repo = ServerLibraryRepository(credentials, fileCommands: journal);
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    await server.close(force: true);
  });

  test(
    'trash fetches unvisited rows and maps video selection to trash identity',
    () async {
      expect(repo.snapshot.videos.any((v) => v.id == 'v3'), isFalse);
      final page = await repo.loadTrash(limit: 1);
      expect(page.total, 1);
      expect(page.items.single.originalPath, '/media/v3.mp4');
      expect(page.items.single.tags, {'keep'});
      expect(await repo.restoreVideos({'v3'}), isEmpty);
      expect(writes.single['trash_ids'], ['trash-v3']);
      expect(states['v3'], 'available');
      await expectLater(
        repo.restoreVideos({'unvisited'}),
        throwsA(isA<LibraryFailure>()),
      );
      expect(writes, hasLength(1));
    },
  );
  test('manual query returns after one running task read instead of waiting for completion', () async {
    lose = true;
    await expectLater(
      repo.deleteVideos({'v1'}, requestId: 'pending-query'),
      throwsA(anything),
    );
    taskRunning = true;
    final before = reads.where((p) => p.startsWith('/api/v1/tasks/')).length;
    await repo.reconcileFileOperation().timeout(const Duration(seconds: 2));
    expect(repo.fileOperationPending, isTrue);
    expect(repo.fileStatus.value, contains('0 / 1'));
    expect(
      reads.where((p) => p.startsWith('/api/v1/tasks/')).length,
      before + 1,
    );
    taskRunning = false;
    await repo.reconcileFileOperation();
    expect(repo.fileOperationPending, isFalse);
    expect(writes, hasLength(1));
  });
  test(
    'lost submit response survives process restart and reconciles by read only',
    () async {
      lose = true;
      await expectLater(
        repo.deleteVideos({'v1'}, requestId: 'client-request'),
        throwsA(anything),
      );
      expect(repo.fileOperationPending, isTrue);
      expect(repo.current!.id, 'v1');
      repo.dispose();
      repo = ServerLibraryRepository(credentials, fileCommands: journal);
      await repo.initialize();
      expect(repo.fileOperationPending, isTrue);
      await repo.reconcileFileOperation();
      expect(repo.fileOperationPending, isFalse);
      expect(writes, hasLength(1));
      expect(reads, contains('/api/v1/file-requests/client-request'));
      final operation = repo.snapshot.lastDelete!;
      expect(operation.id, 'server-operation-0');
      expect(operation.ids, ['v1']);
      await repo.undoDelete(operationId: operation.id);
      expect(writes.last['path'], '/api/v1/operations/server-operation-0/undo');
      expect(repo.snapshot.lastDelete, isNull);
      expect(repo.current!.id, 'v1');
    },
  );
  test('a missing known task preserves its original receipt without replaying deletion', () async {
    lose = true;
    await expectLater(
      repo.deleteVideos({'v1'}, requestId: 'missing-known'),
      throwsA(anything),
    );
    taskRunning = true;
    await repo.reconcileFileOperation();
    taskMissing = true;
    await expectLater(
      repo.reconcileFileOperation(),
      throwsA(isA<LibraryFailure>()),
    );
    expect(repo.fileOperationPending, isTrue);
    expect(writes, hasLength(1));
  });
  test(
    'retry after lost response keeps original command despite new UI nonce',
    () async {
      lose = true;
      await expectLater(
        repo.deleteVideos({'v1'}, requestId: 'first'),
        throwsA(anything),
      );
      await repo.deleteVideos({'v1'}, requestId: 'second-ui-attempt');
      expect(writes.map((w) => w['request_id']), ['first']);
      expect(receipts, hasLength(1));
    },
  );
  test(
    'partial delete preserves precise undo subset and item failure',
    () async {
      await expectLater(
        repo.deleteVideos({'missing', 'v1'}, requestId: 'partial'),
        throwsA(predicate((e) => e.toString().contains('未覆盖'))),
      );
      expect(repo.snapshot.lastDelete!.ids, ['v1']);
      expect(repo.fileOperationPending, isFalse);
      expect(repo.current!.id, 'v2');
    },
  );
  test('conflicting restore preserves trash and permanent delete uses its identity', () async {
    await repo.loadTrash();
    conflict = true;
    expect(
      (await repo.restoreVideos({'v3'})).single,
      contains('v3.mp4：原位置已有同名文件'),
    );
    expect(states['v3'], 'trash');
    await repo.permanentlyDelete({'v3'});
    expect(writes.last['confirmed'], isTrue);
    expect(writes.last['trash_ids'], ['trash-v3']);
    expect(repo.trashCount, 0);
  });
  test('receipt is isolated from another server and no destructive request replays', () async {
    await repo.deleteVideos({'v1'}, requestId: 'old');
    expect(repo.snapshot.lastDelete, isNotNull);
    repo.dispose();
    serverId = 'other-server';
    final old = (await credentials.read())!;
    await credentials.save(
      ConnectionCredentials(
        endpoint: old.endpoint,
        token: old.token,
        serverId: serverId,
        expiresAt: old.expiresAt,
      ),
    );
    repo = ServerLibraryRepository(credentials, fileCommands: journal);
    await repo.initialize();
    expect(repo.snapshot.lastDelete, isNull);
    expect(repo.fileOperationPending, isFalse);
    expect(writes, hasLength(1));
  });

  test(
    'a missing historical request is queried without destructive replay',
    () async {
      lose = true;
      await expectLater(
        repo.deleteVideos({'v1'}, requestId: 'uncertain'),
        throwsA(anything),
      );
      repo.dispose();
      receipts
          .clear(); // An older restored catalog no longer knows the command.
      repo = ServerLibraryRepository(credentials, fileCommands: journal);
      await repo.initialize();
      await expectLater(repo.reconcileFileOperation(), throwsA(anything));
      expect(writes, hasLength(1));
      expect(repo.fileOperationPending, isTrue);
      expect(states['v1'], 'trash');
      await expectLater(
        repo.deleteVideos({'v2'}, requestId: 'new-confirmation'),
        throwsA(isA<LibraryFailure>()),
      );
      expect(writes, hasLength(1));
    },
  );

  test('failure to save the intent prevents sending a file mutation', () async {
    repo.dispose();
    repo = ServerLibraryRepository(
      credentials,
      fileCommands: _UnavailableJournal(),
    );
    await repo.initialize();
    await expectLater(
      repo.deleteVideos({'v1'}, requestId: 'not-sent'),
      throwsA(isA<FileSystemException>()),
    );
    expect(writes, isEmpty);
    expect(states['v1'], 'available');
  });
}

class _UnavailableJournal implements FileCommandStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async =>
      throw const FileSystemException('Storage unavailable');
}
