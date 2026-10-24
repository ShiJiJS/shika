import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

typedef Json = Map<String, dynamic>;
Json clone(Json value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

class ReadingServer {
  final fixture = PackServer();
  final receipts = <String, Json>{};
  Json scope = {
    'directory_id': null,
    'search': '',
    'tag_ids': <String>[],
    'read_state': 'all',
  };
  String source = 'library', sort = 'name', selected = 'p0';
  bool random = false, loseReply = false, unauthorized = false;
  bool backupFixture = false;
  Completer<void>? restoreBlocked, restoreRelease;
  String? backupDigest;
  int revision = 0, progressRevision = 0;
  Json? replyOverride;
  String? overrideKind;
  String? blockKind;
  int? blockOffset;
  Completer<void>? blocked, release;
  Json prefs = {
    'mode': 'horizontal',
    'direction': 'ltr',
    'fit': 'contain',
    'gap': false,
    'revision': 0,
    'overridden': false,
  };
  Json page(int i, {String? packId}) {
    final pack = packId ?? selected;
    return {
      'id': '$pack-page$i',
      'pack_id': pack,
      'name': '第$i张.png',
      'ordinal': i,
      'width': 4000,
      'height': 6000,
      'content_version': 7,
      'error': null,
      'image_url': '/api/v1/pages/$pack-page$i/image?v=7',
      'thumbnail_url': '/api/v1/pages/$pack-page$i/thumbnail?v=7',
    };
  }

  Json state({
    int pageIndex = 0,
    double offset = .3,
    bool completed = false,
    bool ack = false,
  }) => {
    'page': page(pageIndex),
    'page_index': pageIndex,
    'offset_ratio': offset,
    'completed': completed,
    'revision': progressRevision,
    'content_version': 7,
    'recovery_reason': null,
    'preferences': clone(prefs),
    if (ack) 'session_revision': revision,
  };
  Json range() {
    final cursor = int.parse(selected.substring(1));
    return {
      'id': 'reading',
      'revision': revision,
      'candidate_count': 27,
      'available_count': 27,
      'cursor': cursor,
      'finished': false,
      'scope': clone(scope),
      'source': {'kind': source, 'sort': sort},
      'order': random ? 'random' : 'sequential',
      'current': {...fixture.pack(cursor), 'progress': null},
      'resume': state(),
      'previous': cursor == 0
          ? null
          : {'pack_id': 'p${cursor - 1}', 'ordinal': cursor - 1},
      'next': cursor == 26
          ? null
          : {'pack_id': 'p${cursor + 1}', 'ordinal': cursor + 1},
    };
  }

  Future<void> start() async {
    fixture.readingSupported = true;
    fixture.handle = handle;
    await fixture.start();
  }

  Future<({int status, Json body})?> handle(
    HttpRequest request,
    Json body,
  ) async {
    final path = request.uri.path, method = request.method;
    if (backupFixture) {
      if (path.endsWith('/backup-imports')) {
        backupDigest = sha256.convert(utf8.encode(jsonEncode(body))).toString();
        return (status: 202, body: {'id': 'inspect'});
      }
      if (path.endsWith('/backup-restores')) {
        return (status: 202, body: {'id': 'restore'});
      }
      if (path.endsWith('/tasks/inspect')) {
        return (
          status: 200,
          body: {
            'id': 'inspect',
            'kind': 'backup_inspect',
            'phase': 'completed',
            'status': 'completed',
            'result': {
              'file_sha256': backupDigest,
              'counts': <String, int>{},
              'roots': <Json>[],
            },
          },
        );
      }
      if (path.endsWith('/tasks/restore')) {
        if (!restoreBlocked!.isCompleted) restoreBlocked!.complete();
        await restoreRelease!.future;
        return (
          status: 200,
          body: {
            'id': 'restore',
            'kind': 'backup_restore',
            'phase': 'completed',
            'status': 'completed',
            'result': {'restored': true},
          },
        );
      }
    }

    final kind = path.contains('/pages')
        ? 'pages'
        : path.endsWith('/entries')
        ? 'queue'
        : path.contains('/pack-reading-requests/')
        ? 'receipt'
        : path.endsWith('/opened')
        ? 'opened'
        : path.endsWith('/progress')
        ? 'progress'
        : path.endsWith('/preferences')
        ? 'preferences'
        : path.endsWith('/position')
        ? 'position'
        : path.endsWith('/reading-defaults')
        ? 'defaults'
        : path.startsWith('/api/v1/pack-sessions')
        ? 'session'
        : null;
    if (kind == null) return null;
    expect(request.headers.value('Authorization'), 'Bearer pack-test-token');
    if (unauthorized) {
      return (
        status: 401,
        body: {
          'error': {'code': 'expired', 'message': 'Expired'},
        },
      );
    }
    if (blockKind == kind &&
        (blockOffset == null ||
            request.uri.queryParameters['offset'] == '$blockOffset')) {
      if (!blocked!.isCompleted) blocked!.complete();
      await release!.future;
    }
    Json result;
    if (kind == 'receipt') {
      final bits = request.uri.pathSegments;
      final saved = receipts['${bits[3]}:${bits[4]}'];
      if (saved == null) {
        return (
          status: 404,
          body: {
            'error': {
              'code': 'reading_request_not_found',
              'message': 'Unknown',
            },
          },
        );
      }
      result = {'status': 'completed', 'result': clone(saved)};
    } else if (method != 'GET' &&
        receipts.containsKey('$kind:${body['request_id']}')) {
      result = clone(receipts['$kind:${body['request_id']}']!);
    } else if (kind == 'session') {
      if (method == 'POST') {
        scope = Map<String, dynamic>.from(body['scope']);
        source = body['source'];
        sort = body['sort'];
        random = body['order'] == 'random';
        selected = body['anchor_pack_id'] ?? 'p0';
      }
      result = range();
    } else if (kind == 'pages') {
      final offset = int.parse(request.uri.queryParameters['offset']!),
          limit = int.parse(request.uri.queryParameters['limit']!);
      final id = request.uri.pathSegments[3];
      result = {
        'items': [
          for (var i = offset; i < offset + limit && i < 500; i++)
            page(i, packId: id),
        ],
        'total': 500,
        'offset': offset,
        'limit': limit,
        'content_version': 7,
      };
    } else if (kind == 'queue') {
      final offset = int.parse(request.uri.queryParameters['offset']!),
          limit = int.parse(request.uri.queryParameters['limit']!);
      result = {
        'items': [
          for (var i = offset; i < offset + limit && i < 27; i++)
            {'ordinal': i, 'pack': fixture.pack(i), 'available': i != 26},
        ],
        'total': 27,
        'offset': offset,
        'limit': limit,
        'revision': revision,
      };
    } else if (kind == 'opened' || kind == 'progress') {
      progressRevision++;
      prefs = {...prefs, 'overridden': true};
      final index = int.parse((body['page_id'] as String).split('-page').last);
      result = state(
        pageIndex: index,
        offset: kind == 'progress'
            ? (body['offset_ratio'] as num).toDouble()
            : .3,
        completed: body['completed'] == true,
        ack: true,
      );
    } else if (kind == 'position') {
      revision++;
      selected = body['pack_id'] ?? selected;
      result = {...range(), 'finished': body['finish']};
    } else {
      if (method != 'GET') {
        prefs = {
          ...Map<String, dynamic>.from(body['values']),
          'revision': body['expected_revision'] + 1,
          'overridden': kind == 'preferences',
        };
      }
      result = clone(prefs);
    }
    if (method != 'GET') {
      receipts['$kind:${body['request_id']}'] = clone(result);
    }
    if (overrideKind == kind && replyOverride != null) {
      result = clone(replyOverride!);
    }
    if (loseReply && method != 'GET') {
      loseReply = false;
      return (
        status: 503,
        body: {
          'error': {'code': 'reply_lost', 'message': 'Lost response'},
        },
      );
    }
    return (status: 200, body: result);
  }
}

void main() {
  late ReadingServer server;
  late ServerLibraryRepository repo;
  late PackReader reader;
  setUp(() async {
    server = ReadingServer();
    await server.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await repo.connect(
      'http://127.0.0.1',
      server.fixture.server.port,
      'fixture',
    );
    reader = repo.createPackReader();
  });
  tearDown(() async {
    reader.dispose();
    repo.dispose();
    if (server.release != null && !server.release!.isCompleted) {
      server.release!.complete();
    }
    await server.fixture.server.close(force: true);
  });
  const entryCursor = ReaderCursor(
    sessionId: 'reading',
    sessionRevision: 0,
    packId: 'p0',
    version: 7,
    progressRevision: 0,
  );
  CreatePackReading create([String key = 'create']) =>
      CreatePackReading(key, PackReadingEntry(PackQuery()));

  test('entry scope and fixed queue/pages are authoritative and media stays authenticated/versioned', () async {
    final playbackBefore = repo.playbackIdentity;
    final command = CreatePackReading(
      'filtered',
      PackReadingEntry(
        PackQuery(
          folder: '/packs',
          search: '套图',
          tags: {'b', 'a'},
          readState: PackReadState.unread,
          sort: PackSort.newest,
        ),
        source: BrowseSource.tags,
        anchorId: 'p26',
      ),
    );
    final value = await reader.submit(command);
    expect(value.candidateCount, 27);
    expect(value.cursor, 26);
    expect(value.previous!.packId, 'p25');
    expect(value.next, isNull);
    final body = server.fixture.writes.single.body;
    expect(body['scope'], {
      'directory_id': 'pack-directory',
      'search': '套图',
      'tag_ids': ['a', 'b'],
      'read_state': 'unread',
    });
    expect(body['source'], 'tags');
    expect(body['sort'], 'newest');
    expect(body['anchor_pack_id'], 'p26');
    final manifest = await reader.pages(
      'p26',
      version: 7,
      offset: 480,
      limit: 40,
    );
    expect(manifest.total, 500);
    expect(manifest.pages.length, 20);
    expect(manifest.pages.first.ordinal, 480);
    final image = manifest.pages.first.image!;
    expect(image.headers['Authorization'], 'Bearer pack-test-token');
    expect(Uri.parse(image.location).queryParameters['v'], '7');
    expect(Uri.parse(image.location).queryParameters['session'], isNotEmpty);
    final queue = await reader.queue(value.id, offset: 24, limit: 3);
    expect(queue.total, 27);
    expect(queue.entries.last.available, isFalse);
    expect(queue.entries.last.ordinal, 26);
    expect(
      server.fixture.writes.length,
      1,
      reason: 'metadata/prefetch never confirms opened',
    );
    expect(repo.playbackIdentity, playbackBefore);
    final recent = await reader.submit(
      CreatePackReading(
        'recent',
        PackReadingEntry(PackQuery(), source: BrowseSource.recent),
      ),
    );
    expect(recent.source, BrowseSource.recent);
    expect(server.fixture.writes.last.body['sort'], 'recent');
  });

  test('typed commands preserve revisions and lost replies are queried without resubmitting', () async {
    final value = await reader.submit(create());
    final opened = await reader.submit(
      OpenPackReading('opened', value.ownership!, value.resume!.page.id),
    );
    expect(opened.revision, 1);
    expect(opened.sessionRevision, 0);
    final cursor = ReaderCursor(
      sessionId: 'reading',
      sessionRevision: 0,
      packId: 'p0',
      version: 7,
      progressRevision: 1,
    );
    final write = WritePackProgress(
      'progress',
      cursor,
      const ReaderMark('p0-page4', offsetRatio: .37, completed: true),
    );
    server.loseReply = true;
    await expectLater(reader.submit(write), throwsA(isA<ApiFailure>()));
    final count = server.fixture.writes.length;
    final recovered = await reader.receipt(write);
    expect(recovered!.revision, 2);
    expect(recovered.mark.pageId, 'p0-page4');
    expect(recovered.mark.offsetRatio, .37);
    expect(recovered.mark.completed, isTrue);
    expect(server.fixture.writes.length, count);
    final unknown = WritePackProgress(
      'unknown',
      cursor,
      const ReaderMark('p0-page5'),
    );
    expect(await reader.receipt(unknown), isNull);
    expect(server.fixture.writes.length, count);
    final body = server.fixture.writes.last.body;
    expect(body, {
      'request_id': 'progress',
      'expected_session_revision': 0,
      'expected_revision': 1,
      'content_version': 7,
      'session_id': 'reading',
      'page_id': 'p0-page4',
      'offset_ratio': .37,
      'completed': true,
    });
    final moved = await reader.submit(
      const MovePackReading(
        'move',
        sessionId: 'reading',
        revision: 0,
        packId: 'p1',
      ),
    );
    expect(moved.revision, 1);
    expect(moved.pack!.id, 'p1');
    expect(await reader.receipt(create('absent')), isNull);
  });

  test(
    'per-pack preferences and global defaults keep separate revision payloads',
    () async {
      await reader.submit(create());
      final original = await reader.defaults();
      final chosen = original.copy(
        mode: ReaderMode.vertical,
        direction: ReaderDirection.rtl,
        gap: true,
        fit: ReaderFit.width,
      );
      final saved = await reader.submit(
        WritePackPreferences('prefs', entryCursor, chosen),
      );
      expect(saved.revision, 1);
      expect(saved.overridden, isTrue);
      final defaults = await reader.submit(
        WriteReaderDefaults('defaults', original.copy(gap: true)),
      );
      expect(defaults.revision, 1);
      expect(defaults.overridden, isFalse);
      final body = server.fixture.writes
          .where((w) => w.path.endsWith('/preferences'))
          .single
          .body;
      expect(body['session_id'], 'reading');
      expect(body['expected_session_revision'], 0);
      expect(body['expected_revision'], 0);
      expect((body['values'] as Map)['mode'], 'vertical');
    },
  );

  test('malformed ranges/manifests and foreign or wrong-version media cannot become readable', () async {
    await reader.submit(create());
    server.overrideKind = 'session';
    for (final change in <Json>[
      {'id': 'other'},
      {'available_count': 28},
      {'cursor': 27},
      {
        'previous': {'pack_id': 'p0', 'ordinal': 0},
      },
      {
        'resume': {...server.state(), 'offset_ratio': 1.1},
      },
    ]) {
      server.replyOverride = {...server.range(), ...change};
      await expectLater(reader.read('reading'), throwsA(isA<LibraryFailure>()));
    }
    server.overrideKind = 'pages';
    final valid = {
      'items': [server.page(0), server.page(1)],
      'total': 500,
      'offset': 0,
      'limit': 2,
      'content_version': 7,
    };
    for (final change in <Json>[
      {'content_version': 8},
      {'offset': 1},
      {
        'items': [server.page(0), server.page(0)],
      },
      {
        'items': [
          {...server.page(0), 'pack_id': 'foreign'},
          server.page(1),
        ],
      },
      {
        'items': [
          {...server.page(0), 'image_url': 'https://foreign.invalid/image?v=7'},
          server.page(1),
        ],
      },
      {
        'items': [
          {...server.page(0), 'image_url': '/api/v1/pages/p0-page0/image?v=6'},
          server.page(1),
        ],
      },
    ]) {
      server.replyOverride = {...valid, ...change};
      await expectLater(
        reader.pages('p0', version: 7, limit: 2),
        throwsA(isA<LibraryFailure>()),
      );
    }
  });

  test('page cancellation is independent and old handles cannot cross a replacement connection', () async {
    server.blockKind = 'pages';
    server.blockOffset = 0;
    server.blocked = Completer<void>();
    server.release = Completer<void>();
    final old = reader.pages('p0', version: 7, limit: 2);
    final cancelled = expectLater(old, throwsA(isA<RequestCancelled>()));
    await server.blocked!.future;
    final queue = await reader.queue('reading', limit: 2);
    expect(queue.entries.length, 2);
    final next = await reader.pages('p0', version: 7, offset: 40, limit: 2);
    expect(next.offset, 40);
    server.release!.complete();
    await cancelled;
    final other = PackServer();
    await other.start();
    addTearDown(() => other.server.close(force: true));
    await repo.connect('http://127.0.0.1', other.server.port, 'fixture');
    await expectLater(
      reader.submit(create('old-connection')),
      throwsA(isA<RequestCancelled>()),
    );
    expect(other.writes, isEmpty);
    expect(() => repo.createPackReader(), throwsA(isA<LibraryFailure>()));
  });

  test('unavailable directories never create an expanded session and 401 expires the shared owner', () async {
    server.fixture.unavailableDirectory = true;
    await expectLater(
      reader.submit(
        CreatePackReading('dir', PackReadingEntry(PackQuery(folder: '/packs'))),
      ),
      throwsA(isA<LibraryFailure>()),
    );
    expect(server.fixture.writes, isEmpty);
    server.unauthorized = true;
    await expectLater(reader.read('reading'), throwsA(isA<ApiFailure>()));
    expect(repo.snapshot.connected, isFalse);
    await expectLater(
      reader.pages('p0', version: 7),
      throwsA(isA<RequestCancelled>()),
    );
  });
  test('confirmed restore invalidates reader handles and pending reads even on the same connection', () async {
    final connection = repo.connectionIdentity;
    server.blockKind = 'pages';
    server.blockOffset = 0;
    server.blocked = Completer<void>();
    server.release = Completer<void>();
    final old = reader.pages('p0', version: 7, limit: 2);
    final cancelled = expectLater(old, throwsA(isA<RequestCancelled>()));
    await server.blocked!.future;
    server.backupFixture = true;
    server.restoreBlocked = Completer<void>();
    server.restoreRelease = Completer<void>();
    final text = jsonEncode({
      'format': 'video-viewer-management',
      'version': 1,
      'payload': {'fixture': true},
    });
    final restore = repo.restoreBackup(text, {});
    await server.restoreBlocked!.future;
    expect(repo.backupRestorePending, isTrue);
    expect(() => repo.createPackReader(), throwsA(isA<LibraryFailure>()));
    final before = server.fixture.writes.length;
    await expectLater(
      reader.submit(
        const OpenPackReading('during-restore', entryCursor, 'p0-page0'),
      ),
      throwsA(isA<LibraryFailure>()),
    );
    expect(server.fixture.writes.length, before);
    server.restoreRelease!.complete();
    await restore;
    expect(identical(connection, repo.connectionIdentity), isTrue);
    expect(repo.backupRestorePending, isFalse);
    server.release!.complete();
    await cancelled;
    expect(reader.isCurrent, isFalse);
    await expectLater(reader.read('reading'), throwsA(isA<RequestCancelled>()));
    final fresh = repo.createPackReader();
    addTearDown(fresh.dispose);
    expect((await fresh.read('reading')).id, 'reading');
  });
  test('invalid acknowledgements cannot advance state and a malformed create reply is recoverable by receipt', () async {
    final filtered = CreatePackReading(
      'filtered-reply',
      PackReadingEntry(PackQuery(folder: '/packs', search: '套图', tags: {'a'})),
    );
    server.overrideKind = 'session';
    server.replyOverride = server.range();
    await expectLater(reader.submit(filtered), throwsA(isA<LibraryFailure>()));
    final before = server.fixture.writes.length;
    server.replyOverride = null;
    final recovered = await reader.receipt(filtered);
    expect(recovered!.id, 'reading');
    expect(server.fixture.writes.length, before);
    await reader.submit(
      OpenPackReading(
        'open-response',
        recovered.ownership!,
        recovered.resume!.page.id,
      ),
    );
    const cursor = ReaderCursor(
      sessionId: 'reading',
      sessionRevision: 0,
      packId: 'p0',
      version: 7,
      progressRevision: 1,
    );
    final valid = {
      ...server.state(pageIndex: 4, offset: .37, ack: true),
      'revision': 2,
    };
    server.overrideKind = 'progress';
    var sequence = 0;
    for (final change in <Json>[
      {'revision': 1},
      {'session_revision': 1},
      {'content_version': 8},
      {'offset_ratio': .1},
      {'page': server.page(4, packId: 'foreign')},
    ]) {
      server.replyOverride = {...valid, ...change};
      await expectLater(
        reader.submit(
          WritePackProgress(
            'bad-ack-${sequence++}',
            cursor,
            const ReaderMark('p0-page4', offsetRatio: .37),
          ),
        ),
        throwsA(isA<LibraryFailure>()),
      );
    }
    server.overrideKind = 'queue';
    server.replyOverride = {
      'items': [
        {'ordinal': 24, 'pack': server.fixture.pack(24), 'available': true},
        {'ordinal': 25, 'pack': server.fixture.pack(24), 'available': true},
        {'ordinal': 26, 'pack': server.fixture.pack(26), 'available': false},
      ],
      'total': 27,
      'offset': 24,
      'limit': 3,
      'revision': 0,
    };
    await expectLater(
      reader.queue('reading', offset: 24, limit: 3),
      throwsA(isA<LibraryFailure>()),
    );
  });
  test('a listener retiring the reader during publish cannot receive a successful old-handle result', () async {
    void retire() => reader.dispose();
    repo.addListener(retire);
    addTearDown(() => repo.removeListener(retire));
    await expectLater(
      reader.submit(create('retired-on-publish')),
      throwsA(isA<RequestCancelled>()),
    );
    expect(reader.isCurrent, isFalse);
    expect(
      server.fixture.writes
          .where((item) => item.path == '/api/v1/pack-sessions')
          .length,
      1,
    );
    expect(
      server.receipts.containsKey('session:retired-on-publish'),
      isTrue,
      reason: 'the acknowledged mutation is not automatically repeated after local retirement',
    );
  });
}
