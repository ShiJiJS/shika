import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

typedef Json = Map<String, dynamic>;

class MissingServer {
  final fixture = PackServer();
  bool lose = false,
      missing = false,
      reject = false,
      bad = false,
      taskMissing = false;
  int posts = 0, queries = 0;
  Completer<void>? started, release;
  final receipts = <String, String>{};
  Json summary(String identity) => {
    'id': identity,
    'kind': 'pack_forget_missing',
    'status': 'completed',
    'phase': 'completed',
    'family': 'pack',
    'state': 'partial',
    'historical': false,
    'needs_attention': false,
    'created_at': 1,
    'finished_at': 2,
    'error': null,
    'total': 27,
    'processed': 27,
    'succeeded': 13,
    'failed': 0,
    'skipped': 14,
  };
  Future<void> start() async {
    fixture.handle = (r, body) async {
      final path = r.uri.path;
      if (path.endsWith('/info')) {
        return (
          status: 200,
          body: {
            'api_version': 1,
            'server_id': 'packs',
            'capabilities': [
              'typed_roots',
              'image_packs',
              'pack_missing_cleanup',
              'maintenance_tasks',
            ],
          },
        );
      }
      if (path.endsWith('/packs') &&
          r.uri.queryParameters['status'] == 'missing') {
        final at = int.parse(r.uri.queryParameters['offset']!),
            size = int.parse(r.uri.queryParameters['limit']!);
        if (started != null && !started!.isCompleted) {
          started!.complete();
          await release!.future;
        }
        return (
          status: 200,
          body: {
            'items': [
              for (var i = at; i < 27 && i < at + size; i++)
                {...fixture.pack(i), 'status': bad ? 'available' : 'missing'},
            ],
            'total': 27,
            'offset': at,
            'limit': size,
          },
        );
      }
      if (path.endsWith('/packs/forget-missing')) {
        posts++;
        if (reject) {
          return (
            status: 409,
            body: {
              'error': {'code': 'cleanup_busy', 'message': '同步进行中'},
            },
          );
        }
        final identity = receipts.putIfAbsent(
          body['request_id'],
          () => 'cleanup-${receipts.length + 1}',
        );
        if (lose) {
          lose = false;
          return (
            status: 503,
            body: {
              'error': {'code': 'lost', 'message': '回执丢失'},
            },
          );
        }
        return (
          status: 202,
          body: {
            'id': identity,
            'kind': bad ? 'other' : 'pack_forget_missing',
            'request_id': body['request_id'],
          },
        );
      }
      if (path.contains('/pack-missing-requests/')) {
        queries++;
        final identity = receipts[path.split('/').last];
        if (missing || identity == null) {
          return (
            status: 404,
            body: {
              'error': {'code': 'cleanup_request_not_found', 'message': '未找到'},
            },
          );
        }
        return (
          status: 200,
          body: {
            'id': identity,
            'kind': 'pack_forget_missing',
            'request_id': path.split('/').last,
          },
        );
      }
      if (path.contains('/maintenance-tasks/cleanup-')) {
        if (taskMissing) {
          return (
            status: 404,
            body: {
              'error': {'code': 'task_not_found', 'message': '尚未查到'},
            },
          );
        }
        return (status: 200, body: summary(path.split('/').last));
      }
      return null;
    };
    await fixture.start();
  }

  Future<void> connect(ServerLibraryRepository repo) =>
      repo.connect('http://127.0.0.1', fixture.server.port, 'fixture');
  Future<void> close() async {
    if (release != null && !release!.isCompleted) release!.complete();
    await fixture.server.close(force: true);
  }
}

class FailingMissingStore extends MemoryFileCommandStore {
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw const LibraryFailure('本机存储失败');
    await super.write(value);
  }
}

