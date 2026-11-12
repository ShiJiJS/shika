import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

void main() {
  late PackServer server;
  late ServerLibraryRepository repo;
  String identity = 'scan-1';
  Completer<void>? entered, release;
  setUp(() async {
    identity = 'scan-1';
    entered = release = null;
    server = PackServer();
    server.handle = (request, _) async {
      if (!request.uri.path.contains('/tasks/')) return null;
      expect(request.method, 'GET');
      expect(request.headers.value('Authorization'), 'Bearer pack-test-token');
      entered?.complete();
      if (release != null) await release!.future;
      return (
        status: 200,
        body: {
          'id': identity,
          'kind': 'scan',
          'status': 'completed',
          'result': {
            'issues': [
              {'root_id': 'r', 'code': 'probe_timeout', 'name': 'video.mp4'},
            ],
          },
        },
      );
    };
    await server.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await repo.connect('http://127.0.0.1', server.server.port, 'secret');
    server.writes.clear();
  });
  tearDown(() async {
    if (release != null && !release!.isCompleted) release!.complete();
    repo.dispose();
    await server.server.close(force: true);
  });
  test('report reads existing authenticated task without scanning or replacing lists', () async {
    final snapshot = repo.snapshot;
    final report = await repo.loadScanReport('scan-1');
    expect(
      report.issues(const MediaRoot('r', '视频', '/videos')).single.name,
      'video.mp4',
    );
    expect(repo.snapshot, same(snapshot));
    expect(server.writes, isEmpty);
  });
  test('mismatched task identity is refused', () async {
    identity = 'another-task';
    await expectLater(
      repo.loadScanReport('scan-1'),
      throwsA(isA<LibraryFailure>()),
    );
    expect(server.writes, isEmpty);
  });
  test('closing report cancels pending HTTP read', () async {
    entered = Completer<void>();
    release = Completer<void>();
    final scope = RequestScope();
    final pending = repo.loadScanReport('scan-1', cancel: scope);
    final expectation = expectLater(pending, throwsA(isA<RequestCancelled>()));
    await entered!.future;
    scope.cancel();
    await expectation;
    release!.complete();
    expect(server.writes, isEmpty);
  });
}
