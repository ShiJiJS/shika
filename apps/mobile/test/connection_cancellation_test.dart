import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

void main() {
  late PackServer server;
  late ServerLibraryRepository repo;
  late MemoryCredentialStore store;
  Completer<void>? entered, release;
  String? held;
  setUp(() async {
    entered = release = null;
    held = null;
    server = PackServer()..readingSupported = true;
    server.handle = (request, body) async {
      if (request.uri.path == held) {
        entered!.complete();
        await release!.future;
      }
      if (request.uri.path.endsWith('/auth/status')) {
        return (status: 200, body: {'initialized': false});
      }
      if (request.uri.path.endsWith('/auth/session')) {
        return (status: 200, body: <String, dynamic>{});
      }
      return null;
    };
    await server.start();
    store = MemoryCredentialStore();
    repo = ServerLibraryRepository(store);
  });
  tearDown(() async {
    if (release != null && !release!.isCompleted) release!.complete();
    repo.dispose();
    await server.server.close(force: true);
  });
  Future<void> connect() =>
      repo.connect('http://127.0.0.1', server.server.port, 'secret');

  test(
    'cancelling login cannot save credentials or publish a library later',
    () async {
      held = '/api/v1/auth/login';
      entered = Completer<void>();
      release = Completer<void>();
      final pending = connect();
      final expected = expectLater(pending, throwsA(isA<RequestCancelled>()));
      await entered!.future;
      repo.cancelConnection();
      release!.complete();
      await expected;
      expect(repo.snapshot.connected, isFalse);
      expect(store.value, isNull);
    },
  );
  test(
    'aborted server change leaves existing readers and login usable',
    () async {
      await connect();
      final identity = repo.connectionIdentity, credential = store.value;
      final reader = repo.createPackReader();
      held = '/api/v1/auth/login';
      entered = Completer<void>();
      release = Completer<void>();
      final pending = connect();
      final expected = expectLater(pending, throwsA(isA<RequestCancelled>()));
      await entered!.future;
      repo.cancelConnection();
      release!.complete();
      await expected;
      expect(repo.snapshot.connected, isTrue);
      expect(repo.connectionIdentity, same(identity));
      expect(store.value, same(credential));
      expect(reader.isCurrent, isTrue);
      reader.dispose();
    },
  );
  test(
    'logout clears local credential, preserves address and invalidates readers',
    () async {
      await connect();
      final reader = repo.createPackReader();
      final address = repo.snapshot.address;
      await repo.disconnect();
      expect(repo.snapshot.connected, isFalse);
      expect(reader.isCurrent, isFalse);
      expect(store.value, isNull);
      expect(repo.snapshot.address, address);
      expect(store.endpoint, isNotNull);
      reader.dispose();
    },
  );
}
