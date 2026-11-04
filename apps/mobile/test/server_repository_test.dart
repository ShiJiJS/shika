import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';

void main() {
  late HttpServer server;
  late ServerLibraryRepository repo;
  late MemoryCredentialStore credentials;
  final oldStarted = Completer<void>(), releaseOld = Completer<void>();
  var delayed = false;
  var videoDuration = 1.0;
  var dropRoundResponse = false;
  var scanPolls = 0, scanSubmits = 0, missingTotal = 0;
  var rootUnavailable = false, scanFailed = false, renamedDirectory = false;
  Map<String, dynamic> preparation = {};
  final rootWrites = <String>[];
  final rootBodies = <Map<String, dynamic>>[];
  List<String>? capabilities;
  var typedRoot = false, delayRoot = false;
  late Completer<void> delayedRootStarted, releaseRoot;
  final submittedRounds = <Map<String, dynamic>>[];
  Map<String, dynamic> scope = {'tag_ids': <String>[]};
  Map<String, dynamic> emptyRound() => {
    'id': 'round',
    'order': 'random',
    'scope': scope,
    'position': 0,
    'total': 0,
    'revision': 0,
    'finished': true,
    'current': null,
    'window': [],
  };
  Map<String, dynamic> item(String id) => {
    'id': id,
    'root_id': 'root',
    'path': '/media/$id.mp4',
    'width': 100,
    'height': 200,
    'duration': videoDuration,
    'type': 'MP4',
    'status': 'available',
    'tag_ids': [],
    'thumbnail_url': null,
    'media_url': '/api/v1/videos/$id/stream',
  };
  setUp(() async {
    videoDuration = 1.0;
    scope = {'tag_ids': <String>[]};
    dropRoundResponse = false;
    submittedRounds.clear();
    scanPolls = 0;
    scanSubmits = 0;
    missingTotal = 0;
    rootUnavailable = false;
    scanFailed = false;
    renamedDirectory = false;
    rootWrites.clear();
    rootBodies.clear();
    capabilities = null;
    typedRoot = false;
    delayRoot = false;
    delayedRootStarted = Completer<void>();
    releaseRoot = Completer<void>();
    preparation = {'ready': true, 'scanning': false, 'status': 'idle'};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      Object response;
      if (path == '/api/v1/info') {
        response = {
          'api_version': 1,
          'server_id': 'fixture',
          'capabilities': ?capabilities,
        };
      } else if (path == '/api/v1/library-state') {
        response = preparation;
      } else if (path == '/api/v1/roots') {
        if (delayRoot) {
          delayRoot = false;
          delayedRootStarted.complete();
          await releaseRoot.future;
        }
        if (request.method != 'GET') {
          rootWrites.add(request.method);
          rootBodies.add(
            Map<String, dynamic>.from(
              jsonDecode(
                utf8.decode(await request.expand((chunk) => chunk).toList()),
              ) as Map,
            ),
          );
        }
        response = {
          'items': [
            {
              'id': 'root',
              'name': '媒体',
              'path': '/media',
              'directory_id': 'directory',
              'available': !rootUnavailable,
              if (typedRoot) 'kind': 'pack',
              if (typedRoot) 'enabled': false,
              'error': null,
              'last_scan': null,
            },
          ],
        };
      } else if (path == '/api/v1/scans') {
        scanSubmits++;
        response = {'id': 'scan'};
      } else if (path == '/api/v1/tasks/scan') {
        final done = scanPolls++ > 0;
        response = {
          'id': 'scan',
          'status': !done
              ? 'running'
              : scanFailed
              ? 'failed'
              : 'completed',
          'phase': done
              ? scanFailed
                    ? 'failed'
                    : 'completed'
              : 'processing_media',
          'result': {
            'unchanged': 3,
            'roots': [
              {
                'id': 'root',
                'status': rootUnavailable ? 'unavailable' : 'completed',
              },
            ],
          },
        };
      } else if (path == '/api/v1/directories') {
        response = {
          'items': [
            {
              'id': 'child',
              'name': 'old',
              'path': '/media/old',
              'available': true,
            },
          ],
        };
      } else if (path == '/api/v1/directories/resolve') {
        if (renamedDirectory) {
          request.response.statusCode = 404;
          response = {
            'error': {'code': 'directory_not_found', 'message': '原目录已移除'},
          };
        } else {
          response = {
            'id': 'child',
            'name': 'old',
            'path': '/media/old',
            'available': true,
          };
        }
      } else if (path == '/api/v1/playback') {
        response = emptyRound();
      } else if (path == '/api/v1/rounds') {
        final body = jsonDecode(
          utf8.decode(await request.expand((chunk) => chunk).toList()),
        ) as Map;
        scope = Map<String, dynamic>.from(body['scope'] as Map);
        submittedRounds.add(Map<String, dynamic>.from(body));
        if (dropRoundResponse) {
          dropRoundResponse = false;
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
        }
        response = emptyRound();
      } else if (path == '/api/v1/tags') {
        response = {'items': [], 'total': 0};
      } else if (query['status'] == 'missing') {
        response = {
          'total': missingTotal,
          'items': [
            for (
              var i = int.parse(query['offset'] ?? '0');
              i < missingTotal &&
                  i <
                      int.parse(query['offset'] ?? '0') +
                          int.parse(query['limit'] ?? '24');
              i++
            )
              {
                ...item('missing-$i'),
                'status': 'missing',
                'tag_ids': ['keep'],
              },
          ],
        };
      } else if (path == '/api/v1/trash') {
        response = {'items': [], 'total': 0};
      } else if (path == '/api/v1/videos') {
        final old = query['search'] == 'old';
        if (old && delayed) {
          oldStarted.complete();
          await releaseOld.future;
        }
        response = {
          'items': [item(old ? 'old' : 'new')],
          'total': 1,
        };
      } else {
        request.response.statusCode = 404;
        response = {
          'error': {'code': 'not_found', 'message': '不存在'},
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    credentials = MemoryCredentialStore();
    await credentials.save(
      ConnectionCredentials(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        token: 'test-only',
        serverId: 'fixture',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    repo = ServerLibraryRepository(credentials);
  });
  tearDown(() async {
    repo.dispose();
    await server.close(force: true);
  });

  test('fractional duration follows the player whole-second clock', () async {
    videoDuration = 5.98;
    await repo.initialize();
    final page = await repo.loadVideoEntry(VideoEntryScope());
    expect(page.items.single.seconds, 5);
    expect(page.items.single.durationLabel, '0:05');
  });

  test('late old connection cannot publish stale capabilities', () async {
    capabilities = ['typed_roots', 'pack_tags'];
    delayRoot = true;
    final old = repo.initialize();
    final rejected = expectLater(old, throwsA(isA<RequestCancelled>()));
    await delayedRootStarted.future;
    capabilities = null;
    await repo.initialize();
    releaseRoot.complete();
    await rejected;
    expect(repo.snapshot.connected, isTrue);
    expect(repo.capabilities.typedRoots, isFalse);
  });

  test('legacy capabilities keep video writes compatible and reject new root features', () async {
    await repo.initialize();
    expect(repo.capabilities.typedRoots, isFalse);
    expect(repo.capabilities.imagePacks, isFalse);
    expect(repo.snapshot.roots.single.kind, MediaKind.video);
    expect(repo.snapshot.roots.single.enabled, isTrue);
    await repo.saveRoot(const MediaRoot('', '视频', '/media/new'));
    expect(rootBodies.single, {'name': '视频', 'path': '/media/new'});
    await expectLater(
      repo.saveRoot(
        const MediaRoot('', '图包', '/media/packs', kind: MediaKind.pack),
      ),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(
      repo.saveRoot(const MediaRoot('', '停用', '/media/off', enabled: false)),
      throwsA(isA<LibraryFailure>()),
    );
    expect(rootBodies, hasLength(1));
  });

  test(
    'typed capability publishes root flags and expires with connection',
    () async {
      capabilities = ['typed_roots', 'pack_tags', 'future_unknown'];
      typedRoot = true;
      await repo.initialize();
      expect(repo.capabilities.typedRoots, isTrue);
      expect(repo.capabilities.packTags, isTrue);
      expect(repo.capabilities.imagePacks, isFalse);
      expect(repo.snapshot.roots.single.kind, MediaKind.pack);
      expect(repo.snapshot.roots.single.enabled, isFalse);
      expect(repo.folders(''), isEmpty);
      await repo.saveRoot(
        const MediaRoot(
          '',
          '图包',
          '/media/packs',
          kind: MediaKind.pack,
          enabled: false,
        ),
      );
      expect(rootBodies.single, {
        'name': '图包',
        'path': '/media/packs',
        'kind': 'pack',
        'enabled': false,
      });
      await repo.expire();
      expect(repo.capabilities.typedRoots, isFalse);
    },
  );

  test('initial preparation stays locked and live progress does not reload catalog pages', () async {
    expect(repo.libraryPreparation.value.ready, isFalse);
    preparation = {
      'ready': false,
      'scanning': true,
      'status': 'running',
      'task_id': 'initial-scan',
      'phase': 'processing_media',
      'progress': {'discovered': 4065, 'processed': 300},
    };
    await repo.initialize();
    var publications = 0;
    repo.addListener(() => publications++);
    expect(repo.libraryPreparation.value.ready, isFalse);
    expect(repo.libraryPreparation.value.processed, 300);
    preparation['progress'] = {'discovered': 4065, 'processed': 310};
    await repo.pollPreparation(repo.api, 1);
    expect(repo.libraryPreparation.value.processed, 310);
    expect(publications, 0);
    preparation = {
      'ready': true,
      'scanning': false,
      'status': 'completed',
      'task_id': 'initial-scan',
      'phase': 'completed',
      'progress': {'discovered': 4065, 'processed': 4065},
    };
    await repo.pollPreparation(repo.api, 1);
    expect(repo.libraryPreparation.value.ready, isTrue);
    expect(publications, 1);
  });

  test(
    'empty current video can be reopened and selected without expanding scope',
    () async {
      await repo.initialize();
      expect(repo.snapshot.connected, isTrue);
      expect(repo.current, isNull);
      expect(repo.playbackTotal, 0);
      await repo.setScope(VideoQuery(type: 'MOV', tags: {'tag'}));
      expect(repo.current, isNull);
      expect(repo.snapshot.query.type, 'MOV');
      expect(repo.snapshot.query.tags, {'tag'});
      expect(repo.snapshot.round, isEmpty);
    },
  );

  test(
    'background scan completion invalidates externally renamed directory paths',
    () async {
      await repo.initialize();
      await repo.loadFolders('/media');
      expect(await repo.directoryId('/media/old'), 'child');
      renamedDirectory = true;
      preparation = {
        'ready': true,
        'scanning': false,
        'status': 'completed',
        'phase': 'completed',
        'task_id': 'background-scan',
      };
      await repo.pollPreparation(repo.api, 1);
      await expectLater(
        repo.directoryId('/media/old'),
        throwsA(isA<LibraryFailure>()),
      );
      expect(scanSubmits, 0);
    },
  );

  test('a cancelled old page cannot publish after a newer search', () async {
    await repo.initialize();
    delayed = true;
    final old = repo.loadVideos(search: 'old');
    final cancelled = expectLater(old, throwsA(isA<RequestCancelled>()));
    await oldStarted.future;
    final newest = await repo.loadVideos(search: 'new');
    releaseOld.complete();
    await cancelled;
    expect(newest.items.single.id, 'new');
    expect(repo.snapshot.videos.map((v) => v.id), ['new']);
    expect(repo.snapshot.connected, isTrue);
  });

  test(
    'retrying a round after losing the accepted response reuses its command ID',
    () async {
      await repo.initialize();
      dropRoundResponse = true;
      await expectLater(
        repo.setScope(VideoQuery(type: 'MOV')),
        throwsA(isA<LibraryFailure>()),
      );
      expect(repo.snapshot.connected, isTrue);
      expect(repo.snapshot.query.type, isEmpty);
      await repo.setScope(VideoQuery(type: 'MOV'));
      expect(repo.snapshot.query.type, 'MOV');
      expect(submittedRounds, hasLength(2));
      expect(
        submittedRounds.first['request_id'],
        submittedRounds.last['request_id'],
      );
    },
  );

  test(
    'missing records are paged independently of the visited playback cache',
    () async {
      missingTotal = 25;
      await repo.initialize();
      expect(repo.missingCount, 25);
      expect(repo.snapshot.videos, isEmpty);
      final first = await repo.loadMissing();
      final next = await repo.loadMissing(offset: 24);
      expect(first.items, hasLength(24));
      expect(next.items.single.id, 'missing-24');
      expect(next.items.single.tags, {'keep'});
      expect(repo.current, isNull);
    },
  );

  test('new media root submits a creation and scan progress does not duplicate jobs', () async {
    await repo.initialize();
    await repo.saveRoot(const MediaRoot('', '新目录', '/media/new'));
    expect(rootWrites, ['POST']);
    final progress = <String>[];
    repo.scanStatus.addListener(() {
      if (repo.scanStatus.value != null) progress.add(repo.scanStatus.value!);
    });
    await Future.wait([repo.refresh(), repo.refresh()]);
    expect(scanSubmits, 1);
    expect(progress.any((s) => s.contains('正在读取视频信息')), isTrue);
    expect(progress.last, contains('扫描完成'));
  });

  test('unavailable root and failed scan publish authoritative status without fake success', () async {
    await repo.initialize();
    rootUnavailable = true;
    await expectLater(
      repo.refresh(),
      throwsA(predicate((e) => e.toString().contains('1 个目录不可用'))),
    );
    expect(repo.snapshot.roots.single.available, isFalse);
    expect(repo.missingCount, 0);
    rootUnavailable = false;
    scanFailed = true;
    scanPolls = 0;
    await expectLater(
      repo.refresh(),
      throwsA(predicate((e) => e.toString().contains('扫描未完成'))),
    );
    expect(repo.scanStatus.value, contains('原有标签记录保留'));
    scanFailed = false;
    scanPolls = 0;
    await repo.refresh();
    expect(scanSubmits, 3);
    expect(repo.snapshot.roots.single.available, isTrue);
  });

  test(
    'scan clears cached directory paths that disappeared outside the app',
    () async {
      await repo.initialize();
      await repo.loadFolders('/media');
      expect(await repo.directoryId('/media/old'), 'child');
      renamedDirectory = true;
      await repo.refresh();
      await expectLater(
        repo.directoryId('/media/old'),
        throwsA(isA<LibraryFailure>()),
      );
    },
  );
}
