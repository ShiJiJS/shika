import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';

typedef Json = Map<String, dynamic>;

class PreviewServer {
  late HttpServer server;
  bool supportsFixed = true, loseCreate = false, loseOrder = false;
  Json? round;
  final creates = <Json>[], orders = <Json>[], opens = <Json>[];
  final reads = <Uri>[];
  final orderResults = <String, Json>{};
  Completer<void>? moveStarted, releaseMove;

  Json video(int index) => {
    'id': 'v$index',
    'root_id': 'root',
    'path': '/media/folder/$index.mp4',
    'width': 100,
    'height': 200,
    'duration': 3.0,
    'created_at': index.toDouble(),
    'type': 'MP4',
    'status': 'available',
    'tag_ids': <String>[],
    'thumbnail_url': null,
    'media_url': '/api/v1/videos/v$index/stream',
  };

  Json summary({int position = 0, int revision = 0, int sequence = 0}) => {
    'id': 'fixed-range',
    'membership': 'fixed',
    'source': creates.last['source'],
    'sort': creates.last['sort'],
    'scope': creates.last['scope'],
    'order': creates.last['order'],
    'position': position,
    'total': 30,
    'candidate_count': 30,
    'revision': revision,
    'sequence_revision': sequence,
    'finished': false,
    'active': true,
    'current': video(position),
    'window': [
      for (var i = position - 1; i <= position + 1; i++)
        if (i >= 0 && i < 30) {'position': i, 'video': video(i)},
    ],
  };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      Json body = {};
      if (request.method != 'GET') {
        final text = await utf8.decoder.bind(request).join();
        if (text.isNotEmpty) body = Map<String, dynamic>.from(jsonDecode(text));
      } else {
        reads.add(request.uri);
      }
      Object result;
      var status = 200;
      if (path.endsWith('/auth/login')) {
        result = {
          'access_token': 'isolated-token',
          'server_id': 'fixture',
          'expires_at': 4000000000,
        };
      } else if (path.endsWith('/info')) {
        result = {
          'api_version': 1,
          'server_id': 'fixture',
          'capabilities': [
            if (supportsFixed) ...[
              'fixed_video_sessions',
              'versioned_video_queue',
              'video_entry_anchors',
            ],
          ],
        };
      } else if (path.endsWith('/roots')) {
        result = {
          'items': [
            {
              'id': 'root',
              'name': 'Media',
              'path': '/media',
              'directory_id': 'root-dir',
              'available': true,
              'last_scan': 1,
            },
          ],
        };
      } else if (path.endsWith('/library-state')) {
        result = {'ready': true, 'scanning': false, 'status': 'idle'};
      } else if (path.endsWith('/scans')) {
        result = {'id': 'scan'};
        status = 202;
      } else if (path.endsWith('/tasks/scan')) {
        result = {
          'id': 'scan',
          'status': 'completed',
          'result': {
            'imported': 0,
            'unchanged': 30,
            'deferred': 0,
            'failed': 0,
            'roots': [],
          },
        };
      } else if (path.contains('/directories/')) {
        result = {
          'id': 'folder-id',
          'root_id': 'root',
          'path': '/media/folder',
          'name': 'folder',
          'available': true,
        };
      } else if (path.endsWith('/playback')) {
        if (round == null && request.uri.queryParameters['create'] == 'false') {
          status = 404;
          result = {
            'error': {'code': 'round_not_started', 'message': 'Choose a scope'},
          };
        } else {
          result =
              round ??
              {
                'id': 'legacy',
                'scope': <String, dynamic>{},
                'order': 'random',
                'window': [],
                'current': null,
                'revision': 0,
                'position': 0,
                'total': 0,
                'finished': true,
              };
        }
      } else if (path.endsWith('/rounds')) {
        creates.add(body);
        final position = int.parse(
          (body['anchor_video_id'] as String? ?? 'v0').substring(1),
        );
        round ??= summary(position: position);
        status = 201;
        result = round!;
        if (loseCreate) {
          loseCreate = false;
          status = 503;
          result = {
            'error': {'code': 'lost', 'message': 'Response lost'},
          };
        }
      } else if (path.endsWith('/order')) {
        orders.add(body);
        final key = body['request_id'] as String;
        round = orderResults.putIfAbsent(
          key,
          () => {
            ...round!,
            'order': body['order'],
            'revision': (round!['revision'] as int) + 1,
            'sequence_revision': (round!['sequence_revision'] as int) + 1,
          },
        );
        result = round!;
        if (loseOrder) {
          loseOrder = false;
          status = 503;
          result = {
            'error': {'code': 'lost', 'message': 'Response lost'},
          };
        }
      } else if (path.endsWith('/position')) {
        round = summary(
          position: int.parse((body['video_id'] as String).substring(1)),
          revision: (round!['revision'] as int) + 1,
          sequence: round!['sequence_revision'] as int,
        );
        result = {...round!};
        if (releaseMove != null) {
          moveStarted!.complete();
          await releaseMove!.future;
        }
      } else if (path.endsWith('/opened')) {
        opens.add(body);
        result = {'video_id': body['video_id'], 'opened_at': 123.0};
      } else if (path.endsWith('/entries')) {
        final version = request.uri.queryParameters['v'];
        if (version != null && version != '${round!['sequence_revision']}') {
          status = 409;
          result = {
            'error': {
              'code': 'round_order_changed',
              'message': 'Order changed',
            },
          };
        } else {
          final offset = int.parse(
            request.uri.queryParameters['offset'] ?? '0',
          );
          final limit = int.parse(request.uri.queryParameters['limit'] ?? '48');
          result = {
            'items': [
              for (var i = offset; i < 30 && i < offset + limit; i++)
                {'position': i, 'video': video(i)},
            ],
            'offset': offset,
            'limit': limit,
            'total': 30,
            'sequence_revision': round!['sequence_revision'],
          };
        }
      } else if (path.endsWith('/videos')) {
        final unavailable = request.uri.queryParameters['status'] == 'missing';
        final restoring = request.uri.queryParametersAll['anchor_ids'];
        final offset = restoring == null
            ? int.parse(request.uri.queryParameters['offset'] ?? '0')
            : 24;
        final limit = int.parse(request.uri.queryParameters['limit'] ?? '24');
        result = {
          'items': [
            if (!unavailable)
              for (var i = offset; i < 30 && i < offset + limit; i++) video(i),
          ],
          'total': unavailable ? 0 : 30,
          'offset': offset,
          'limit': limit,
          if (restoring != null) 'anchor_index': 28,
        };
      } else {
        result = {'items': [], 'total': 0};
      }
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
  }
}

