import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

void main() {
  late PackServer server;
  late ServerLibraryRepository repo;
  setUp(() async {
    server = PackServer()..readingSupported = true;
    await server.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await repo.connect('http://127.0.0.1', server.server.port, 'fixture');
  });
  tearDown(() async {
    repo.dispose();
    await server.server.close(force: true);
  });

  Map<String, dynamic> latest({int total = 1, int index = 99}) => {
    'items': [if (total > 0) server.pack(index)],
    'total': total,
    'offset': 0,
    'limit': 1,
  };
  bool summary(Uri uri) =>
      uri.path.endsWith('/packs') && uri.queryParameters['source'] == 'recent';

  test('summary uses authoritative latest opened pack, not catalog cache; GET only', () async {
    server.handle = (request, _) {
      if (!summary(request.uri)) return null;
      expect(request.uri.queryParameters, containsPair('limit', '1'));
      expect(request.uri.queryParameters, containsPair('sort', 'recent'));
      expect(request.uri.queryParameters, containsPair('read_state', 'all'));
      expect(
        request.uri.queryParametersAll.containsKey('directory_id'),
        isFalse,
      );
      expect(request.uri.queryParametersAll.containsKey('tag_ids'), isFalse);
      return (status: 200, body: latest());
    };
    await repo.loadPacks(PackQuery(), limit: 24);
    final pack = await repo.loadPackContinuation();
    expect(pack!.id, 'p99');
    expect(pack.progress!.pageIndex, 1);
    expect(pack.progress!.revision, 4);
    expect(pack.progress!.offsetRatio, .3);
    expect(server.writes, isEmpty);
    server.handle = (r, _) =>
        summary(r.uri) ? (status: 200, body: latest(total: 0)) : null;
    expect(await repo.loadPackContinuation(), isNull);
  });

  test(
    'catalog refresh/cancellation cannot cancel a held continuation',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      server.handle = (r, _) async {
        if (!summary(r.uri)) return null;
        started.complete();
        await release.future;
        return (status: 200, body: latest());
      };
      final continuation = repo.loadPackContinuation();
      await started.future;
      expect(
        (await repo.loadPacks(PackQuery(search: 'other'))).items.single.id,
        'p0',
      );
      repo.cancelPackRead();
      release.complete();
      expect((await continuation)!.id, 'p99');
    },
  );

  test('continuation refresh cannot cancel held catalog pagination', () async {
    server.blocked = Completer<void>();
    server.release = Completer<void>();
    addTearDown(() {
      if (!server.release!.isCompleted) server.release!.complete();
    });
    server.handle = (r, _) =>
        summary(r.uri) ? (status: 200, body: latest()) : null;
    final page = repo.loadPacks(PackQuery(search: 'blocked'), offset: 24);
    await server.blocked!.future;
    expect((await repo.loadPackContinuation())!.id, 'p99');
    server.release!.complete();
    expect((await page).items.single.id, 'p24');
  });

  test(
    'a newer summary and connection lifetime invalidate old responses',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var reads = 0;
      server.handle = (r, _) async {
        if (!summary(r.uri)) return null;
        if (++reads == 1) {
          started.complete();
          await release.future;
        }
        return (status: 200, body: latest(index: reads));
      };
      final first = repo.loadPackContinuation();
      final cancelled = expectLater(first, throwsA(isA<RequestCancelled>()));
      await started.future;
      expect((await repo.loadPackContinuation())!.id, 'p2');
      release.complete();
      await cancelled;
      final held = Completer<void>(), finish = Completer<void>();
      addTearDown(() {
        if (!finish.isCompleted) finish.complete();
      });
      server.handle = (r, _) async {
        if (!summary(r.uri)) return null;
        held.complete();
        await finish.future;
        return (status: 200, body: latest());
      };
      final old = repo.loadPackContinuation();
      final invalid = expectLater(old, throwsA(isA<RequestCancelled>()));
      await held.future;
      await repo.connect('http://127.0.0.1', server.server.port, 'fixture');
      finish.complete();
      await invalid;
    },
  );

  test(
    'old reading capability and failed/incomplete summaries do not widen scope',
    () async {
      server.readingSupported = false;
      await repo.connect('http://127.0.0.1', server.server.port, 'fixture');
      final before = server.reads.length;
      await expectLater(
        repo.loadPackContinuation(),
        throwsA(isA<LibraryFailure>()),
      );
      expect(server.reads.length, before);
      server.readingSupported = true;
      await repo.connect('http://127.0.0.1', server.server.port, 'fixture');
      server.handle = (r, _) => summary(r.uri)
          ? (
              status: 503,
              body: {
                'error': {'code': 'unavailable', 'message': '摘要暂不可用'},
              },
            )
          : null;
      await expectLater(
        repo.loadPackContinuation(),
        throwsA(isA<LibraryFailure>()),
      );
      server.handle = (r, _) => summary(r.uri)
          ? (
              status: 200,
              body: {'items': [], 'total': 1, 'offset': 0, 'limit': 1},
            )
          : null;
      await expectLater(
        repo.loadPackContinuation(),
        throwsA(isA<LibraryFailure>()),
      );
      server.handle = (r, _) =>
          summary(r.uri) ? (status: 200, body: latest()) : null;
      expect((await repo.loadPackContinuation())!.id, 'p99');
      expect(server.writes, isEmpty);
    },
  );
}
