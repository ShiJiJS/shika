import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/backup_document.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_api.dart';

void main() {
  late Directory directory;
  late BackupFileStore store;
  late HttpServer server;
  late ServerApi api;
  const oldEpoch = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const newEpoch = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('server-file-');
    store = BackupFileStore(directory, owner: 'isolated:epoch-A');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ServerApi(
      Uri.parse('http://127.0.0.1:${server.port}'),
      token: 'isolated',
    );
    api.bindAuthority({
      'capabilities': ['management_authority'],
      'management_epoch': oldEpoch,
    });
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  void respond(Future<void> Function(HttpRequest) action) {
    server.listen((request) async {
      try {
        await action(request);
      } on IOException {
        /* Deliberate socket cancellation. */
      }
    });
  }

  test(
    'file upload uses exact bytes/authentication and a single POST',
    () async {
      final document = await store.capture(
        Stream.value(List.generate(1024 * 1024, (i) => i % 251)),
        maximumBytes: 2 * 1024 * 1024,
      );
      var calls = 0;
      respond((request) async {
        calls++;
        expect(request.headers.value('authorization'), 'Bearer isolated');
        expect(request.headers.value('x-management-epoch'), oldEpoch);
        expect(request.contentLength, document.bytes);
        expect(request.headers.contentType?.mimeType, 'application/x-ndjson');
        expect((await sha256.bind(request).first).toString(), document.sha256);
        request.response.headers.set('x-management-epoch', oldEpoch);
        request.response.write('{"id":"accepted"}');
        await request.response.close();
      });
      final response = await api.uploadFile(
        '/api/v1/management-backups/imports',
        document,
        headers: {'Idempotency-Key': 'original'},
      );
      expect(jsonDecode(utf8.decode(response.bytes)), {'id': 'accepted'});
      expect(calls, 1);
    },
  );
  test('source mutation fails before sending an upload', () async {
    final document = await store.capture(
      Stream.value([1, 2, 3]),
      maximumBytes: 10,
    );
    var calls = 0;
    respond((request) async {
      calls++;
      await request.response.close();
    });
    await File(document.path).writeAsBytes([3, 2, 1]);
    await expectLater(
      api.uploadFile('/imports', document),
      throwsA(isA<LibraryFailure>()),
    );
    expect(calls, 0);
  });
  test('lost uploaded response never repeats the original POST', () async {
    var calls = 0;
    final document = await store.capture(
      Stream.value([1, 2, 3]),
      maximumBytes: 10,
    );
    respond((request) async {
      calls++;
      await request.drain<void>();
      (await request.response.detachSocket(writeHeaders: false)).destroy();
    });
    await expectLater(
      api.uploadFile('/imports', document),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.code, 'code', 'network_unavailable')
            .having((e) => e.transportCause, 'cause', isA<IOException>())
            .having(
              (e) => e.transportPhase,
              'phase',
              ApiTransportPhase.waitingForHeaders,
            ),
      ),
    );
    expect(calls, 1);
  });
  test('download goes to a verified private file and metadata mismatch leaves no file', () async {
    final bytes = List<int>.generate(1024 * 1024 + 3, (i) => i % 251);
    final hash = sha256.convert(bytes).toString();
    respond((request) async {
      request.response.headers.set('x-management-epoch', oldEpoch);
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    final document = await api.downloadFile(
      '/api/v1/management-backups/original/download',
      store,
      expectedBytes: bytes.length,
      expectedSha256: hash,
      maximumBytes: 2 * 1024 * 1024,
    );
    await document.verify();
    expect(document.sha256, hash);
    await document.delete();
    await expectLater(
      api.downloadFile(
        '/download',
        store,
        expectedBytes: bytes.length,
        expectedSha256: '0' * 64,
        maximumBytes: 2 * 1024 * 1024,
      ),
      throwsA(isA<LibraryFailure>()),
    );
    expect(await directory.list().length, 0);
  });
  test(
    'cancel and deadline stop a stalled file response and clean partial output',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var calls = 0;
      respond((request) async {
        calls++;
        request.response.headers.set('x-management-epoch', oldEpoch);
        request.response.add([1]);
        await request.response.flush();
        if (!started.isCompleted) started.complete();
        await release.future;
        await request.response.close();
      });
      final scope = RequestScope();
      final work = api.downloadFile(
        '/download',
        store,
        expectedBytes: 3,
        expectedSha256: 'a' * 64,
        maximumBytes: 10,
        scope: scope,
      );
      final assertion = expectLater(work, throwsA(isA<RequestCancelled>()));
      await started.future;
      scope.cancel();
      await assertion;
      expect(await directory.list().length, 0);
      await expectLater(
        api.downloadFile(
          '/download',
          store,
          expectedBytes: 3,
          expectedSha256: 'a' * 64,
          maximumBytes: 10,
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'timeout')),
      );
      expect(await directory.list().length, 0);
      expect(calls, 2);
      release.complete();
    },
  );
  test(
    'only the exact original download can cross to a restored epoch',
    () async {
      var changed = 0;
      api.onManagementChanged = () {
        changed++;
      };
      final bytes = [1, 2, 3], hash = sha256.convert([1, 2, 3]).toString();
      respond((request) async {
        request.response.headers.set('x-management-epoch', newEpoch);
        request.response.add(bytes);
        await request.response.close();
      });
      await expectLater(
        api.downloadFile(
          '/current',
          store,
          expectedBytes: 3,
          expectedSha256: hash,
          maximumBytes: 10,
        ),
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'management_changed'),
        ),
      );
      expect(changed, 1);
      expect(await directory.list().length, 0);
      final old = await api.downloadFile(
        '/api/v1/management-backups/original/download',
        store,
        expectedBytes: 3,
        expectedSha256: hash,
        maximumBytes: 10,
        originalReceipt: true,
      );
      await old.verify();
      await expectLater(
        api.downloadFile(
          '/arbitrary-current-data',
          store,
          expectedBytes: 3,
          expectedSha256: hash,
          maximumBytes: 10,
          originalReceipt: true,
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'historical file reads require an explicit original graph or epoch',
    () async {
      var calls = 0;
      final bytes = [1, 2, 3], hash = sha256.convert([1, 2, 3]).toString();
      respond((request) async {
        calls++;
        expect(request.uri.queryParameters, {'epoch': oldEpoch});
        request.response.headers.set('x-management-epoch', newEpoch);
        request.response.add(bytes);
        await request.response.close();
      });
      for (final query in <Map<String, String>?>[
        null,
        {},
        {'epoch': 'unknown'},
        {'epoch': oldEpoch, 'current': 'true'},
      ]) {
        await expectLater(
          api.downloadFile(
            '/api/v1/management-history/tasks/old/download',
            store,
            expectedBytes: 3,
            expectedSha256: hash,
            maximumBytes: 10,
            originalReceipt: true,
            query: query,
          ),
          throwsArgumentError,
        );
      }
      expect(calls, 0);
      final file = await api.downloadFile(
        '/api/v1/management-history/tasks/old/download',
        store,
        expectedBytes: 3,
        expectedSha256: hash,
        maximumBytes: 10,
        originalReceipt: true,
        query: {'epoch': oldEpoch},
      );
      await file.verify();
      expect(calls, 1);
    },
  );
  test(
    'a generation change during a current download discards its late file',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final bytes = [1, 2, 3], hash = sha256.convert([1, 2, 3]).toString();
      respond((request) async {
        if (request.uri.path == '/changed') {
          request.response.headers.set('x-management-epoch', newEpoch);
          request.response.write('{}');
        } else {
          request.response.headers.set('x-management-epoch', oldEpoch);
          request.response.add([1]);
          await request.response.flush();
          started.complete();
          await release.future;
          request.response.add([2, 3]);
        }
        await request.response.close();
      });
      final work = api.downloadFile(
        '/current-file',
        store,
        expectedBytes: bytes.length,
        expectedSha256: hash,
        maximumBytes: 10,
      );
      final assertion = expectLater(
        work,
        throwsA(
          isA<ApiFailure>().having((e) => e.code, 'code', 'management_changed'),
        ),
      );
      await started.future;
      await expectLater(
        api.json('GET', '/changed'),
        throwsA(isA<ApiFailure>()),
      );
      release.complete();
      await assertion;
      expect(await directory.list().length, 0);
    },
  );
}
