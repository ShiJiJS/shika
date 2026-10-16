import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';

void main() {
  late HttpServer server;
  late ServerLibraryRepository repo;
  late MemoryCredentialStore credentials;
  final oldStarted = Completer<void>(), releaseOld = Completer<void>();
  var delayed = false;
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
    'duration': 1.0,
    'type': 'MP4',
    'status': 'available',
    'tag_ids': [],
    'thumbnail_url': null,
    'media_url': '/api/v1/videos/$id/stream',
  };
  setUp(() async {
    scope = {'tag_ids': <String>[]};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      Object response;
      if (path == '/api/v1/info') {
        response = {'api_version': 1, 'server_id': 'fixture'};
      } else if (path == '/api/v1/roots') {
        response = {
          'items': [
            {
              'id': 'root',
              'name': '媒体',
              'path': '/media',
              'directory_id': 'directory',
              'available': true,
              'error': null,
              'last_scan': null,
            },
          ],
        };
      } else if (path == '/api/v1/playback') {
        response = emptyRound();
      } else if (path == '/api/v1/rounds') {
        final body = jsonDecode(
          utf8.decode(await request.expand((chunk) => chunk).toList()),
        ) as Map;
        scope = Map<String, dynamic>.from(body['scope'] as Map);
        response = emptyRound();
      } else if (path == '/api/v1/tags') {
        response = {'items': [], 'total': 0};
      } else if (path == '/api/v1/trash' || query['status'] == 'missing') {
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
}
