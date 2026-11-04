import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;
import 'support/root_scan_fixture.dart';

void main() {
  late PackServer fixture;
  late ServerLibraryRepository repo;
  bool precise = true, scoped = true, fail = false;
  bool disposed = false;
  Completer<void>? entered, release;
  late Map<String, dynamic> state;
  setUp(() async {
    precise = scoped = true;
    fail = false;
    disposed = false;
    entered = release = null;
    state = scanFixture();
    fixture = PackServer();
    fixture.handle = (request, body) async {
      if (request.uri.path.endsWith('/info')) {
        return (
          status: 200,
          body: {
            'api_version': 1,
            'server_id': 'packs',
            'capabilities': [
              'image_packs',
              'typed_roots',
              if (precise) 'root_scan_progress',
              if (scoped) 'scoped_scans',
            ],
          },
        );
      }
      if (request.uri.path.endsWith('/roots')) {
        return (
          status: 200,
          body: {
            'items': [
              for (final r in scanRoots)
                {
                  'id': r.id,
                  'name': r.name,
                  'path': r.path,
                  'kind': r.kind.name,
                  'directory_id': 'dir-${r.id}',
                  'available': true,
                  'enabled': true,
                  'last_scan': 1710000000,
                },
            ],
          },
        );
      }
      if (request.uri.path.endsWith('/library-state')) {
        return (status: 200, body: state);
      }
      if (request.uri.path.endsWith('/scans')) {
        if (entered != null) {
          entered!.complete();
          await release!.future;
        }
        if (fail) {
          return (
            status: 503,
            body: {
              'error': {'code': 'service_busy', 'message': '请稍后重试'},
            },
          );
        }
        (state['roots'] as List)[1]['queued_task_ids'] = ['queued-A'];
        return (status: 202, body: {'id': 'queued-A'});
      }
      return null;
    };
    await fixture.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
  });
  tearDown(() async {
    if (release != null && !release!.isCompleted) release!.complete();
    if (!disposed) repo.dispose();
    await fixture.server.close(force: true);
  });
  Future<void> connect() =>
      repo.connect('http://127.0.0.1', fixture.server.port, 'secret');

  test('scoped POST names only the selected root and polls without replacing other facts', () async {
    await connect();
    fixture.writes.clear();
    final before = repo.libraryPreparation.value.rootProgress('B').scan;
    await repo.requestRootScan('A');
    expect(fixture.writes, hasLength(1));
    expect(fixture.writes.single.path, '/api/v1/scans');
    expect(fixture.writes.single.body, {'root_id': 'A'});
    expect(repo.libraryPreparation.value.rootProgress('A').queued, true);
    expect(repo.libraryPreparation.value.rootProgress('B').scan, before);
  });
  for (final flags in [(false, false), (false, true), (true, false)]) {
    test(
      'missing capability $flags sends no POST and never falls back to all',
      () async {
        precise = flags.$1;
        scoped = flags.$2;
        await connect();
        fixture.writes.clear();
        await expectLater(
          repo.requestRootScan('A'),
          throwsA(isA<LibraryFailure>()),
        );
        expect(fixture.writes, isEmpty);
      },
    );
  }
  test(
    'rejected submission preserves progress and is not retried as all',
    () async {
      await connect();
      fixture.writes.clear();
      final before = repo.libraryPreparation.value;
      fail = true;
      await expectLater(repo.requestRootScan('A'), throwsA(isA<ApiFailure>()));
      expect(fixture.writes, hasLength(1));
      expect(fixture.writes.single.path, '/api/v1/scans');
      expect(fixture.writes.single.body, {'root_id': 'A'});
      expect(identical(repo.libraryPreparation.value, before), true);
    },
  );
  test(
    'closing a connection rejects the late accepted response without polling',
    () async {
      await connect();
      entered = Completer();
      release = Completer();
      final work = repo.requestRootScan('A');
      await entered!.future;
      final reads = fixture.reads.length;
      repo.dispose();
      disposed = true;
      release!.complete();
      await expectLater(work, throwsA(isA<RequestCancelled>()));
      expect(fixture.reads.length, reads);
    },
  );
}
