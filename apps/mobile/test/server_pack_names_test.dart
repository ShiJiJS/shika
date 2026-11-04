import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

void main() {
  late PackServer fixture;
  late ServerLibraryRepository repo;
  setUp(() async {
    fixture = PackServer();
    await fixture.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await repo.connect('http://127.0.0.1', fixture.server.port, 'fixture');
  });
  tearDown(() async {
    if (fixture.namesRelease?.isCompleted == false) {
      fixture.namesRelease!.complete();
    }
    repo.dispose();
    await fixture.server.close(force: true);
  });

  test('card names are authoritative and exact selected IDs resolve beyond first 50 in bounded batches', () async {
    final pack = (await repo.loadPacks(PackQuery())).items.single;
    expect(pack.tagNames, {'same-id': '同名', 'keep': '保留'});
    fixture.packTags.addAll({for (var i = 0; i < 300; i++) 't$i': '标签$i'});
    final ids = {for (var i = 0; i < 300; i++) 't$i', 'gone'};
    final result = await repo.resolvePackTags(ids);
    expect(result.names.length, 300);
    expect(result.names['t299'], '标签299');
    expect(result.missing, {'gone'});
    final reads = fixture.reads
        .where((u) => u.path.endsWith('/pack-tags/resolve'))
        .toList();
    expect(reads.map((u) => u.queryParametersAll['tag_ids']!.length), [
      256,
      45,
    ]);
    expect(
      reads.every((u) => !u.queryParameters.containsKey('offset')),
      isTrue,
    );
    expect(fixture.writes, isEmpty);
  });

  test('name lookup is independent of tag list paging and cannot publish after reconnection', () async {
    fixture.namesBlocked = Completer();
    fixture.namesRelease = Completer();
    final old = repo.resolvePackTags({'same-id'});
    final rejected = expectLater(old, throwsA(isA<RequestCancelled>()));
    await fixture.namesBlocked!.future;
    await repo.loadPackTags();
    repo.cancelPackTagRead();
    expect(fixture.namesRelease!.isCompleted, isFalse);
    final other = PackServer()..packTags['same-id'] = '另一服务的名称';
    await other.start();
    try {
      await repo.connect('http://127.0.0.1', other.server.port, 'fixture');
      fixture.namesRelease!.complete();
      await rejected;
      expect((await repo.resolvePackTags({'same-id'})).names, {
        'same-id': '另一服务的名称',
      });
    } finally {
      await other.server.close(force: true);
    }
  });

  test('malformed or incomplete lookup and advertised incomplete summary names are rejected', () async {
    for (final response in [
      {'kind': 'pack', 'items': null, 'missing_ids': []},
      {
        'kind': 'pack',
        'items': ['bad-shape'],
        'missing_ids': [],
      },
      {
        'kind': 'video',
        'items': [],
        'missing_ids': ['same-id'],
      },
      {'kind': 'pack', 'items': [], 'missing_ids': []},
      {
        'kind': 'pack',
        'items': [
          {'id': 'same-id', 'name': '错误类型', 'kind': 'video'},
        ],
        'missing_ids': [],
      },
      {
        'kind': 'pack',
        'items': [
          {'id': 'same-id', 'name': '重复', 'kind': 'pack'},
        ],
        'missing_ids': ['same-id'],
      },
    ]) {
      fixture.namesOverride = response;
      await expectLater(
        repo.resolvePackTags({'same-id'}),
        throwsA(isA<LibraryFailure>()),
      );
    }
    fixture.incompletePackNames = true;
    await expectLater(
      repo.loadPacks(PackQuery()),
      throwsA(isA<LibraryFailure>()),
    );
  });

  test('unauthorized name lookups expire the shared connection', () async {
    fixture.unauthorized = true;
    await expectLater(
      repo.resolvePackTags({'same-id'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(repo.snapshot.connected, isFalse);
  });
}
