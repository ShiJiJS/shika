import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

typedef Json = Map<String, dynamic>;
Json copy(Json value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

class FilesFixture {
  final server = PackServer(), store = MemoryFileCommandStore();
  final receipts = <String, Json>{}, tasks = <String, Json>{};
  bool supported = true,
      lose = false,
      missing = false,
      reject = false,
      partial = false,
      malformed = false,
      queued = false;
  Completer<void>? blocked, release;
  Json task(
    String id,
    String kind,
    List<String> ids, {
    String status = 'completed',
  }) => {
    'id': id,
    'kind': 'pack_$kind',
    'status': status,
    'error': null,
    'result': status != 'completed'
        ? <String, dynamic>{}
        : {
            'operation_id': id,
            'total': ids.length,
            'processed': ids.length,
            'succeeded': partial ? ids.length - 1 : ids.length,
            'failed': partial ? 1 : 0,
            'partial': partial && ids.length > 1,
            'items': [
              for (var i = 0; i < ids.length; i++)
                {
                  'requested_id': ids[i],
                  'pack_id': kind == 'trash' ? ids[i] : 'p$i',
                  'trash_id': kind == 'trash' ? 'trash-$i' : ids[i],
                  'outcome': partial && i == ids.length - 1
                      ? 'failed'
                      : 'succeeded',
                  'phase': 'committed',
                  'error': partial && i == ids.length - 1
                      ? 'stale_pack_state'
                      : null,
                },
            ],
            'reading_transition': kind == 'trash'
                ? {
                    'session_id': 'reading',
                    'revision': 3,
                    'cursor': 1,
                    'pack_id': 'p1',
                    'finished': false,
                  }
                : null,
            'reading_restored': kind == 'undo',
            'undo_expires_at': kind == 'trash' ? 4000000000.0 : null,
          },
  };
  Future<void> start() async {
    server.handle = handle;
    await server.start();
  }

  Future<({int status, Json body})?> handle(HttpRequest r, Json body) async {
    final path = r.uri.path;
    if (path == '/api/v1/info') {
      return (
        status: 200,
        body: {
          'api_version': 1,
          'server_id': 'packs',
          'capabilities': [
            'image_packs',
            'pack_tags',
            'typed_roots',
            if (supported) 'pack_logical_trash',
          ],
        },
      );
    }
    if (path.contains('/pack-file-requests/') ||
        path.contains('/pack-retry-requests/')) {
      final value = receipts[r.uri.pathSegments.last];
      if (missing || value == null) {
        return (
          status: 404,
          body: {
            'error': {'code': 'not_found', 'message': 'Unknown'},
          },
        );
      }
      return (status: 200, body: malformed ? {...value, 'result': {}} : value);
    }
    if (r.method == 'GET' && path.contains('/pack-operations/')) {
      final value = tasks[r.uri.pathSegments.last];
      return value == null
          ? (
              status: 404,
              body: {
                'error': {'code': 'not_found', 'message': 'Unknown'},
              },
            )
          : (status: 200, body: value);
    }
    if (r.method == 'POST' &&
        (path == '/api/v1/packs/trash' ||
            path == '/api/v1/pack-trash/restore' ||
            path.contains('/pack-operations/'))) {
      expect(store.value, contains(body['request_id']));
      if (blocked != null) {
        blocked!.complete();
        await release!.future;
      }
      if (reject) {
        return (
          status: 409,
          body: {
            'error': {'code': 'stale_pack_state', 'message': 'Changed'},
          },
        );
      }
      final kind = path.endsWith('/trash')
          ? 'trash'
          : path.endsWith('/restore')
          ? 'restore'
          : path.endsWith('/undo')
          ? 'undo'
          : 'retry';
      final id = kind == 'retry'
          ? r.uri.pathSegments[3]
          : 'op-${body['request_id']}';
      final value = kind == 'retry'
          ? tasks[id]!
          : task(
              id,
              kind,
              List<String>.from(
                body[kind == 'trash' ? 'pack_ids' : 'trash_ids'] ?? ['trash-0'],
              ),
              status: queued ? 'queued' : 'completed',
            );
      receipts[body['request_id']] = copy(value);
      tasks[id] = copy(value);
      if (lose) {
        lose = false;
        return (
          status: 503,
          body: {
            'error': {'code': 'reply_lost', 'message': 'Unconfirmed'},
          },
        );
      }
      return (status: 202, body: malformed ? {...value, 'result': {}} : value);
    }
    return null;
  }
}

class FailingStore extends MemoryFileCommandStore {
  @override
  Future<void> write(String value) async =>
      throw const FileSystemException('disk full');
}

void main() {
  test('reader context round trips original query, order, range and return position locally', () {
    final origin = PackCleanupContext(
      entry: PackReadingEntry(
        PackQuery(
          folder: '/图片/图包',
          tags: {'b', 'a'},
          search: '春日',
          readState: PackReadState.reading,
          source: BrowseSource.tags,
          sort: PackSort.newest,
        ),
        anchorId: 'p2',
        random: true,
      ),
      quick: false,
      scrollOffset: 238.5,
      scrollAnchor: 'p2',
      scrollIndex: 26,
      scrollInset: -13,
      anchors: ['p2', 'p3'],
    );
    final owner = ReaderCursor(
      sessionId: 'range',
      sessionRevision: 9,
      packId: 'p2',
      version: 3,
      progressRevision: 4,
    );
    final command = PackFileCommand.trash(
      'original',
      ['p2'],
      reading: owner,
      advance: false,
      readerContext: origin,
    );
    final restored = PackFileCommand.fromJson(copy(command.toJson()));
    expect(restored.signature, command.signature);
    expect(restored.readerContext!.toJson(), command.readerContext!.toJson());
    expect(restored.readingSessionId, 'range');
    expect(restored.body['reading']['advance'], isFalse);
    expect(restored.body, isNot(contains('reader_context')));
    expect(restored.readerContext!.entry.random, isTrue);
    final undo = PackFileCommand.fromJson(
      copy(
        PackFileCommand.undo(
          'undo',
          'task',
          readerContext: restored.readerContext,
        ).toJson(),
      ),
    );
    expect(undo.readingSessionId, 'range');
    expect(
      undo.readerContext!.entry.query.toJson(),
      origin.entry.query.toJson(),
    );
    final legacy = PackFileCommand.trash('old', ['p2'], reading: owner);
    expect((legacy.body['reading'] as Map).containsKey('advance'), isFalse);
    expect(
      PackFileCommand.fromJson(copy(legacy.toJson())).signature,
      legacy.signature,
    );
  });
  test(
    'stored context cannot silently change quick behavior or original range',
    () {
      final owner = ReaderCursor(
        sessionId: 'range',
        sessionRevision: 9,
        packId: 'p2',
        version: 3,
        progressRevision: 4,
      );
      final command = PackFileCommand.trash(
        'original',
        ['p2'],
        reading: owner,
        readerContext: PackCleanupContext(
          entry: PackReadingEntry(PackQuery()),
          quick: true,
        ),
      );
      for (final change in ['quick', 'session_id', 'scroll_offset', 'source']) {
        final raw = copy(command.toJson());
        final context = raw['reader_context'] as Map;
        if (change == 'quick') context['quick'] = false;
        if (change == 'session_id') context['session_id'] = 'another-range';
        if (change == 'scroll_offset') context['scroll_offset'] = -1;
        if (change == 'source') context['query']['source'] = 'unknown';
        expect(
          () => PackFileCommand.fromJson(raw),
          throwsA(isA<LibraryFailure>()),
        );
      }
      final modified = PackFileCommand.trash(
        'original',
        ['p2'],
        reading: owner,
        readerContext: PackCleanupContext(
          entry: PackReadingEntry(PackQuery(search: 'changed')),
          quick: true,
        ),
      );
      expect(modified.signature, isNot(command.signature));
    },
  );

  late FilesFixture fixture;
  late ServerLibraryRepository repo;
  setUp(() async {
    fixture = FilesFixture();
    await fixture.start();
    repo = ServerLibraryRepository(
      MemoryCredentialStore(),
      packCommands: fixture.store,
    );
    await repo.connect(
      'http://127.0.0.1',
      fixture.server.server.port,
      'fixture',
    );
  });
  tearDown(() async {
    if (fixture.release != null && !fixture.release!.isCompleted) {
      fixture.release!.complete();
    }
    repo.dispose();
    await fixture.server.server.close(force: true);
  });
  test(
    'immutable intent, actual reading owner and persisted command precede HTTP',
    () async {
      final ids = ['p0', 'p0'];
      final cmd = PackFileCommand.trash(
        'once',
        ids,
        reading: const ReaderCursor(
          sessionId: 'reading',
          sessionRevision: 2,
          packId: 'p0',
          version: 7,
          progressRevision: 4,
        ),
        label: '原包名称',
      );
      ids.add('p1');
      expect(
        () => (cmd.body['pack_ids'] as List).add('p1'),
        throwsUnsupportedError,
      );
      expect(
        () => (cmd.body['reading'] as Map)['pack_id'] = 'p1',
        throwsUnsupportedError,
      );
      final files = repo.createPackFiles(),
          value = await repo.createPackFiles().resolve(cmd, submit: true);
      expect(value!.result!.succeeded, 1);
      expect(value.result!.transition!.packId, 'p1');
      expect(
        value.result!.undoExpiresAt!.millisecondsSinceEpoch,
        4000000000000,
      );
      expect(fixture.server.writes.last.body, {
        'request_id': 'once',
        ...cmd.body,
      });
      expect((await files.pending()).single.toJson(), cmd.toJson());
      // A second handle must read the receipt before acknowledging it.
      await expectLater(files.acknowledge(cmd), throwsA(isA<LibraryFailure>()));
      await files.receipt(cmd);
      await files.acknowledge(cmd);
      expect(await files.pending(), isEmpty);
    },
  );
  test('committed write with 503 survives repository reopen; reconciliation sends only GET', () async {
    fixture.lose = true;
    final files = repo.createPackFiles(),
        cmd = PackFileCommand.trash('lost', ['p0']);
    await expectLater(files.send(cmd), throwsA(isA<ApiFailure>()));
    final before = fixture.server.writes.length;
    repo.dispose();
    repo = ServerLibraryRepository(
      MemoryCredentialStore(),
      packCommands: fixture.store,
    );
    await repo.connect(
      'http://127.0.0.1',
      fixture.server.server.port,
      'fixture',
    );
    final reopened = repo.createPackFiles(),
        saved = (await repo.createPackFiles().pending()).single;
    expect(saved.signature, cmd.signature);
    expect((await reopened.resolve(saved))!.result!.succeeded, 1);
    expect(fixture.server.writes.length, before);
    await reopened.acknowledge(saved);
    expect(await reopened.pending(), isEmpty);
  });
  test(
    'unknown 404 stays pending without replay; other packs remain usable',
    () async {
      fixture.lose = true;
      final files = repo.createPackFiles(),
          cmd = PackFileCommand.trash('unknown', ['p0']);
      await expectLater(files.send(cmd), throwsA(isA<ApiFailure>()));
      fixture.missing = true;
      final before = fixture.server.writes.length;
      expect(await files.receipt(cmd), isNull);
      expect(await files.resolve(cmd), isNull);
      expect(fixture.server.writes.length, before);
      expect((await files.pending()).length, 1);
      await expectLater(files.acknowledge(cmd), throwsA(isA<LibraryFailure>()));
      await expectLater(
        files.send(PackFileCommand.trash('duplicate', ['p0'])),
        throwsA(isA<LibraryFailure>()),
      );
      fixture.missing = false;
      expect(
        (await files.send(PackFileCommand.trash('other', ['p1']))).settled,
        isTrue,
      );
    },
  );
  test(
    'explicit resend keeps nonce and payload; differing payload is rejected',
    () async {
      fixture.lose = true;
      final files = repo.createPackFiles(),
          cmd = PackFileCommand.trash('resend', ['p0']);
      await expectLater(files.send(cmd), throwsA(isA<ApiFailure>()));
      fixture.missing = true;
      expect(await files.receipt(cmd), isNull);
      await expectLater(
        files.send(PackFileCommand.trash('resend', ['p1'])),
        throwsA(isA<LibraryFailure>()),
      );
      fixture.missing = false;
      expect((await files.send(cmd)).id, 'op-resend');
      final writes = fixture.server.writes
          .where((r) => r.path == '/api/v1/packs/trash')
          .toList();
      expect(writes.length, 2);
      expect(writes[0].body, writes[1].body);
    },
  );
  test('known task is queried on repeated send without another POST', () async {
    final files = repo.createPackFiles(),
        cmd = PackFileCommand.trash('known', ['p0']);
    final task = await files.send(cmd);
    final before = fixture.server.writes.length;
    expect((await files.send(cmd)).id, task.id);
    expect(fixture.server.writes.length, before);
  });
  test('partial results keep item outcomes; malformed results retain the original intent', () async {
    fixture.partial = true;
    final files = repo.createPackFiles(),
        cmd = PackFileCommand.trash('partial', ['p0', 'p1']);
    final task = await files.send(cmd);
    expect(task.result!.partial, isTrue);
    expect(task.result!.succeeded, 1);
    expect(task.result!.items.last.error, 'stale_pack_state');
    await files.acknowledge(cmd);
    fixture.partial = false;
    fixture.malformed = true;
    final bad = PackFileCommand.trash('bad', ['p0']);
    await expectLater(files.send(bad), throwsA(isA<LibraryFailure>()));
    expect((await files.pending()).single.requestId, 'bad');
    await expectLater(files.acknowledge(bad), throwsA(isA<LibraryFailure>()));
    fixture.malformed = false;
    expect((await files.receipt(bad))!.settled, isTrue);
  });
  test(
    'queued and interrupted results cannot be acknowledged as success',
    () async {
      fixture.queued = true;
      final files = repo.createPackFiles(),
          cmd = PackFileCommand.trash('queued', ['p0']);
      final task = await files.resolve(
        cmd,
        submit: true,
        timeout: Duration.zero,
      );
      expect(task!.settled, isFalse);
      await expectLater(files.acknowledge(cmd), throwsA(isA<LibraryFailure>()));
      fixture.receipts['queued'] = fixture.task(task.id, 'trash', [
        'p0',
      ], status: 'interrupted');
      expect((await files.resolve(cmd))!.status, 'interrupted');
      fixture.receipts['queued'] = fixture.task(task.id, 'trash', ['p0']);
      expect((await files.resolve(cmd))!.settled, isTrue);
    },
  );
  test('retry response loss queries its own receipt and retains original task identity', () async {
    final files = repo.createPackFiles();
    fixture.tasks['original'] = fixture.task('original', 'restore', [
      'trash-0',
    ]);
    fixture.lose = true;
    final cmd = PackFileCommand.retry('retry-key', 'original');
    await expectLater(files.send(cmd), throwsA(isA<ApiFailure>()));
    final before = fixture.server.writes.length;
    expect((await files.receipt(cmd))!.id, 'original');
    expect(fixture.server.writes.length, before);
    expect(
      fixture.server.reads.last.path,
      '/api/v1/pack-retry-requests/retry-key',
    );
  });
  test('replaced connection cancels late publication and isolates persisted scopes', () async {
    fixture.blocked = Completer<void>();
    fixture.release = Completer<void>();
    final files = repo.createPackFiles(),
        cmd = PackFileCommand.trash('blocked', ['p0']);
    final work = files.send(cmd),
        assertion = expectLater(
          files.send(cmd),
          throwsA(isA<RequestCancelled>()),
        );
    await fixture.blocked!.future;
    final other = FilesFixture();
    await other.start();
    try {
      await repo.connect(
        'http://127.0.0.1',
        other.server.server.port,
        'fixture',
      );
      fixture.release!.complete();
      await assertion;
      await expectLater(work, throwsA(isA<RequestCancelled>()));
      expect(files.isCurrent(), isFalse);
      expect(await repo.createPackFiles().pending(), isEmpty);
    } finally {
      await other.server.server.close(force: true);
    }
  });
  test('capability gate rejects before any pack mutation', () async {
    fixture.supported = false;
    await repo.connect(
      'http://127.0.0.1',
      fixture.server.server.port,
      'fixture',
    );
    final before = fixture.server.writes.length;
    expect(() => repo.createPackFiles(), throwsA(isA<LibraryFailure>()));
    expect(fixture.server.writes.length, before);
  });
  test('journal disk failure prevents HTTP mutation', () async {
    repo.dispose();
    repo = ServerLibraryRepository(
      MemoryCredentialStore(),
      packCommands: FailingStore(),
    );
    await repo.connect(
      'http://127.0.0.1',
      fixture.server.server.port,
      'fixture',
    );
    final before = fixture.server.writes.length;
    await expectLater(
      repo.createPackFiles().send(PackFileCommand.trash('disk', ['p0'])),
      throwsA(isA<FileSystemException>()),
    );
    expect(fixture.server.writes.length, before);
  });
  test(
    'definitive rejection releases reservation without reporting success',
    () async {
      fixture.reject = true;
      final files = repo.createPackFiles();
      await expectLater(
        files.send(PackFileCommand.trash('rejected', ['p0'])),
        throwsA(isA<ApiFailure>()),
      );
      expect(await files.pending(), isEmpty);
    },
  );
  test('in-flight duplicate keys cannot change intent and identical sends coalesce', () async {
    fixture.blocked = Completer<void>();
    fixture.release = Completer<void>();
    final files = repo.createPackFiles(),
        command = PackFileCommand.trash('race', ['p0']);
    final first = files.send(command), same = files.send(command);
    expect(identical(first, same), isTrue);
    await fixture.blocked!.future;
    await expectLater(
      files.send(PackFileCommand.trash('race', ['p1'])),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(
      files.send(PackFileCommand.trash('different', ['p0'])),
      throwsA(isA<LibraryFailure>()),
    );
    fixture.release!.complete();
    expect((await first).settled, isTrue);
    expect(
      fixture.server.writes
          .where((r) => r.path == '/api/v1/packs/trash')
          .length,
      1,
    );
  });
  test('known task 404 cannot enable POST replay and changed receipt identity is rejected', () async {
    final files = repo.createPackFiles(),
        command = PackFileCommand.trash('known404', ['p0']);
    await files.send(command);
    fixture.missing = true;
    expect(await files.receipt(command), isNull);
    expect(await files.canResend(command), isFalse);
    fixture.missing = false;
    fixture.receipts['known404'] = fixture.task(
      'different-operation',
      'trash',
      ['p0'],
    );
    await expectLater(files.receipt(command), throwsA(isA<LibraryFailure>()));
    expect((await files.pending()).single.requestId, 'known404');
    await expectLater(
      files.acknowledge(command),
      throwsA(isA<LibraryFailure>()),
    );
  });
  test('mismatched result membership is rejected without dropping the original journal entry', () async {
    final files = repo.createPackFiles(),
        command = PackFileCommand.trash('members', ['p0']);
    await files.send(command);
    fixture.receipts['members'] = fixture.task('op-members', 'trash', ['p9']);
    await expectLater(files.receipt(command), throwsA(isA<LibraryFailure>()));
    expect((await files.pending()).single.requestId, 'members');
  });
  test('a corrupt journal fails closed without discarding evidence or sending HTTP', () async {
    repo.dispose();
    fixture.store.value = '{broken';
    repo = ServerLibraryRepository(
      MemoryCredentialStore(),
      packCommands: fixture.store,
    );
    await repo.connect(
      'http://127.0.0.1',
      fixture.server.server.port,
      'fixture',
    );
    final before = fixture.server.writes.length;
    expect(() => repo.createPackFiles(), throwsA(isA<LibraryFailure>()));
    expect(fixture.store.value, '{broken');
    expect(fixture.server.writes.length, before);
  });
  for (final serverClock in [100.0, 4000000000.0]) {
    test(
      'undo duration uses server time despite phone clock skew: $serverClock',
      () {
        final raw = fixture.task('clock', 'trash', ['p0']);
        raw['server_time'] = serverClock;
        (raw['result'] as Map)['undo_expires_at'] = serverClock + 8;
        final task = PackFileTask.fromJson(raw);
        expect(task.remainingUndo(task.receivedAt), const Duration(seconds: 8));
        expect(
          task.remainingUndo(
            task.receivedAt.add(const Duration(milliseconds: 1250)),
          ),
          const Duration(milliseconds: 6750),
        );
        expect(
          task.remainingUndo(task.receivedAt.add(const Duration(seconds: 8))),
          Duration.zero,
        );
        (raw['result'] as Map)['undo_expires_at'] = serverClock - 1;
        expect(PackFileTask.fromJson(raw).remainingUndo(), Duration.zero);
        raw.remove('server_time');
        (raw['result'] as Map)['undo_expires_at'] = 4000000000.0;
        expect(
          PackFileTask.fromJson(raw).remainingUndo().inMilliseconds,
          lessThanOrEqualTo(8000),
        );
      },
    );
  }
}
