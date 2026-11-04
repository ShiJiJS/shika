import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

void main() {
  late PackServer fixture;
  late ServerLibraryRepository repo;
  bool supported = true, fail = false;
  Object? videos = 270, packs = 730;
  Completer<void>? entered, release;
  Map<String, dynamic> state() => {
    'ready': true,
    'scanning': false,
    'media': {
      'video': {'indexed': videos},
      'pack': {'indexed': packs},
    },
  };
  setUp(() async {
    supported = true;
    fail = false;
    videos = 270;
    packs = 730;
    entered = release = null;
    fixture = PackServer();
    fixture.handle = (request, _) async {
      if (request.uri.path.endsWith('/info')) {
        return (
          status: 200,
          body: {
            'api_version': 1,
            'server_id': 'packs',
            'capabilities': [
              'image_packs',
              'typed_roots',
              'pack_tags',
              if (supported) 'media_catalog_counts',
            ],
          },
        );
      }
      if (request.uri.path.endsWith('/library-state')) {
        final body = state(), status = fail ? 503 : 200;
        final ready = entered, done = release;
        if (ready != null && !ready.isCompleted) {
          ready.complete();
          await done!.future;
        }
        return (status: status, body: body);
      }
      if (request.uri.path.endsWith('/scans')) {
        return (status: 202, body: {'id': 'scan'});
      }
      return null;
    };
    await fixture.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
  });
  tearDown(() async {
    if (release != null && !release!.isCompleted) release!.complete();
    repo.dispose();
    await fixture.server.close(force: true);
  });
  Future<void> connect() =>
      repo.connect('http://127.0.0.1', fixture.server.port, 'secret');

  test(
    'initial totals are unfiltered, not visited pages; retry is GET-only',
    () async {
      await connect();
      expect(repo.catalogCounts.value, const MediaCatalogCounts(270, 730));
      expect(repo.snapshot.videos.length, lessThan(270));
      await repo.loadPacks(PackQuery(search: 'one'), limit: 1);
      expect(repo.catalogCounts.value, const MediaCatalogCounts(270, 730));
      final writes = fixture.writes.length;
      final read = fixture.reads.length;
      videos = 0;
      packs = 0;
      await repo.refreshCatalogCounts();
      expect(repo.catalogCounts.value, const MediaCatalogCounts(0, 0));
      expect(fixture.writes.length, writes);
      expect(fixture.reads.skip(read).map((u) => u.path), [
        '/api/v1/library-state',
      ]);
    },
  );

  test(
    'legacy capability ignores old counters and performs no extra request',
    () async {
      supported = false;
      await connect();
      expect(repo.catalogCounts.value, isNull);
      final reads = fixture.reads.length;
      await repo.refreshCatalogCounts();
      expect(fixture.reads.length, reads);
    },
  );

  test(
    'failures and malformed totals remain unknown without disconnecting',
    () async {
      await connect();
      for (final invalid in [null, -1, 1.5, '730']) {
        packs = invalid;
        await repo.refreshCatalogCounts();
        expect(repo.catalogCounts.value, isNull);
        expect(repo.snapshot.connected, isTrue);
      }
      packs = 9;
      fail = true;
      await repo.refreshCatalogCounts();
      expect(repo.catalogCounts.value, isNull);
      fail = false;
      await repo.refreshCatalogCounts();
      expect(repo.catalogCounts.value, const MediaCatalogCounts(270, 9));
    },
  );

  test(
    'newer totals and a new connection reject a held older response',
    () async {
      await connect();
      entered = Completer();
      release = Completer();
      final first = repo.refreshCatalogCounts();
      await entered!.future;
      packs = 8;
      await repo.refreshCatalogCounts();
      release!.complete();
      await first;
      expect(repo.catalogCounts.value, const MediaCatalogCounts(270, 8));
      entered = Completer();
      release = Completer();
      final stale = repo.refreshCatalogCounts();
      await entered!.future;
      packs = 3;
      await connect();
      release!.complete();
      await stale;
      expect(repo.catalogCounts.value, const MediaCatalogCounts(270, 3));
    },
  );

  test('totals do not cancel catalog paging and mutations re-read without scanning', () async {
    await connect();
    fixture.blocked = Completer();
    fixture.release = Completer();
    final page = repo.loadPacks(PackQuery(search: 'blocked'));
    await fixture.blocked!.future;
    await repo.refreshCatalogCounts();
    fixture.release!.complete();
    expect((await page).total, 51);
    final read = fixture.reads.length, writes = fixture.writes.length;
    packs = 729;
    final done = Completer<void>();
    void changed() {
      if (repo.catalogCounts.value?.packs == 729 && !done.isCompleted) {
        done.complete();
      }
    }

    repo.catalogCounts.addListener(changed);
    repo.packFilesChanged();
    expect(repo.catalogCounts.value, isNull);
    await done.future.timeout(const Duration(seconds: 5));
    repo.catalogCounts.removeListener(changed);
    expect(fixture.writes.length, writes);
    expect(fixture.reads.skip(read).map((u) => u.path), [
      '/api/v1/library-state',
    ]);
  });

  test(
    'normal scan-state polling updates the same total without extra reads',
    () async {
      await connect();
      videos = 281;
      packs = 741;
      final read = fixture.reads.length;
      await repo.requestScan();
      expect(repo.catalogCounts.value, const MediaCatalogCounts(281, 741));
      expect(fixture.reads.skip(read).map((u) => u.path), [
        '/api/v1/library-state',
      ]);
    },
  );
}
