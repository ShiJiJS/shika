import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/backup_work_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_backups.dart';

void main() {
  late HttpServer server;
  late ServerApi api;
  late ServerBackups client;
  late MemoryBackupWorkStore store;
  late ValueNotifier<String?> status;
  late Map<String, Map<String, dynamic>> tasks;
  late Map<String, String> receipts;
  late List<Map<String, dynamic>> requests;
  var failDownload = false,
      failTask = false,
      loseRestore = false,
      dropRestore = false,
      corruptDownload = false,
      failReadback = false;
  String? inspectError, restoreError;
  var restored = 0;
  final text = jsonEncode({
    'format': 'video-viewer-management',
    'version': 1,
    'payload': {'sample': '真实备份正文'},
  });
  final digest = sha256.convert(utf8.encode(text)).toString();

  Future<void> reopen([String scope = 'server-1']) async {
    client.dispose();
    api.close();
    api = ServerApi(
      Uri.parse('http://127.0.0.1:${server.port}'),
      token: 'test-only',
    );
    client = ServerBackups(
      api: api,
      scope: scope,
      store: store,
      status: status,
      onChanged: () {},
      onRestored: () async {
        if (failReadback) {
          failReadback = false;
          throw const LibraryFailure('结果读取暂时失败');
        }
        restored++;
      },
    );
    await client.initialize();
  }

  setUp(() async {
    tasks = {};
    receipts = {};
    requests = [];
    restored = 0;
    failDownload = false;
    failTask = false;
    loseRestore = false;
    dropRestore = false;
    corruptDownload = false;
    failReadback = false;
    inspectError = null;
    restoreError = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final bytes = await request.expand((chunk) => chunk).toList();
      final row = <String, dynamic>{'method': request.method, 'path': path};
      requests.add(row);
      Object response = {};
      void error(int code, String message) {
        request.response.statusCode = code;
        response = {
          'error': {'code': 'fixture', 'message': message},
        };
      }

      if (request.method == 'POST') {
        final body = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(bytes)) as Map,
        );
        final kind = path == '/api/v1/backups'
            ? 'export'
            : path == '/api/v1/backup-imports'
            ? 'inspect'
            : 'restore';
        final key =
            (request.headers.value('Idempotency-Key') ?? body['request_id'])
                as String;
        row['key'] = key;
        if (kind == 'restore' && dropRestore) {
          dropRestore = false;
          (await request.response.detachSocket(writeHeaders: false)).destroy();
          return;
        }
        final receipt = '$kind:$key';
        final id = receipts.putIfAbsent(
          receipt,
          () => 'task-${receipts.length}',
        );
        tasks.putIfAbsent(
          id,
          () => {
            'id': id,
            'kind': 'backup_$kind',
            'phase': 'completed',
            'status':
                (kind == 'inspect'
                        ? inspectError
                        : kind == 'restore'
                        ? restoreError
                        : null) ==
                    null
                ? 'completed'
                : 'failed',
            'error': kind == 'inspect'
                ? inspectError
                : kind == 'restore'
                ? restoreError
                : null,
            'result': kind == 'inspect'
                ? {
                    'file_sha256': sha256.convert(bytes).toString(),
                    'counts': {'videos': 3, 'tags': 2, 'trash_items': 1},
                    'roots': [
                      {
                        'id': 'root',
                        'name': 'NAS视频',
                        'original_path': '/media',
                        'suggested_path': '/media',
                      },
                    ],
                  }
                : kind == 'restore'
                ? {'restored': true}
                : {'file_sha256': digest},
          },
        );
        response = tasks[id]!;
        if (kind == 'restore' && loseRestore) {
          loseRestore = false;
          error(503, '恢复响应丢失');
        }
      } else if (path.startsWith('/api/v1/tasks/')) {
        if (failTask) {
          failTask = false;
          error(503, '读取任务暂时失败');
        } else {
          response = tasks[path.split('/').last]!;
        }
      } else if (path.endsWith('/download')) {
        if (failDownload) {
          failDownload = false;
          error(503, '下载暂时失败');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(corruptDownload ? '$text ' : text);
          await request.response.close();
          return;
        }
      } else if (path.startsWith('/api/v1/backup-requests/')) {
        final pieces = path.split('/');
        final key = '${pieces[4]}:${pieces[5]}';
        if (receipts[key] == null) {
          error(404, '原任务不存在');
        } else {
          response = tasks[receipts[key]]!;
        }
      } else {
        error(404, '不存在');
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    store = MemoryBackupWorkStore();
    status = ValueNotifier(null);
    api = ServerApi(
      Uri.parse('http://127.0.0.1:${server.port}'),
      token: 'test-only',
    );
    client = ServerBackups(
      api: api,
      scope: 'server-1',
      store: store,
      status: status,
      onChanged: () {},
      onRestored: () async {
        if (failReadback) {
          failReadback = false;
          throw const LibraryFailure('结果读取暂时失败');
        }
        restored++;
      },
    );
    await client.initialize();
  });
  tearDown(() async {
    client.dispose();
    api.close();
    status.dispose();
    await server.close(force: true);
  });

  test(
    'failed download reopens its accepted export without making a new snapshot',
    () async {
      failDownload = true;
      await expectLater(client.export(), throwsA(isA<LibraryFailure>()));
      expect(store.value, isNot(contains('真实备份正文')));
      await reopen();
      expect(await client.export(), text);
      expect(
        requests.where(
          (r) => r['method'] == 'POST' && r['path'] == '/api/v1/backups',
        ),
        hasLength(1),
      );
    },
  );
  test('a successful HTTP download with different bytes is not reported as a valid backup', () async {
    corruptDownload = true;
    await expectLater(
      client.export(),
      throwsA(predicate((e) => e.toString().contains('完整性校验失败'))),
    );
    corruptDownload = false;
    expect(await client.export(), text);
    expect(
      requests.where(
        (r) => r['method'] == 'POST' && r['path'] == '/api/v1/backups',
      ),
      hasLength(1),
    );
  });
  test('same actual import file reopens its saved validation task and shows counts', () async {
    failTask = true;
    await expectLater(client.inspect(text), throwsA(isA<LibraryFailure>()));
    await reopen();
    final preview = await client.inspect(text);
    expect(preview.counts['videos'], 3);
    expect(preview.snapshot.roots.single.name, 'NAS视频');
    expect(preview.suggestedMappings, {'root': '/media'});
    expect(
      requests.where(
        (r) => r['method'] == 'POST' && r['path'] == '/api/v1/backup-imports',
      ),
      hasLength(1),
    );
    expect(store.value, isNot(contains('真实备份正文')));
  });
  test('bad and demo packages never reach a restore and failed checksum explains why', () async {
    await expectLater(
      client.inspect('{bad'),
      throwsA(predicate((e) => e.toString().contains('JSON'))),
    );
    await expectLater(
      client.inspect('{"format":"video-viewer-flutter-demo","version":1}'),
      throwsA(predicate((e) => e.toString().contains('版本不兼容'))),
    );
    expect(requests, isEmpty);
    inspectError = 'backup_checksum_mismatch';
    await expectLater(
      client.inspect(text),
      throwsA(predicate((e) => e.toString().contains('完整性校验失败'))),
    );
    expect(restored, 0);
  });
  test('uncertain accepted restore survives restart and only queries its original command', () async {
    loseRestore = true;
    await expectLater(
      client.restore(text, {'root': '/media'}),
      throwsA(isA<LibraryFailure>()),
    );
    expect(client.restorePending, isTrue);
    expect(restored, 0);
    await reopen();
    expect(client.restorePending, isTrue);
    await expectLater(client.export(), throwsA(isA<LibraryFailure>()));
    await expectLater(
      client.restore(text, {'root': '/other'}),
      throwsA(isA<LibraryFailure>()),
    );
    await client.reconcile();
    expect(client.restorePending, isFalse);
    expect(restored, 1);
    expect(
      requests.where(
        (r) => r['method'] == 'POST' && r['path'] == '/api/v1/backup-restores',
      ),
      hasLength(1),
    );
    expect(
      requests.any(
        (r) => (r['path'] as String).contains('/backup-requests/restore/'),
      ),
      isTrue,
    );
  });
  test('accepted restore with a task ID is queried across restart without a second POST', () async {
    await client.inspect(text);
    failTask = true;
    await expectLater(
      client.restore(text, {'root': '/media'}),
      throwsA(isA<LibraryFailure>()),
    );
    await reopen();
    await client.reconcile();
    expect(restored, 1);
    expect(
      requests.where(
        (r) => r['method'] == 'POST' && r['path'] == '/api/v1/backup-restores',
      ),
      hasLength(1),
    );
    expect(
      requests.any(
        (r) => (r['path'] as String).contains('/backup-requests/restore/'),
      ),
      isFalse,
    );
  });
  test('task completion is not reported until authoritative state can be refreshed', () async {
    failReadback = true;
    await expectLater(
      client.restore(text, {'root': '/media'}),
      throwsA(predicate((e) => e.toString().contains('结果读取'))),
    );
    expect(client.restorePending, isTrue);
    expect(restored, 0);
    await client.reconcile();
    expect(restored, 1);
    expect(client.restorePending, isFalse);
  });
  test(
    'a missing restore request is never resubmitted by query or by reopening',
    () async {
      dropRestore = true;
      await expectLater(
        client.restore(text, {'root': '/media'}),
        throwsA(isA<LibraryFailure>()),
      );
      await reopen();
      await expectLater(
        client.reconcile(),
        throwsA(predicate((e) => e.toString().contains('没有补执行'))),
      );
      expect(restored, 0);
      expect(client.restorePending, isFalse);
      expect(
        requests.where(
          (r) =>
              r['method'] == 'POST' && r['path'] == '/api/v1/backup-restores',
        ),
        hasLength(1),
      );
    },
  );
  test(
    'restore receipts from another service do not lock or replay into this one',
    () async {
      loseRestore = true;
      await expectLater(
        client.restore(text, {'root': '/media'}),
        throwsA(isA<LibraryFailure>()),
      );
      await reopen('different-instance');
      expect(client.restorePending, isFalse);
      await client.reconcile();
      expect(restored, 0);
      expect(
        requests.where(
          (r) =>
              r['method'] == 'POST' && r['path'] == '/api/v1/backup-restores',
        ),
        hasLength(1),
      );
    },
  );
}
