import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_reading_session.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_reading_test.dart' show ReadingServer;

void main() {
  late ReadingServer server;
  late ServerLibraryRepository repo;
  late PackReadingSession session;
  setUp(() async {
    server = ReadingServer();
    await server.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await repo.connect(
      'http://127.0.0.1',
      server.fixture.server.port,
      'fixture',
    );
    session = PackReadingSession(
      repo,
      PackReadingEntry(PackQuery(), anchorId: 'p5'),
    );
    expect(await session.start(), isTrue);
  });
  tearDown(() async {
    session.dispose();
    repo.dispose();
    if (server.release?.isCompleted == false) server.release!.complete();
    await server.fixture.server.close(force: true);
  });
  Future<void> until(bool Function() ready) async {
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (!ready()) {
      if (DateTime.now().isAfter(end)) {
        fail('Read did not start: ${session.error}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  int reads() =>
      server.fixture.reads.where((u) => u.path.endsWith('/entries')).length;
  void hold() {
    server.blockKind = 'queue';
    server.blocked = Completer<void>();
    server.release = Completer<void>();
  }

  Future<Object> outcome(Future<ReaderQueuePage> work) =>
      work.then<Object>((p) => p, onError: (Object e, StackTrace _) => e);

  test('independent queue consumers do not cancel each other', () async {
    final reader = repo.createPackReader();
    addTearDown(reader.dispose);
    hold();
    final first = outcome(reader.queue('reading', limit: 120));
    await until(() => reads() == 1);
    final second = outcome(reader.queue('reading', limit: 40));
    await until(() => reads() == 2);
    server.release!.complete();
    expect(await first, isA<ReaderQueuePage>());
    expect(await second, isA<ReaderQueuePage>());
  });

  test('previous lookup survives concurrent background refresh and skips all locally removed neighbours', () async {
    hold();
    session.excludePacks({'p4'});
    await until(() => reads() == 1);
    final previous = session.findNeighbor(-1);
    await until(() => reads() == 2);
    session.excludePacks({'p4', 'p3'});
    final overview = session.loadQueue();
    await until(() => reads() == 3);
    server.release!.complete();
    expect((await previous)?.packId, 'p2');
    await overview;
    expect(session.error, isEmpty);
    expect(await session.move('p2'), isTrue);
    expect(session.range!.id, 'reading');
  });

  test(
    'explicit queue cancellation still interrupts every outstanding consumer',
    () async {
      final reader = repo.createPackReader();
      addTearDown(reader.dispose);
      hold();
      final first = outcome(reader.queue('reading', limit: 120));
      await until(() => reads() == 1);
      final second = outcome(reader.queue('reading', limit: 40));
      await until(() => reads() == 2);
      reader.cancelQueue();
      expect(await first, isA<RequestCancelled>());
      expect(await second, isA<RequestCancelled>());
      server.release!.complete();
    },
  );
  test(
    'a cancelled lookup cannot finish the range or change its current pack',
    () async {
      hold();
      session.excludePacks({'p4'});
      await until(() => reads() == 1);
      final previous = session.findNeighbor(-1);
      await until(() => reads() == 2);
      session.reader.cancelQueue();
      expect(await previous, isNull);
      expect(session.error, '本次切换未完成，请重试');
      expect(session.range!.pack!.id, 'p5');
      expect(
        server.fixture.writes.where((r) => r.path.endsWith('/position')),
        isEmpty,
      );
      server.release!.complete();
      expect((await session.findNeighbor(-1))?.packId, 'p3');
      expect(session.error, isEmpty);
    },
  );

  test('a late old lookup cannot overwrite a newer pack position', () async {
    hold();
    session.excludePacks({'p4'});
    await until(() => reads() == 1);
    final previous = session.findNeighbor(-1);
    await until(() => reads() == 2);
    expect(await session.move('p7'), isTrue);
    expect(await previous, isNull);
    expect(session.range!.pack!.id, 'p7');
    expect(session.error, isEmpty);
    server.release!.complete();
  });
}
