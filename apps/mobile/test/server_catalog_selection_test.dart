import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
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
    if (fixture.selectionRelease?.isCompleted == false) {
      fixture.selectionRelease!.complete();
    }
    if (fixture.writeRelease?.isCompleted == false) {
      fixture.writeRelease!.complete();
    }
    repo.dispose();
    await fixture.server.close(force: true);
  });

  test(
    'full ID snapshots preserve typed filters and do not open playback',
    () async {
      final entry = VideoEntryScope(
        query: VideoQuery(
          tags: {'b', 'a'},
          orientation: 'portrait',
          duration: 'short',
          type: 'MP4',
        ),
        search: '名字',
        source: BrowseSource.tags,
        sort: VideoSort.newest,
      );
      expect(await repo.selectVideoIds(entry), hasLength(1027));
      final read = fixture.reads.last;
      expect(read.path, '/api/v1/videos/selection');
      expect(read.queryParametersAll['tag_ids'], ['a', 'b']);
      expect(read.queryParameters['orientation'], 'portrait');
      expect(read.queryParameters['duration'], 'short');
      expect(read.queryParameters['source'], 'tags');
      expect(read.queryParameters['search'], '名字');
      expect(
        await repo.selectPackIds(
          PackQuery(
            folder: '/packs',
            tags: {'same-id'},
            readState: PackReadState.unread,
          ),
        ),
        hasLength(1027),
      );
      expect(
        fixture.reads.last.queryParameters['directory_id'],
        'pack-directory',
      );
      expect(fixture.reads.last.queryParameters['read_state'], 'unread');
      expect(fixture.writes, isEmpty);
    },
  );

  test(
    'partial, duplicate or wrong-kind membership never becomes all selected',
    () async {
      for (final response in [
        {
          'kind': 'video',
          'ids': ['a'],
          'total': 2,
        },
        {
          'kind': 'video',
          'ids': ['a', 'a'],
          'total': 2,
        },
        {
          'kind': 'pack',
          'ids': ['a'],
          'total': 1,
        },
      ]) {
        fixture.selectionOverride = response;
        await expectLater(
          repo.selectVideoIds(VideoEntryScope()),
          throwsA(isA<LibraryFailure>()),
        );
      }
    },
  );

  test('selection cancellation is independent of media reads and late membership is rejected', () async {
    fixture.selectionBlocked = Completer();
    fixture.selectionRelease = Completer();
    final old = repo.selectVideoIds(VideoEntryScope(search: 'blocked'));
    final rejected = expectLater(old, throwsA(isA<RequestCancelled>()));
    await fixture.selectionBlocked!.future;
    await repo.loadPacks(PackQuery());
    expect(fixture.selectionRelease!.isCompleted, isFalse);
    repo.cancelVideoSelection();
    await rejected;
    fixture.selectionRelease!.complete();
    expect(await repo.selectVideoIds(VideoEntryScope()), hasLength(1027));
  });

  test('more than 1000 pack assignments retain idempotency across a lost second receipt', () async {
    final ids = {for (var i = 0; i < 1027; i++) 'p$i'};
    fixture.loseWriteAt = 2;
    await expectLater(
      repo.setPackTags(ids, {'added'}),
      throwsA(
        isA<LibraryFailure>().having(
          (e) => e.message,
          'confirmed count',
          contains('1000/1027'),
        ),
      ),
    );
    expect(fixture.writes.map((w) => (w.body['pack_ids'] as List).length), [
      1000,
      27,
    ]);
    final lostKey = fixture.writes.last.body['request_id'];
    await repo.setPackTags(ids, {'added'});
    expect(fixture.writes.last.body['request_id'], lostKey);
    expect(fixture.writes.every((w) => w.body['mode'] == 'add'), isTrue);
    expect(fixture.links, containsAll(['same-id', 'keep', 'added']));
  });

  test(
    'reconnection cannot send a later tag chunk to a different service',
    () async {
      final other = PackServer();
      await other.start();
      fixture.writeBlocked = Completer();
      fixture.writeRelease = Completer();
      try {
        final pending = repo.setPackTags(
          {for (var i = 0; i < 1027; i++) 'p$i'},
          {'added'},
        );
        final rejected = expectLater(pending, throwsA(isA<LibraryFailure>()));
        await fixture.writeBlocked!.future;
        await repo.connect('http://127.0.0.1', other.server.port, 'fixture');
        fixture.writeRelease!.complete();
        await rejected;
        expect(
          fixture.writes.where((w) => w.path == '/api/v1/pack-tag-links'),
          hasLength(1),
        );
        expect(other.writes, isEmpty);
        expect(repo.snapshot.connected, isTrue);
      } finally {
        await other.server.close(force: true);
      }
    },
  );

  test('more than 1000 video assignments use bounded stable chunks', () async {
    final ids = {for (var i = 0; i < 1027; i++) 'v$i'};
    await repo.setVideoTags(ids, {'same-id'});
    final writes = fixture.writes
        .where((w) => w.path == '/api/v1/video-tags')
        .toList();
    expect(writes.map((w) => (w.body['video_ids'] as List).length), [1000, 27]);
    expect(
      writes
          .expand((w) => (w.body['video_ids'] as List).cast<String>())
          .toSet(),
      ids,
    );
  });
}
