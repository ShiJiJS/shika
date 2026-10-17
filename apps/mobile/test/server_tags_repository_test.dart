import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';

void main() {
  late HttpServer server;
  late ServerLibraryRepository repo;
  late Map<String, String> tags;
  late Map<String, Set<String>> links;
  late Map<String, Object> receipts;
  late List<Map<String, dynamic>> writes;
  String? lose;

  Map<String, dynamic> video(String id) => {
    'id': id,
    'root_id': 'root',
    'path': '/media/$id.mp4',
    'width': 100,
    'height': 200,
    'duration': 2.0,
    'type': 'MP4',
    'status': 'available',
    'tag_ids': links[id]!.toList(),
    'thumbnail_url': null,
    'media_url': '/api/v1/videos/$id/stream',
  };

  setUp(() async {
    tags = {'a': '自然', 'k': '保留'};
    links = {
      'v1': {'a', 'k'},
      'v2': {'k'},
      'v3': {'a'},
    };
    receipts = {};
    writes = [];
    lose = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      Object response;
      if (request.method != 'GET') {
        final body = Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        );
        writes.add(body);
        final key = body['request_id'] as String;
        if (receipts.containsKey(key)) {
          response = receipts[key]!;
        } else if (path == '/api/v1/video-tags') {
          final chosen = Set<String>.from(body['tag_ids']);
          for (final id in List<String>.from(body['video_ids'])) {
            switch (body['mode']) {
              case 'replace':
                links[id] = {...chosen};
              case 'remove':
                links[id]!.removeAll(chosen);
              default:
                links[id]!.addAll(chosen);
            }
          }
          response = {'changed': 1, 'added': 1, 'removed': 0};
          receipts[key] = response;
        } else if (path == '/api/v1/tags') {
          if (tags.containsValue(body['name'])) {
            request.response.statusCode = 409;
            response = {
              'error': {'code': 'duplicate_tag', 'message': '已有同名标签'},
            };
          } else {
            tags['new'] = body['name'];
            response = {'id': 'new', 'name': body['name']};
            receipts[key] = response;
          }
        } else {
          final id = path.split('/').last;
          if (request.method == 'DELETE') {
            tags.remove(id);
            for (final assigned in links.values) {
              assigned.remove(id);
            }
            response = {'id': id, 'deleted': true};
          } else {
            tags[id] = body['name'];
            response = {'id': id, 'name': body['name']};
          }
          receipts[key] = response;
        }
        if (lose == path) {
          lose = null;
          (await request.response.detachSocket(writeHeaders: false)).destroy();
          return;
        }
      } else if (path == '/api/v1/info') {
        response = {'api_version': 1, 'server_id': 'tags-fixture'};
      } else if (path == '/api/v1/library-state') {
        response = {'ready': true, 'scanning': false, 'status': 'idle'};
      } else if (path == '/api/v1/roots') {
        response = {
          'items': [
            {
              'id': 'root',
              'name': '媒体',
              'path': '/media',
              'directory_id': 'dir',
              'available': true,
              'error': null,
              'last_scan': null,
            },
          ],
        };
      } else if (path == '/api/v1/playback') {
        response = {
          'id': 'round',
          'order': 'random',
          'scope': {'tag_ids': []},
          'position': 0,
          'total': 3,
          'revision': 0,
          'finished': false,
          'current': video('v1'),
          'window': [
            {'position': 0, 'video': video('v1')},
            {'position': 1, 'video': video('v2')},
          ],
        };
      } else if (path == '/api/v1/tags') {
        response = {
          'items': [
            for (final entry in tags.entries)
              {
                'id': entry.key,
                'name': entry.value,
                'video_count': links.values
                    .where((v) => v.contains(entry.key))
                    .length,
              },
          ],
          'total': tags.length,
        };
      } else if (path == '/api/v1/trash' || query['status'] == 'missing') {
        response = {'items': [], 'total': 0};
      } else {
        response = {'items': links.keys.map(video).toList(), 'total': 3};
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    final credentials = MemoryCredentialStore();
    await credentials.save(
      ConnectionCredentials(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        token: 'fixture-only',
        serverId: 'tags-fixture',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    repo = ServerLibraryRepository(credentials);
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    await server.close(force: true);
  });

  test(
    'accepted tag creation can be retried after losing the HTTP response',
    () async {
      lose = '/api/v1/tags';
      await expectLater(
        repo.editTag(name: '花卉'),
        throwsA(isA<LibraryFailure>()),
      );
      expect(tags['new'], '花卉');
      await repo.editTag(name: '花卉');
      expect(writes, hasLength(2));
      expect(writes.first['request_id'], writes.last['request_id']);
      expect(repo.tagName('new'), '花卉');
      expect(repo.snapshot.tags, hasLength(3));
    },
  );

  test(
    'batch retry reuses its command and preserves unrelated associations',
    () async {
      lose = '/api/v1/video-tags';
      await expectLater(
        repo.setVideoTags({'v1', 'v2'}, {'a'}),
        throwsA(isA<LibraryFailure>()),
      );
      await repo.setVideoTags({'v2', 'v1'}, {'a'});
      expect(writes.first['request_id'], writes.last['request_id']);
      expect(links['v1'], {'a', 'k'});
      expect(links['v2'], {'a', 'k'});
      await repo.setVideoTags({'v1', 'v2'}, {'a'}, remove: true);
      expect(links['v1'], {'k'});
      expect(links['v2'], {'k'});
      expect(repo.current!.tags, {'k'});
    },
  );

  test('tag rename retains ID and deletion invalidates cached pages', () async {
    await repo.loadVideos();
    expect(repo.snapshot.videos.singleWhere((v) => v.id == 'v3').tags, {'a'});
    await repo.editTag(original: 'a', name: '自然改名');
    expect(repo.tagName('a'), '自然改名');
    await repo.editTag(original: 'a', delete: true);
    expect(repo.snapshot.tags, isNot(contains('a')));
    expect(repo.snapshot.videos.any((v) => v.tags.contains('a')), isFalse);
    final result = await repo.loadVideos();
    expect(result.items.any((v) => v.tags.contains('a')), isFalse);
    expect(repo.tagName('a'), isNot('自然改名'));
  });
}
