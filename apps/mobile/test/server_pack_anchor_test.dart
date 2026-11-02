import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';

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
    repo.dispose();
    await fixture.server.close(force: true);
  });
  Future<CatalogPage<LibraryPack>> restore() => repo.restorePackEntry(
    PackQuery(
      folder: '/packs',
      search: '套图',
      tags: {'b', 'a'},
      readState: PackReadState.unread,
      sort: PackSort.newest,
    ),
    anchors: ['p58', 'p59', 'p57'],
    fallbackIndex: 58,
  );
  test('restore preserves the full pack query and preferred IDs and returns a localized window', () async {
    final playback = repo.playbackIdentity;
    final page = await restore();
    expect(page.offset, 48);
    expect(page.items.length, 24);
    expect(page.anchorIndex, 58);
    expect(page.items[10].id, 'p58');
    final read = fixture.reads.last;
    expect(read.queryParametersAll['anchor_ids'], ['p58', 'p59', 'p57']);
    expect(read.queryParametersAll['tag_ids'], ['a', 'b']);
    expect(read.queryParameters['directory_id'], 'pack-directory');
    expect(read.queryParameters['read_state'], 'unread');
    expect(read.queryParameters['search'], '套图');
    expect(read.queryParameters['sort'], 'newest');
    expect(read.queryParameters['offset'], '58');
    expect(repo.playbackIdentity, playback);
    expect(fixture.writes, isEmpty);
  });
  test('failed location never expands directory or drops filter and malformed anchor positions are rejected', () async {
    fixture.unavailableDirectory = true;
    await expectLater(restore(), throwsA(isA<LibraryFailure>()));
    expect(fixture.reads.last.path, '/api/v1/directories/resolve');
    fixture.unavailableDirectory = false;
    for (final index in [null, -1, 73, 24]) {
      fixture.anchorOverride = {
        'items': [fixture.pack(48)],
        'total': 73,
        'offset': 48,
        'limit': 24,
        'anchor_index': index,
      };
      await expectLater(restore(), throwsA(isA<LibraryFailure>()));
    }
    expect(fixture.writes, isEmpty);
  });
}