void main() {
  late MissingServer server;
  late ServerLibraryRepository repo;
  late FailingMissingStore store;
  late PackMissingCatalog gateway;
  setUp(() async {
    server = MissingServer();
    await server.start();
    store = FailingMissingStore();
    repo = ServerLibraryRepository(
      MemoryCredentialStore(),
      packCommands: store,
    );
    await server.connect(repo);
    gateway = repo.createPackMissing();
  });
  tearDown(() async {
    gateway.dispose();
    repo.dispose();
    await server.close();
  });
  test(
    'missing packs are authoritative, bounded and independent from viewing',
    () async {
      final identity = repo.playbackIdentity;
      expect((await gateway.page()).items.length, 24);
      final next = await gateway.page(offset: 24);
      expect(next.total, 27);
      expect(next.items.length, 3);
      expect(repo.playbackIdentity, identity);
      expect(server.posts, 0);
      server.bad = true;
      await expectLater(gateway.page(), throwsA(isA<LibraryFailure>()));
    },
  );
  test('real HTTP lost reply survives gateway recreation; unknown GET never repeats POST', () async {
    server.lose = true;
    await expectLater(gateway.submit('original'), throwsA(isA<ApiFailure>()));
    expect((await gateway.pending()).single.requestId, 'original');
    gateway.dispose();
    gateway = repo.createPackMissing();
    server.missing = true;
    expect(await gateway.query('original'), isNull);
    expect(server.posts, 1);
    await expectLater(
      gateway.submit('original'),
      throwsA(isA<LibraryFailure>()),
    );
    expect(server.posts, 1);
    server.missing = false;
    final task = await gateway.query('original');
    expect(task!.succeeded, 13);
    expect(task.skipped, 14);
    expect(task.progressLabel, contains('保留 14'));
    expect(await gateway.pending(), isEmpty);
    expect(server.posts, 1);
    expect(server.queries, 2);
  });
  test('write failure stops POST and an incomplete accepted identity stays pending', () async {
    store.fail = true;
    await expectLater(
      gateway.submit('disk-fail'),
      throwsA(isA<LibraryFailure>()),
    );
    expect(server.posts, 0);
    store.fail = false;
    server.bad = true;
    await expectLater(
      gateway.submit('accepted-bad'),
      throwsA(isA<LibraryFailure>()),
    );
    expect((await gateway.pending()).single.requestId, 'accepted-bad');
    server.bad = false;
    expect((await gateway.query('accepted-bad'))!.kind, 'pack_forget_missing');
    expect(server.posts, 1);
  });
  test('definite rejection clears only its local request; GET failure after acceptance does not', () async {
    server.reject = true;
    await expectLater(gateway.submit('rejected'), throwsA(isA<ApiFailure>()));
    expect(await gateway.pending(), isEmpty);
    server.reject = false;
    server.taskMissing = true;
    await expectLater(gateway.submit('accepted'), throwsA(isA<ApiFailure>()));
    expect((await gateway.pending()).single.requestId, 'accepted');
    server.taskMissing = false;
    expect((await gateway.query('accepted'))!.id, 'cleanup-1');
    expect(await gateway.pending(), isEmpty);
  });
  test(
    'task center finds and GETs the exact original cleanup receipt',
    () async {
      server.lose = true;
      await expectLater(gateway.submit('tasks'), throwsA(isA<ApiFailure>()));
      final tasks = repo.createMaintenanceTasks();
      final receipt = (await tasks.pending()).single;
      expect(receipt.source, MaintenanceReceiptSource.missingCleanup);
      expect(receipt.family, 'pack');
      expect((await tasks.reconcile(receipt))!.id, 'cleanup-1');
      expect(await tasks.pending(), isEmpty);
      expect(server.posts, 1);
      tasks.dispose();
    },
  );
  test('page cancellation and connection changes cannot publish stale rows or share receipts', () async {
    server.started = Completer();
    server.release = Completer();
    final pending = gateway.page();
    final rejected = expectLater(
      pending,
      throwsA(anyOf(isA<RequestCancelled>(), isA<ApiFailure>())),
    );
    await server.started!.future;
    gateway.cancelPages();
    server.release!.complete();
    await rejected;
    server.started = null;
    server.lose = true;
    await expectLater(
      gateway.submit('old-service'),
      throwsA(isA<ApiFailure>()),
    );
    final other = MissingServer();
    await other.start();
    try {
      await other.connect(repo);
      expect(gateway.isCurrent, isFalse);
      gateway.dispose();
      gateway = repo.createPackMissing();
      expect(await gateway.pending(), isEmpty);
    } finally {
      await other.close();
    }
  });
  test('journal preserves unknown namespaces, marks old receipts historical and removes only explicit local entry', () async {
    final book = PackFileJournal(store);
    final raw = jsonDecode(
      store.value ?? '{"version":1,"scopes":{}}',
    ) as Map<String, dynamic>;
    raw['future_namespace'] = {'safe': true};
    await store.write(jsonEncode(raw));
    await book.rememberMissing('scope', 'old');
    await book.historicalMissing('scope');
    expect((await book.missingPending('scope')).single.historical, isTrue);
    await book.rememberMissing('scope', 'new');
    await book.forgetMissingReceipt('scope', 'old');
    expect((await book.missingPending('scope')).single.requestId, 'new');
    expect((jsonDecode(store.value!) as Map)['future_namespace'], {
      'safe': true,
    });
  });
}
