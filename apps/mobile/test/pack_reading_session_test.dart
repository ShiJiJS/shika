import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_reading_session.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_reading_test.dart' show ReadingServer;
import 'server_pack_catalog_test.dart' show PackServer;

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
    var sequence = 0;
    session = PackReadingSession(
      repo,
      PackReadingEntry(PackQuery()),
      saveDelay: const Duration(days: 1),
      nonce: () => 'reader-${sequence++}',
    );
  });
  tearDown(() async {
    session.dispose();
    repo.dispose();
    if (server.release != null && !server.release!.isCompleted) {
      server.release!.complete();
    }
    await server.fixture.server.close(force: true);
  });
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out; ${session.error}; ${session.pageError}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> start() async {
    expect(await session.start(), isTrue);
    await until(() => !session.loadingPages);
  }

  void frame() {
    session.visibleFrame(
      session.index,
      session.currentPage!.id,
      session.packEpoch,
    );
  }

  for (final reason in ['page_removed', 'page_unreadable']) {
    test(
      'recovery notice survives opened acknowledgement and resets for the next pack: $reason',
      () async {
        final range = server.range();
        (range['resume'] as Map)['recovery_reason'] = reason;
        server.overrideKind = 'session';
        server.replyOverride = range;
        await start();
        expect(session.recoveryReason, reason);
        frame();
        await until(() => session.opened && !session.busy);
        // The server acknowledges recovery by clearing its durable marker.
        expect(session.recoveryReason, reason);
        server.replyOverride = null;
        expect(await session.move('p1'), isTrue);
        expect(session.recoveryReason, isNull);
      },
    );
  }

  test('prefetch never opens; only current displayed frames own progress and old frames are ignored', () async {
    await start();
    await session.ensure(40);
    expect(
      server.fixture.writes.where((r) => r.path.endsWith('/opened')),
      isEmpty,
    );
    session.visibleFrame(1, 'p0-page1', session.packEpoch);
    expect(session.opened, isFalse);
    session.show(0, ratio: .3);
    frame();
    await until(() => session.opened && !session.busy);
    expect(session.cursor!.progressRevision, 1);
    expect(
      server.fixture.writes.where((r) => r.path.endsWith('/opened')).length,
      1,
    );
    session.show(4, ratio: .37);
    frame();
    expect(await session.flush(), isTrue);
    final body = server.fixture.writes.last.body;
    expect(body['page_id'], 'p0-page4');
    expect(body['offset_ratio'], .37);
    expect(body['expected_revision'], 1);
    expect(session.unsaved, isFalse);
  });
  test('a later displayed image is not replaced by an earlier opened acknowledgement', () async {
    await start();
    server.blockKind = 'opened';
    server.blocked = Completer<void>();
    server.release = Completer<void>();
    session.show(0, ratio: .3);
    frame();
    await server.blocked!.future;
    session.show(4, ratio: .72);
    frame();
    server.release!.complete();
    await until(() => session.opened && !session.busy);
    expect(session.index, 4);
    expect(session.offsetRatio, .72);
    expect(session.unsaved, isTrue);
    expect(await session.flush(), isTrue);
    expect(server.fixture.writes.last.body['page_id'], 'p0-page4');
    expect(server.fixture.writes.last.body['offset_ratio'], .72);
  });
  test('uncertain writes query their original receipt and unknown results require explicit resend', () async {
    server.loseReply = true;
    expect(await session.start(), isFalse);
    expect(session.hasPending, isTrue);
    final key = server.fixture.writes.single.body['request_id'];
    final diagnostic = session.lastCommandFailure!;
    expect(diagnostic.kind, 'session');
    expect(diagnostic.requestId, key);
    expect(diagnostic.receiptLookup, isFalse);
    expect(diagnostic.failure.status, 503);
    server.receipts.remove('session:$key');
    final count = server.fixture.writes.length;
    expect(await session.checkPending(), isFalse);
    expect(session.canResend, isTrue);
    expect(session.lastCommandFailure, same(diagnostic));
    expect(server.fixture.writes.length, count);
    expect(await session.resendPending(), isTrue);
    expect(server.fixture.writes.last.body['request_id'], key);
    expect(session.lastCommandFailure, same(diagnostic));
    await until(() => !session.loadingPages);
    session.show(0, ratio: .3);
    server.loseReply = true;
    frame();
    await until(() => !session.busy && session.hasPending);
    final before = server.fixture.writes.length;
    expect(await session.checkPending(), isTrue);
    expect(session.opened, isTrue);
    expect(server.fixture.writes.length, before);
  });
  test('a closed connection retains its actual cause and failed lookup never permits resend', () async {
    await server.fixture.server.close(force: true);
    expect(await session.start(), isFalse);
    final original = session.lastCommandFailure!;
    expect(original.kind, 'session');
    expect(original.requestId, 'reader-0');
    expect(original.receiptLookup, isFalse);
    expect(original.failure.code, 'network_unavailable');
    // The API already has keep-alive sockets from connect(). A peer close may
    // be noticed before openUrl or while awaiting headers on a reused socket.
    expect(
      original.failure.transportPhase,
      isIn([ApiTransportPhase.opening, ApiTransportPhase.waitingForHeaders]),
    );
    expect(original.failure.transportCause, isA<IOException>());
    expect(session.error, original.failure.message);
    expect(session.error, isNot(contains('127.0.0.1')));
    expect(session.hasPending, isTrue);
    expect(session.canResend, isFalse);
    expect(await session.checkPending(), isFalse);
    final lookup = session.lastCommandFailure!;
    expect(lookup.requestId, original.requestId);
    expect(lookup.receiptLookup, isTrue);
    expect(lookup.failure.transportPhase, isNotNull);
    expect(lookup.failure.transportCause, isA<IOException>());
    expect(await session.resendPending(), isFalse);
    expect(server.fixture.writes, isEmpty);
  });
  test('manual pack changes flush first and late old-page frames cannot mark the next pack', () async {
    await start();
    session.show(0, ratio: .3);
    frame();
    await until(() => session.opened && !session.busy);
    session.show(4, ratio: .37);
    frame();
    final epoch = session.packEpoch;
    expect(await session.move('p1'), isTrue);
    final operations = server.fixture.writes.map((r) => r.path).toList();
    expect(operations[operations.length - 2], endsWith('/progress'));
    expect(operations.last, endsWith('/position'));
    expect(session.opened, isFalse);
    expect(session.cursor!.packId, 'p1');
    session.visibleFrame(4, 'p0-page4', epoch);
    expect(session.opened, isFalse);
    await until(() => !session.loadingPages);
    frame();
    await until(() => session.opened && !session.busy);
    expect(server.fixture.writes.last.body['pack_id'], 'p1');
  });
  test('metadata windows stay bounded and a replacement connection invalidates pending reading work', () async {
    await start();
    for (var i = 40; i < 500; i += 40) {
      session.show(i);
      await until(() => !session.loadingPages && session.currentPage != null);
      expect(
        session.pages.length,
        lessThanOrEqualTo(PackReadingSession.maximumPages),
      );
    }
    expect(session.windowStart, greaterThan(0));
    session.show(0);
    await until(() => !session.loadingPages && session.currentPage != null);
    expect(session.index, 0);
    expect(session.pages.length, lessThanOrEqualTo(120));
    final other = PackServer();
    await other.start();
    addTearDown(() => other.server.close(force: true));
    await repo.connect('http://127.0.0.1', other.server.port, 'fixture');
    expect(session.invalidated, isTrue);
    expect(session.pages, isEmpty);
    expect(await session.flush(), isFalse);
    expect(other.writes, isEmpty);
  });
  test('mode preferences retain the displayed page and ratio without widening the range', () async {
    await start();
    session.show(4, ratio: .37);
    frame();
    await until(() => session.opened && !session.busy);
    expect(
      await session.setPreferences(
        session.preferences.copy(mode: ReaderMode.vertical, gap: true),
      ),
      isTrue,
    );
    expect(session.index, 4);
    expect(session.offsetRatio, .37);
    expect(session.preferences.mode, ReaderMode.vertical);
    expect(
      server.fixture.writes
          .where((r) => r.path == '/api/v1/pack-sessions')
          .length,
      1,
    );
  });
}
