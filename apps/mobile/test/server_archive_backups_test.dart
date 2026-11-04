import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/backup_document.dart';
import 'package:shika/library/backup_work_store.dart';
import 'package:shika/library/management_archives.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_backups.dart';

class _WriteUnknown extends MemoryBackupWorkStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    await super.write(value);
    if (fail) throw const LibraryFailure('isolated unknown journal write');
  }
}

void main() {
  late Directory directory;
  late BackupFileStore files;
  late HttpServer server;
  late ServerApi api;
  late ServerBackups client;
  late _WriteUnknown journal;
  late ValueNotifier<String?> status;
  late Map<String, Map<String, dynamic>> tasks;
  late Map<String, String> receipts;
  late List<Map<String, dynamic>> calls;
  var restored = 0, lose = '', shortPage = false;
  final bytes = utf8.encode('{"record":"logical-v2"}\n');
  final digest = sha256
      .convert(utf8.encode('{"record":"logical-v2"}\n'))
      .toString();
  const epoch = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  List<Map<String, dynamic>> roots(int offset, int limit) => [
    for (var n = offset; n < (offset + limit).clamp(0, 27); n++)
      {
        'id': 'r$n',
        'name': '目录$n',
        'original_path': '/previous/$n',
        'kind': n.isEven ? 'video' : 'pack',
        'enabled': true,
        'suggested_path': n == 26 ? null : '/local/$n',
      },
  ];
  Future<void> reopen() async {
    client.dispose();
    api.close();
    api = ServerApi(
      Uri.parse('http://127.0.0.1:${server.port}'),
      token: 'isolated',
    );
    api.bindAuthority({
      'capabilities': ['management_authority'],
      'management_epoch': epoch,
    });
    client = ServerBackups(
      api: api,
      scope: 'server:epoch-A',
      store: journal,
      status: status,
      onChanged: () {},
      onRestored: () async {
        restored++;
      },
    );
    await client.initialize();
  }

  setUp(() async {
    restored = 0;
    lose = '';
    shortPage = false;
    directory = await Directory.systemTemp.createTemp('archive-flow-');
    files = BackupFileStore(directory, owner: 'server:epoch-A');
    journal = _WriteUnknown();
    status = ValueNotifier(null);
    tasks = {};
    receipts = {};
    calls = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ServerApi(Uri.parse('http://127.0.0.1:${server.port}'));
    client = ServerBackups(
      api: api,
      scope: files.owner,
      store: journal,
      status: status,
      onChanged: () {},
      onRestored: () async {
        restored++;
      },
    );
    await reopen();
    server.listen((request) async {
      try {
        final body = await request.expand((c) => c).toList();
        final path = request.uri.path;
        calls.add({'method': request.method, 'path': path, 'body': body});
        request.response.headers.set('x-management-epoch', epoch);
        Object response = {};
        if (request.method == 'POST') {
          final kind =
              (path.endsWith('/imports') || path.contains('/from-snapshot/'))
              ? 'inspect'
              : path.endsWith('/restores')
              ? 'restore'
              : 'export';
          final payload = kind == 'inspect' && !path.contains('/from-snapshot/')
              ? <String, dynamic>{}
              : jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
          final key = kind == 'inspect' && !path.contains('/from-snapshot/')
              ? request.headers.value('Idempotency-Key')!
              : payload['request_id'] as String;
          final id = '$kind-${tasks.length}';
          receipts['$kind:$key'] = id;
          final result = kind == 'restore'
              ? {'restored': true, 'pre_snapshot_id': 'snapshot-1'}
              : {
                  'file_sha256': digest,
                  'bytes': bytes.length,
                  'version': 2,
                  if (kind == 'inspect') ...{
                    'roots_count': 27,
                    'counts': {
                      'roots': 27,
                      'videos': 18,
                      'tags': 2,
                      'packs': 30,
                      'pack_pages': 300,
                      'pack_tag_definitions': 3,
                    },
                  },
                };
          tasks[id] = {
            'id': id,
            'kind': 'backup_${kind}_v2',
            'status': 'completed',
            'phase': 'completed',
            'created_at': 1,
            'finished_at': 2,
            'result': result,
            'error': null,
          };
          if (kind == 'inspect' && !path.contains('/from-snapshot/')) {
            expect(sha256.convert(body).toString(), digest);
          }
          response = tasks[id]!;
          if (lose == kind) {
            lose = '';
            (await request.response.detachSocket(writeHeaders: false))
                .destroy();
            return;
          }
        } else if (path.endsWith('/latest-restore')) {
          response = {
            'item': {
              'restore_id': 'previous-restore',
              'snapshot_id': 'previous-snapshot',
              'kind': 'backup_snapshot_v2',
              'created_at': 1.25,
              'bytes': bytes.length,
              'file_sha256': digest,
            },
          };
        } else if (path.contains('/requests/')) {
          final segments = path.split('/');
          final found =
              receipts['${segments[segments.length - 2]}:${segments.last}'];
          if (found == null) {
            request.response.statusCode = 404;
            response = {
              'error': {
                'code': 'backup_request_not_found',
                'message': 'original missing',
              },
            };
          } else {
            response = tasks[found]!;
          }
        } else if (path.endsWith('/download')) {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
          return;
        } else if (path.endsWith('/roots')) {
          final offset = int.parse(request.uri.queryParameters['offset']!);
          final limit = int.parse(request.uri.queryParameters['limit']!);
          response = {
            'total': 27,
            'offset': offset,
            'limit': limit,
            'items': shortPage ? [] : roots(offset, limit),
          };
        } else if (path.startsWith('/api/v1/tasks/')) {
          response = tasks[path.split('/').last]!;
        }
        request.response.write(jsonEncode(response));
        await request.response.close();
      } on IOException {
        /* Deliberate lost responses. */
      }
    });
  });
  tearDown(() async {
    client.dispose();
    api.close();
    status.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  int writes(String path) =>
      calls.where((v) => v['method'] == 'POST' && v['path'] == path).length;
  Future<BackupDocument> source() =>
      files.capture(Stream.value(bytes), maximumBytes: 1024);

  test('latest restore point is a current scoped read, not an original receipt bypass', () async {
    final point = (await client.latestRestorePoint())!;
    expect(point.owner, files.owner);
    expect(point.snapshotId, 'previous-snapshot');
    expect(point.createdAt, 1.25);
    expect(calls.single['method'], 'GET');
  });

  test('snapshot lost response and reopening query one original without reinspection or restore', () async {
    final point = ArchiveRestorePoint.fromJson({
      'restore_id': 'restore-previous',
      'snapshot_id': 'snapshot-previous',
      'kind': 'backup_snapshot_v2',
      'created_at': 1.25,
      'bytes': bytes.length,
      'file_sha256': digest,
    }, owner: files.owner);
    lose = 'inspect';
    await expectLater(
      client.inspectRestorePoint(point),
      throwsA(isA<ApiFailure>()),
    );
    await reopen();
    final preview = await client.resumeDocumentPreview();
    expect(preview.fileSha256, digest);
    await client.inspectRestorePoint(point);
    expect(
      writes('/api/v1/management-backups/from-snapshot/snapshot-previous'),
      1,
    );
    expect(writes('/api/v1/management-backups/imports'), 0);
    expect(writes('/api/v1/management-backups/restores'), 0);
    expect(restored, 0);
  });

  test('export/save cancellation and reopening preserve the same original job and file', () async {
    final first = await client.exportDocument(files, maximumBytes: 1024);
    expect(client.pendingReceipts.single['version'], 2);
    await reopen();
    final next = await client.exportDocument(files, maximumBytes: 1024);
    expect(next.taskId, first.taskId);
    expect(next.document.path, first.document.path);
    expect(writes('/api/v1/management-backups'), 1);
    await next.document.delete();
    final recovered = await client.exportDocument(files, maximumBytes: 1024);
    expect(recovered.taskId, first.taskId);
    expect(writes('/api/v1/management-backups'), 1);
    await client.markExportSaved(recovered.taskId, files: files);
    expect(await File(recovered.document.path).exists(), isFalse);
    expect(client.pendingReceipts, isEmpty);
  });
  test('lost export response reconciles by GET and never creates a replacement job', () async {
    lose = 'export';
    await expectLater(
      client.exportDocument(files, maximumBytes: 1024),
      throwsA(isA<ApiFailure>()),
    );
    await reopen();
    final result = await client.exportDocument(files, maximumBytes: 1024);
    expect(result.taskId, startsWith('export-'));
    expect(writes('/api/v1/management-backups'), 1);
    expect(
      calls.any(
        (v) => v['path'].toString().startsWith(
          '/api/v1/management-backups/requests/export/',
        ),
      ),
      isTrue,
    );
  });
  test('lost import response resumes without needing the local input or repeating POST', () async {
    final document = await source();
    lose = 'inspect';
    await expectLater(
      client.inspectDocument(document),
      throwsA(isA<ApiFailure>()),
    );
    await document.delete();
    await reopen();
    final preview = await client.resumeDocumentPreview();
    expect(preview.protocol, 2);
    expect(preview.counts['packs'], 30);
    final first = await client.documentRoots(preview),
        tail = await client.documentRoots(preview, offset: 24);
    expect(first.items.length, 24);
    expect(tail.items.length, 3);
    expect(tail.items.last.suggestedPath, isNull);
    expect(writes('/api/v1/management-backups/imports'), 1);
  });
  test('lost restore response retains complete mapping and queries the v2 original on reopening', () async {
    final preview = await client.inspectDocument(await source());
    final mapping = {
      for (var n = 0; n < 27; n++) 'r$n': n == 26 ? null : '/local/$n',
    };
    lose = 'restore';
    await expectLater(
      client.restoreDocument(preview, mapping),
      throwsA(isA<ApiFailure>()),
    );
    expect(client.restorePending, isTrue);
    final saved = jsonDecode(journal.value!) as Map;
    expect(saved['restore']['version'], 2);
    expect(saved['restore']['body']['root_mapping'], mapping);
    await reopen();
    await client.reconcile();
    expect(restored, 1);
    expect(client.restorePending, isFalse);
    expect(writes('/api/v1/management-backups/restores'), 1);
    expect(
      calls.any(
        (v) => v['path'].toString().startsWith(
          '/api/v1/management-backups/requests/restore/',
        ),
      ),
      isTrue,
    );
  });
  test('unknown journal write and missing original remain query-only after reopening', () async {
    final document = await source();
    journal.fail = true;
    await expectLater(
      client.inspectDocument(document),
      throwsA(isA<LibraryFailure>()),
    );
    expect(writes('/api/v1/management-backups/imports'), 0);
    journal.fail = false;
    await reopen();
    await expectLater(
      client.resumeDocumentPreview(),
      throwsA(isA<LibraryFailure>()),
    );
    expect(client.pendingReceipts.single['kind'], 'inspect');
    expect(writes('/api/v1/management-backups/imports'), 0);
  });
  test('incomplete root pages, spoofed previews and another owner cannot authorize a restore', () async {
    final preview = await client.inspectDocument(await source());
    shortPage = true;
    await expectLater(
      client.documentRoots(preview),
      throwsA(isA<LibraryFailure>()),
    );
    final fake = ArchivePreview(
      taskId: preview.taskId,
      protocol: 2,
      fileVersion: 2,
      fileSha256: digest,
      bytes: bytes.length,
      rootsTotal: 0,
      counts: {},
    );
    await expectLater(
      client.restoreDocument(fake, {}),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(
      client.restoreDocument(preview, {'r0': '/one'}),
      throwsA(isA<LibraryFailure>()),
    );
    final other = BackupFileStore(
      Directory('${directory.path}/other'),
      owner: 'different-service',
    );
    await expectLater(
      client.inspectDocument(
        await other.capture(Stream.value(bytes), maximumBytes: 1024),
      ),
      throwsA(isA<LibraryFailure>()),
    );
    expect(writes('/api/v1/management-backups/restores'), 0);
  });
  test('an existing v1 export is read with its own protocol before starting a v2 export', () async {
    journal.value = jsonEncode({
      'scope': files.owner,
      'export': {'key': 'legacy-key', 'task': 'legacy-task'},
    });
    tasks['legacy-task'] = {
      'id': 'legacy-task',
      'kind': 'backup_export',
      'status': 'completed',
      'result': {'file_sha256': digest, 'bytes': bytes.length},
    };
    await reopen();
    final value = await client.exportDocument(files, maximumBytes: 1024);
    expect(value.taskId, 'legacy-task');
    expect(
      calls.any((v) => v['path'] == '/api/v1/backups/legacy-task/download'),
      isTrue,
    );
    expect(writes('/api/v1/management-backups'), 0);
    await client.markExportSaved(value.taskId);
    await client.exportDocument(files, maximumBytes: 1024);
    expect(writes('/api/v1/management-backups'), 1);
  });
}
