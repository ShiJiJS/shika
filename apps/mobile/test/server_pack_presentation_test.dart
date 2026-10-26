import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/pack_reading.dart';
import 'package:video_viewer/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;
import 'server_pack_reading_test.dart' show ReadingServer;

class PresentedPacks extends PackServer {
  bool presentation = true;
  Object? title = '夏日祭', author = '作者甲', number = '034';
  @override
  Map<String, dynamic> pack(int index) => {
    ...super.pack(index),
    if (presentation) ...{'title': title, 'author': author, 'number': number},
  };
}

Map<String, dynamic> info(bool modern) => {
  'api_version': 1,
  'server_id': 'packs',
  'capabilities': [
    'image_packs',
    'typed_roots',
    'pack_tags',
    'catalog_selection',
    'pack_entry_anchors',
    'pack_reading_sessions',
    if (modern) 'pack_presentation',
  ],
};

void main() {
  for (final modern in [true, false]) {
    test(
      'presentation=$modern preserves identity and sends one consistent wire sort',
      () async {
        final server = PresentedPacks()..presentation = modern;
        server.handle = (r, _) => r.uri.path.endsWith('/info')
            ? (status: 200, body: info(modern))
            : null;
        await server.start();
        final repo = ServerLibraryRepository(MemoryCredentialStore());
        addTearDown(() async {
          repo.dispose();
          await server.server.close(force: true);
        });
        await repo.connect('http://127.0.0.1', server.server.port, 'fixture');
        final query = PackQuery(search: '套图', source: BrowseSource.tags);
        final page = await repo.loadPacks(query);
        final pack = page.items.first;
        expect(pack.name, '套图0');
        expect(pack.path, '/packs/套图0');
        expect(pack.id, 'p0');
        expect(pack.displayTitle, modern ? '夏日祭' : '套图0');
        expect(pack.catalogSubtitle, modern ? '作者甲' : '499 张可读');
        expect(pack.readerSubtitle, modern ? '作者甲 · 034' : '');
        await repo.selectPackIds(query);
        await repo.restorePackEntry(query, anchors: ['p25'], fallbackIndex: 25);
        final reads = server.reads.where(
          (r) => r.path.startsWith('/api/v1/packs'),
        );
        expect(reads.length, 3);
        expect(
          reads.every(
            (r) => r.queryParameters['sort'] == (modern ? 'title' : 'name'),
          ),
          isTrue,
        );
        expect(
          reads.every((r) => r.queryParameters['source'] == 'tags'),
          isTrue,
        );
        await repo.loadPacks(PackQuery(sort: PackSort.newest));
        expect(server.reads.last.queryParameters['sort'], 'newest');
        await repo.loadPackContinuation();
        expect(server.reads.last.queryParameters['sort'], 'recent');
      },
    );

    test(
      'reader presentation=$modern uses the same sort; existing name sessions still open',
      () async {
        final server = ReadingServer();
        await server.start();
        server.fixture.handle = (r, body) => r.uri.path.endsWith('/info')
            ? (status: 200, body: info(modern))
            : server.handle(r, body);
        final repo = ServerLibraryRepository(MemoryCredentialStore());
        await repo.connect(
          'http://127.0.0.1',
          server.fixture.server.port,
          'fixture',
        );
        final reader = repo.createPackReader();
        addTearDown(() async {
          reader.dispose();
          repo.dispose();
          await server.fixture.server.close(force: true);
        });
        final range = await reader.submit(
          CreatePackReading('title-create', PackReadingEntry(PackQuery())),
        );
        expect(range.candidateCount, 27);
        expect(
          server.fixture.writes.single.body['sort'],
          modern ? 'title' : 'name',
        );
        // Reading an existing fixed membership does not reinterpret its order.
        server.sort = 'name';
        final old = await reader.read(range.id);
        expect(old.id, range.id);
        expect(old.pack!.name, range.pack!.name);
        expect(old.candidateCount, 27);
      },
    );
  }

  test('optional invalid or empty presentation falls back without blocking the catalog', () async {
    final server = PresentedPacks();
    server.handle = (r, _) =>
        r.uri.path.endsWith('/info') ? (status: 200, body: info(true)) : null;
    await server.start();
    final repo = ServerLibraryRepository(MemoryCredentialStore());
    addTearDown(() async {
      repo.dispose();
      await server.server.close(force: true);
    });
    await repo.connect('http://127.0.0.1', server.server.port, 'fixture');
    for (final invalid in [null, '', 123, <String>[]]) {
      server.title = server.author = server.number = invalid;
      final pack = (await repo.loadPacks(PackQuery())).items.first;
      expect(pack.displayTitle, pack.name);
      expect(pack.catalogSubtitle, '499 张可读');
      expect(pack.readerSubtitle, '');
    }
  });
}
