import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/library/browse_context.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;
import 'server_pack_reading_test.dart' show ReadingServer;

void main() {
  test('pack source/order is canonical across catalog, return and frozen reading entry', () {
    final library = PackQuery(
      search: '合集',
      folder: '/packs',
      tags: {'b', 'a'},
      sort: PackSort.newest,
    );
    final recent = PackBrowseContext(
      query: library,
      source: BrowseSource.recent,
    );
    expect(recent.query.source, BrowseSource.recent);
    expect(recent.query.sort, PackSort.recent);
    expect(recent.query.search, '合集');
    expect(recent.query.tags, {'a', 'b'});
    expect(recent.copyWith(scrollAnchor: 'p26').queryKey, recent.queryKey);
    final reading = PackReadingEntry(recent.query, anchorId: 'p26');
    expect(reading.source, recent.source);
    expect(reading.query.queryKey, recent.query.queryKey);
    expect(PackBrowseContext(query: recent.query).source, BrowseSource.recent);
    expect(
      recent.copyWith(source: BrowseSource.tags).query.sort,
      PackSort.name,
    );
    expect(library.source, BrowseSource.library);
    expect(library.sort, PackSort.newest);
    expect(library.copy(source: BrowseSource.tags).sort, PackSort.newest);
    expect(() => PackQuery(sort: PackSort.recent), throwsArgumentError);
    expect(
      PackReadingEntry(library, source: BrowseSource.recent).query.sort,
      PackSort.recent,
    );
    expect(recent.query.copy(search: '').source, BrowseSource.recent);
  });

  test('recent list, location, complete selection and reading send the identical source/order/filters', () async {
    final server = ReadingServer();
    await server.start();
    final repo = ServerLibraryRepository(MemoryCredentialStore());
    addTearDown(() async {
      repo.dispose();
      await server.fixture.server.close(force: true);
    });
    await repo.connect(
      'http://127.0.0.1',
      server.fixture.server.port,
      'fixture',
    );
    final reader = repo.createPackReader();
    addTearDown(reader.dispose);
    for (final sort in [PackSort.recent, PackSort.name, PackSort.newest]) {
      final query = PackQuery(
        source: BrowseSource.recent,
        sort: sort,
        folder: '/packs',
        search: '合集',
        tags: {'b', 'a'},
        readState: PackReadState.reading,
      );
      await repo.loadPacks(query, offset: 24, limit: 7);
      final list = server.fixture.reads.last;
      await repo.restorePackEntry(
        query,
        anchors: ['p58', 'p59'],
        fallbackIndex: 58,
      );
      final location = server.fixture.reads.last;
      expect((await repo.selectPackIds(query)).length, 1027);
      final selection = server.fixture.reads.last;
      await reader.submit(
        CreatePackReading(
          'recent-${sort.name}',
          PackReadingEntry(query, anchorId: 'p0'),
        ),
      );
      final body = server.fixture.writes.last.body;
      for (final uri in [list, location, selection]) {
        expect(uri.queryParameters['source'], 'recent');
        expect(uri.queryParameters['sort'], sort.name);
        expect(uri.queryParameters['search'], '合集');
        expect(uri.queryParameters['directory_id'], 'pack-directory');
        expect(uri.queryParameters['read_state'], 'reading');
        expect(uri.queryParametersAll['tag_ids'], ['a', 'b']);
      }
      expect(list.queryParameters['offset'], '24');
      expect(location.queryParametersAll['anchor_ids'], ['p58', 'p59']);
      expect(body['source'], 'recent');
      expect(body['sort'], sort.name);
      expect(body['scope'], {
        'directory_id': 'pack-directory',
        'search': '合集',
        'tag_ids': ['a', 'b'],
        'read_state': 'reading',
      });
      expect(body['anchor_pack_id'], 'p0');
    }
    expect(
      server.fixture.writes,
      hasLength(3),
      reason: 'catalog, selection and location never confirm opened',
    );
    server.overrideKind = 'session';
    server.replyOverride = {
      ...server.range(),
      'source': {'kind': 'recent', 'sort': 'name'},
    };
    await expectLater(
      reader.submit(
        CreatePackReading(
          'wrong-order',
          PackReadingEntry(PackQuery(source: BrowseSource.recent)),
        ),
      ),
      throwsA(isA<LibraryFailure>()),
    );
  });

  test('old pack service rejects recent reads and selections before issuing any whole-library request', () async {
    final fixture = PackServer();
    await fixture.start();
    final repo = ServerLibraryRepository(MemoryCredentialStore());
    addTearDown(() async {
      repo.dispose();
      await fixture.server.close(force: true);
    });
    await repo.connect('http://127.0.0.1', fixture.server.port, 'fixture');
    fixture.reads.clear();
    final query = PackQuery(source: BrowseSource.recent);
    await expectLater(repo.loadPacks(query), throwsA(isA<LibraryFailure>()));
    await expectLater(
      repo.restorePackEntry(query, anchors: ['p0'], fallbackIndex: 0),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(
      repo.selectPackIds(query),
      throwsA(isA<LibraryFailure>()),
    );
    expect(fixture.reads, isEmpty);
    expect(fixture.writes, isEmpty);
    expect((await repo.loadPacks(PackQuery())).total, 51);
    expect(fixture.reads.single.queryParameters['source'], 'library');
  });
  test('catalog resume index is optional for old payloads but malformed positions cannot be shown', () async {
    final fixture = PackServer();
    await fixture.start();
    final repo = ServerLibraryRepository(MemoryCredentialStore());
    addTearDown(() async {
      repo.dispose();
      await fixture.server.close(force: true);
    });
    await repo.connect('http://127.0.0.1', fixture.server.port, 'fixture');
    expect(
      (await repo.loadPacks(PackQuery())).items.single.progress!.pageIndex,
      1,
    );
    Object? position;
    fixture.handle = (request, _) {
      if (!request.uri.path.endsWith('/packs')) return null;
      final pack = fixture.pack(0);
      final progress = Map<String, dynamic>.from(pack['progress']);
      progress.remove('page_index');
      if (position != null) progress['page_index'] = position;
      return (
        status: 200,
        body: {
          'items': [
            {...pack, 'progress': progress},
          ],
          'total': 1,
          'offset': 0,
          'limit': 24,
        },
      );
    };
    expect(
      (await repo.loadPacks(PackQuery())).items.single.progress!.pageIndex,
      isNull,
    );
    for (final bad in [-1, 500, 1.5, '1']) {
      position = bad;
      await expectLater(
        repo.loadPacks(PackQuery()),
        throwsA(isA<LibraryFailure>()),
      );
    }
  });
}