void main() {
  late PreviewServer fixture;
  late ServerLibraryRepository repo;
  setUp(() async {
    fixture = PreviewServer();
    await fixture.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
  });
  tearDown(() async {
    repo.dispose();
    await fixture.server.close(force: true);
  });
  Future<void> connect() =>
      repo.connect('http://127.0.0.1', fixture.server.port, 'test-only');

  test('return location sends bounded stable IDs and accepts the located page offset', () async {
    await connect();
    final result = await repo.restoreVideoEntry(
      VideoEntryScope(search: 'folder', sort: VideoSort.name),
      anchors: ['removed', 'v28', 'v29'],
      fallbackIndex: 40,
    );
    final request = fixture.reads.last;
    expect(request.queryParametersAll['anchor_ids'], ['removed', 'v28', 'v29']);
    expect(request.queryParameters['offset'], '40');
    expect(request.queryParameters['search'], 'folder');
    expect(request.queryParameters['sort'], 'name');
    expect(result.offset, 24);
    expect(result.anchorIndex, 28);
    expect(result.items.first.id, 'v24');
    expect(repo.playbackIdentity, isEmpty);
  });

  test('connect and catalog reads do not start a round; begin sends the complete entry', () async {
    await connect();
    expect(repo.current, isNull);
    expect(repo.savedPreviewEntry, isNull);
    expect(repo.playbackIdentity, isEmpty);
    expect(
      fixture.reads
          .where((uri) => uri.path.endsWith('/playback'))
          .single
          .queryParameters['create'],
      'false',
    );
    final entry = VideoEntryScope(
      query: VideoQuery(
        folder: '/media/folder',
        tags: {'b', 'a'},
        orientation: 'portrait',
        duration: 'short',
        type: 'MP4',
      ),
      search: 'folder',
      source: BrowseSource.tags,
      sort: VideoSort.name,
    );
    final page = await repo.loadVideoEntry(entry);
    expect(page.items.length, 24);
    expect(page.total, 30);
    expect(fixture.creates, isEmpty);
    expect(fixture.opens, isEmpty);
    fixture.loseCreate = true;
    await expectLater(
      repo.beginPreview(entry, anchor: 'v25'),
      throwsA(isA<LibraryFailure>()),
    );
    await repo.beginPreview(entry, anchor: 'v25');
    final saved = repo.savedPreviewEntry!;
    expect(saved.search, entry.search);
    expect(saved.source, entry.source);
    expect(saved.sort, entry.sort);
    expect(saved.query.tags, entry.query.tags);
    expect(saved.query.folder, entry.query.folder);
    expect(fixture.creates[0], fixture.creates[1]);
    expect(fixture.creates.last, containsPair('membership', 'fixed'));
    expect(fixture.creates.last['scope'], {
      'directory_id': 'folder-id',
      'tag_ids': ['a', 'b'],
      'orientation': 'portrait',
      'duration': 'short',
      'file_type': 'MP4',
      'search': 'folder',
    });
    expect(fixture.creates.last['source'], 'tags');
    expect(fixture.creates.last['sort'], 'name');
    expect(repo.current!.id, 'v25');
    expect(repo.playbackTotal, 30);
    expect(repo.snapshot.round.length, 3);
    expect(repo.fixedPreview, isTrue);
    expect(fixture.opens, isEmpty);
    await Future.wait([
      repo.recordVideoOpened('v25'),
      repo.recordVideoOpened('v25'),
    ]);
    await repo.recordVideoOpened('v25');
    expect(fixture.opens.length, 1);
  });

  test('order response retry is idempotent and invalidates queue identity without creating another scope', () async {
    await connect();
    await repo.beginPreview(VideoEntryScope(), anchor: 'v5');
    final previous = repo.playbackSequenceIdentity;
    fixture.loseOrder = true;
    await expectLater(
      repo.changePreviewOrder(PlayOrder.sequential),
      throwsA(isA<LibraryFailure>()),
    );
    await repo.changePreviewOrder(PlayOrder.sequential);
    expect(fixture.orders[0], fixture.orders[1]);
    expect(repo.playbackSequenceIdentity, isNot(previous));
    expect(repo.playbackIdentity, 'fixed-range');
    expect(repo.current!.id, 'v5');
    await repo.newRound();
    expect(fixture.orders.last['restart'], isTrue);
    expect(fixture.creates.length, 1);
  });

  test('late position receipt cannot replace a newer refreshed and reordered session', () async {
    await connect();
    await repo.beginPreview(VideoEntryScope());
    fixture.moveStarted = Completer<void>();
    fixture.releaseMove = Completer<void>();
    final moving = repo.moveToVideo('v6');
    final rejected = expectLater(moving, throwsA(isA<RequestCancelled>()));
    await fixture.moveStarted!.future;
    await repo.refresh();
    await repo.changePreviewOrder(PlayOrder.sequential);
    fixture.releaseMove!.complete();
    await rejected;
    expect(repo.current!.id, 'v6');
    expect(repo.snapshot.order, PlayOrder.sequential);
    expect(repo.playbackSequenceIdentity, endsWith(':1'));
  });

  test('an externally changed queue rejects stale pages and refreshes its ordering identity', () async {
    await connect();
    await repo.beginPreview(VideoEntryScope());
    fixture.round = {...fixture.round!, 'sequence_revision': 1, 'revision': 1};
    await expectLater(
      repo.loadPlaybackVideos(),
      throwsA(isA<RequestCancelled>()),
    );
    expect(repo.playbackSequenceIdentity, endsWith(':1'));
    final page = await repo.loadPlaybackVideos(offset: 24, limit: 6);
    expect(page.items.map((video) => video.id).toList(), [
      'v24',
      'v25',
      'v26',
      'v27',
      'v28',
      'v29',
    ]);
    expect(
      fixture.reads
          .where((uri) => uri.path.endsWith('/entries'))
          .last
          .queryParameters['v'],
      '1',
    );
  });

  test('old services keep legacy connection behavior and reject unsupported fixed entry clearly', () async {
    fixture.supportsFixed = false;
    await connect();
    expect(
      fixture.reads
          .where((uri) => uri.path.endsWith('/playback'))
          .single
          .queryParameters,
      isEmpty,
    );
    await expectLater(
      Future.sync(() => repo.beginPreview(VideoEntryScope(search: 'folder'))),
      throwsA(isA<LibraryFailure>()),
    );
    expect(fixture.creates, isEmpty);
  });
}
