import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';

typedef Json = Map<String, dynamic>;

class PackServer {
  late HttpServer server;
  bool supported = true, unavailableDirectory = false, foreignCover = false;
  bool readingSupported = false;
  FutureOr<({int status, Json body})?> Function(HttpRequest, Json)? handle;
  bool loseWrite = false, unauthorized = false;
  final reads = <Uri>[];
  final writes = <({String path, Json body})>[];
  final packTags = <String, String>{'same-id': '同名'};
  final videoTags = <String, String>{'same-id': '同名'};
  bool unauthorizedVideoTags = false;
  Completer<void>? blockedTags, releaseTags;
  final receipts = <String, Json>{};
  final links = <String>{'same-id', 'keep'};
  Completer<void>? blocked, release;
  Completer<void>? selectionBlocked, selectionRelease;
  Completer<void>? writeBlocked, writeRelease;
  Completer<void>? namesBlocked, namesRelease;
  Json? namesOverride;
  bool incompletePackNames = false;
  Json? anchorOverride;
  bool anchorFailure = false;
  Json? selectionOverride;
  int loseWriteAt = 0;
  Json pack(int index) => {
    'id': 'p$index',
    'root_id': 'pack-root',
    'path': '/packs/套图$index',
    'name': '套图$index',
    'page_count': 500,
    'readable_count': 499,
    'content_version': 7,
    'status': 'available',
    'created_at': 12.0,
    'error': null,
    'tag_ids': links.toList(),
    'tag_names': incompletePackNames
        ? {}
        : {for (final id in links) id: packTags[id] ?? '保留'},
    'cover_url': foreignCover
        ? 'https://foreign.invalid/cover'
        : '/api/v1/packs/p$index/cover?v=7',
    'progress': {
      'page_id': 'page-2',
      'page_index': 1,
      'offset_ratio': .3,
      'completed': false,
      'revision': 4,
      'updated_at': 15.0,
    },
  };
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final path = r.uri.path;
      Json body = {};
      if (r.method != 'GET') {
        final text = await utf8.decoder.bind(r).join();
        if (text.isNotEmpty) body = Map<String, dynamic>.from(jsonDecode(text));
        if (!path.endsWith('/auth/login')) writes.add((path: path, body: body));
      } else {
        reads.add(r.uri);
      }
      var status = 200;
      Object result;
      final special = await handle?.call(r, body);
      if (special != null) {
        status = special.status;
        result = special.body;
      } else if (path.endsWith('/auth/login')) {
        result = {
          'access_token': 'pack-test-token',
          'expires_at': 4000000000,
          'server_id': 'packs',
        };
      } else if (path.endsWith('/info')) {
        result = {
          'api_version': 1,
          'server_id': 'packs',
          'capabilities': [
            if (supported) ...[
              'image_packs',
              'pack_tags',
              'typed_roots',
              'catalog_selection',
              'pack_tag_names',
              'pack_entry_anchors',
              if (readingSupported) 'pack_reading_sessions',
            ],
          ],
        };
      } else if (path.endsWith('/selection')) {
        expect(r.headers.value('Authorization'), 'Bearer pack-test-token');
        if (selectionBlocked != null &&
            r.uri.queryParameters['search'] == 'blocked') {
          selectionBlocked!.complete();
          await selectionRelease!.future;
        }
        final ids = [for (var i = 0; i < 1027; i++) 'selected-$i'];
        result =
            selectionOverride ??
            {
              'kind': path.contains('/packs/') ? 'pack' : 'video',
              'ids': ids,
              'total': ids.length,
            };
      } else if (path.contains('/packs') ||
          path.contains('/pack-tags') ||
          path.contains('/pack-tag-links') ||
          r.uri.queryParameters['kind'] == 'pack') {
        expect(r.headers.value('Authorization'), 'Bearer pack-test-token');
        if (unauthorized) {
          status = 401;
          result = {
            'error': {'code': 'expired', 'message': 'Expired'},
          };
        } else if (path.endsWith('/pack-tags/resolve')) {
          final ids = r.uri.queryParametersAll['tag_ids']!;
          result =
              namesOverride ??
              {
                'kind': 'pack',
                'items': [
                  for (final id in ids)
                    if (packTags.containsKey(id))
                      {'id': id, 'name': packTags[id], 'kind': 'pack'},
                ],
                'missing_ids': ids
                    .where((id) => !packTags.containsKey(id))
                    .toList(),
              };
          if (namesBlocked != null && !namesBlocked!.isCompleted) {
            namesBlocked!.complete();
            await namesRelease!.future;
          }
        } else if (path.endsWith('/directories/resolve')) {
          result = {'id': 'pack-directory', 'available': !unavailableDirectory};
        } else if (path.endsWith('/directories')) {
          result = {
            'items': [
              {
                'id': 'child',
                'name': '子目录',
                'path': '/packs/子目录',
                'available': true,
              },
            ],
            'total': 51,
            'offset': int.parse(r.uri.queryParameters['offset']!),
            'limit': int.parse(r.uri.queryParameters['limit']!),
          };
        } else if (path.endsWith('/packs')) {
          if (blocked != null && r.uri.queryParameters['search'] == 'blocked') {
            blocked!.complete();
            await release!.future;
          }
          final offset = int.parse(r.uri.queryParameters['offset']!);
          if (r.uri.queryParametersAll.containsKey('anchor_ids')) {
            if (anchorFailure) {
              status = 503;
              result = {
                'error': {'code': 'fixture_anchor', 'message': '定位暂时失败'},
              };
            } else {
              result =
                  anchorOverride ??
                  {
                    'items': [for (var i = 48; i < 72; i++) pack(i)],
                    'total': 73,
                    'offset': 48,
                    'limit': 24,
                    'anchor_index': 58,
                  };
            }
          } else {
            result = {
              'items': [pack(offset)],
              'total': 51,
              'offset': offset,
              'limit': int.parse(r.uri.queryParameters['limit']!),
            };
          }
        } else if (r.method == 'GET') {
          final search = r.uri.queryParameters['search'] ?? '';
          final all = packTags.entries
              .where((e) => e.value.contains(search))
              .toList();
          final offset = int.parse(r.uri.queryParameters['offset']!);
          final limit = int.parse(r.uri.queryParameters['limit']!);
          result = {
            'items': [
              for (final e in all.skip(offset).take(limit))
                {'id': e.key, 'name': e.value, 'kind': 'pack', 'pack_count': 1},
            ],
            'total': all.length,
            'offset': offset,
            'limit': limit,
          };
        } else {
          final key = body['request_id'] as String;
          result = receipts.putIfAbsent(key, () {
            if (path.endsWith('/pack-tag-links')) {
              if (body['mode'] == 'replace') links.clear();
              links.addAll(List<String>.from(body['tag_ids']));
            } else if (r.method == 'DELETE') {
              packTags.remove(path.split('/').last);
            } else {
              packTags[path.endsWith('/pack-tags')
                      ? 'new-tag'
                      : Uri.decodeComponent(path.split('/').last)] =
                  body['name'];
            }
            return <String, dynamic>{
              'changed': 1,
              if (path.endsWith('/pack-tags')) ...{
                'id': 'new-tag',
                'name': body['name'],
                'pack_count': 0,
              },
            };
          });
          if (loseWrite || writes.length == loseWriteAt) {
            loseWrite = false;
            status = 503;
            result = {
              'error': {'code': 'lost', 'message': 'Lost receipt'},
            };
          }
        }
        if (path.endsWith('/pack-tag-links') &&
            writeBlocked != null &&
            !writeBlocked!.isCompleted) {
          writeBlocked!.complete();
          await writeRelease!.future;
        }
      } else if (path.endsWith('/tags')) {
        expect(r.headers.value('Authorization'), 'Bearer pack-test-token');
        if (r.uri.queryParameters['search'] == 'blocked' &&
            blockedTags != null) {
          blockedTags!.complete();
          await releaseTags!.future;
        }
        final matching = videoTags.entries
            .where(
              (e) => e.value.contains(r.uri.queryParameters['search'] ?? ''),
            )
            .toList();
        final offset = int.parse(r.uri.queryParameters['offset'] ?? '0');
        final limit = int.parse(r.uri.queryParameters['limit'] ?? '200');
        if (unauthorizedVideoTags) {
          status = 401;
          result = {
            'error': {'code': 'expired', 'message': 'Expired'},
          };
        } else {
          result = {
            'items': [
              for (final tag in matching.skip(offset).take(limit))
                {
                  'id': tag.key,
                  'name': tag.value,
                  'video_count': tag.key == 'same-id' ? 7 : 3,
                },
            ],
            'total': matching.length,
            'offset': offset,
            'limit': limit,
          };
        }
      } else if (path.endsWith('/library-state')) {
        result = {'ready': true, 'scanning': false};
      } else if (path.endsWith('/playback')) {
        result = {
          'id': 'existing',
          'scope': <String, dynamic>{},
          'order': 'random',
          'position': 0,
          'total': 0,
          'revision': 0,
          'finished': true,
          'window': [],
          'current': null,
        };
      } else {
        result = {'items': [], 'total': 0};
      }
      try {
        r.response.statusCode = status;
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(result));
        await r.response.close();
      } on IOException {
        /* A cancelled catalog request may have closed its socket. */
      }
    });
  }
}

void main() {
  late PackServer fixture;
  late ServerLibraryRepository repo;
  setUp(() async {
    fixture = PackServer();
    await fixture.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
  });
  tearDown(() async {
    repo.dispose();
    await fixture.server.close(force: true);
  });
  Future<void> connect() =>
      repo.connect('http://127.0.0.1', fixture.server.port, 'fixture');

  test('video label search and paging read authoritative labels absent from the legacy snapshot', () async {
    await connect();
    expect(repo.snapshot.tags, ['same-id']);
    fixture.videoTags.addAll({for (var i = 0; i < 61; i++) 'v$i': '新增标签$i'});
    final page = await repo.loadVideoTags(
      search: '新增标签',
      offset: 50,
      limit: 10,
    );
    expect(page.total, 61);
    expect(page.offset, 50);
    expect(page.limit, 10);
    expect(page.items.map((t) => t.id), [for (var i = 50; i < 60; i++) 'v$i']);
    expect(page.items.every((t) => t.count == 3), isTrue);
    expect(repo.tagName('v50'), '新增标签50');
    expect(repo.snapshot.tags, [
      'same-id',
    ], reason: 'the new list does not depend on the legacy complete cache');
    final request = fixture.reads.last;
    expect(request.path, '/api/v1/tags');
    expect(request.queryParameters, {
      'search': '新增标签',
      'offset': '50',
      'limit': '10',
    });
    expect((await repo.loadPackTags()).items.single.name, '同名');
    expect(repo.tagName('same-id'), '同名');
  });

  test('video label cancellation is independent of media and pack-label reads; superseded labels are rejected', () async {
    await connect();
    fixture.blockedTags = Completer<void>();
    fixture.releaseTags = Completer<void>();
    final pending = repo.loadVideoTags(search: 'blocked');
    await fixture.blockedTags!.future;
    repo.cancelVideoRead();
    repo.cancelPackRead();
    repo.cancelPackTagRead();
    fixture.releaseTags!.complete();
    expect((await pending).total, 0);
    fixture.blockedTags = Completer<void>();
    fixture.releaseTags = Completer<void>();
    final obsolete = repo.loadVideoTags(search: 'blocked');
    final cancelled = expectLater(obsolete, throwsA(isA<RequestCancelled>()));
    await fixture.blockedTags!.future;
    final current = await repo.loadVideoTags();
    fixture.releaseTags!.complete();
    await cancelled;
    expect(current.items.single.count, 7);
  });

  test('unauthorized video labels expire the common connection instead of displaying stale cached labels', () async {
    await connect();
    fixture.unauthorizedVideoTags = true;
    await expectLater(repo.loadVideoTags(), throwsA(isA<ApiFailure>()));
    expect(repo.snapshot.connected, isFalse);
    expect(repo.snapshot.tags, isEmpty);
  });

  test('whole-pack catalog sends complete typed filters and keeps authoritative paging, progress and authorized cover', () async {
    await connect();
    final identity = repo.playbackIdentity;
    final page = await repo.loadPacks(
      PackQuery(
        folder: '/packs',
        search: '套图',
        tags: {'b', 'a'},
        readState: PackReadState.reading,
        sort: PackSort.newest,
      ),
      offset: 24,
      limit: 7,
    );
    expect(page.total, 51);
    expect(page.offset, 24);
    expect(page.limit, 7);
    expect(page.hasMore, isTrue);
    final read = fixture.reads.lastWhere((u) => u.path.endsWith('/packs'));
    expect(read.queryParameters['directory_id'], 'pack-directory');
    expect(read.queryParametersAll['tag_ids'], ['a', 'b']);
    expect(read.queryParameters['read_state'], 'reading');
    expect(read.queryParameters['sort'], 'newest');
    expect(read.queryParameters['search'], '套图');
    final pack = page.items.single;
    expect(pack.pageCount, 500);
    expect(pack.readableCount, 499);
    expect(pack.contentVersion, 7);
    expect(pack.readState, PackReadState.reading);
    expect(pack.progress!.pageId, 'page-2');
    expect(pack.progress!.offsetRatio, .3);
    expect(Uri.parse(pack.cover!.location).queryParameters['v'], '7');
    expect(pack.cover!.headers['Authorization'], 'Bearer pack-test-token');
    expect(pack.cover!.asset, isFalse);
    expect(repo.playbackIdentity, identity);
    expect(fixture.writes, isEmpty);
  });

  test('pack tag edits and batch append/replace preserve the separate video namespace and retry a lost receipt', () async {
    await connect();
    fixture.loseWrite = true;
    await expectLater(
      repo.editPackTag(name: ' 新建 '),
      throwsA(isA<ApiFailure>()),
    );
    await repo.editPackTag(name: ' 新建 ');
    expect(
      fixture.writes[0].body['request_id'],
      fixture.writes[1].body['request_id'],
    );
    expect(fixture.packTags.values.where((n) => n == '新建'), hasLength(1));
    await repo.editPackTag(original: 'same-id', name: '图包改名');
    final tags = await repo.loadPackTags(search: '图包', limit: 1);
    expect(tags.total, 1);
    expect(tags.items.single.name, '图包改名');
    expect(tags.items.single.count, 1);
    expect(repo.tagName('same-id'), '同名');
    expect(repo.tagVideoCount('same-id'), 7);
    await repo.setPackTags({'p1'}, {'new-tag'});
    expect(fixture.links, {'same-id', 'keep', 'new-tag'});
    await repo.setPackTags({'p1'}, {'new-tag'}, replace: true);
    expect(fixture.links, {'new-tag'});
    await repo.editPackTag(original: 'same-id', delete: true);
    expect(fixture.packTags.containsKey('same-id'), isFalse);
    expect(repo.tagName('same-id'), '同名');
    expect(fixture.writes.every((w) => w.path.contains('/pack-')), isTrue);
  });

  test('inline pack tag creation returns its authoritative ID without a first-page lookup', () async {
    await connect();
    final before = fixture.reads
        .where((u) => u.path.endsWith('/pack-tags'))
        .length;
    final tag = await repo.createPackTag(' 新建图包标签 ');
    expect(tag.id, 'new-tag');
    expect(tag.name, '新建图包标签');
    expect(tag.count, 0);
    expect(
      fixture.reads.where((u) => u.path.endsWith('/pack-tags')).length,
      before,
    );
    expect(repo.tagName('same-id'), '同名');
  });

  test('pack folders are typed and paginated; an unavailable folder does not broaden a query', () async {
    await connect();
    final dirs = await repo.loadPackDirectories(
      '/packs',
      offset: 50,
      limit: 10,
    );
    expect(dirs.total, 51);
    expect(dirs.offset, 50);
    expect(dirs.items.single.id, 'child');
    final request = fixture.reads.last;
    expect(request.queryParameters['kind'], 'pack');
    expect(request.queryParameters['parent_id'], 'pack-directory');
    fixture.unavailableDirectory = true;
    final before = fixture.reads.where((u) => u.path.endsWith('/packs')).length;
    await expectLater(
      repo.loadPacks(PackQuery(folder: '/packs')),
      throwsA(isA<LibraryFailure>()),
    );
    expect(
      fixture.reads.where((u) => u.path.endsWith('/packs')).length,
      before,
    );
  });

  test('pack and video cancellation are independent; a superseded pack read is rejected', () async {
    await connect();
    fixture.blocked = Completer<void>();
    fixture.release = Completer<void>();
    final unaffected = repo.loadPacks(PackQuery(search: 'blocked'));
    await fixture.blocked!.future;
    repo.cancelVideoRead();
    fixture.release!.complete();
    expect((await unaffected).items.single.id, 'p0');
    fixture.blocked = Completer<void>();
    fixture.release = Completer<void>();
    final old = repo.loadPacks(PackQuery(search: 'blocked'));
    final cancelled = expectLater(old, throwsA(isA<RequestCancelled>()));
    await fixture.blocked!.future;
    repo.cancelVideoRead();
    final current = await repo.loadPacks(PackQuery(search: 'new'));
    fixture.release!.complete();
    await cancelled;
    expect(current.items.single.id, 'p0');
    final video = await repo.loadVideos();
    expect(video.total, 0);
  });

  test('foreign covers are rejected and unauthorized pack reads expire the shared connection', () async {
    await connect();
    fixture.foreignCover = true;
    await expectLater(
      repo.loadPacks(PackQuery()),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'invalid_media_url'),
      ),
    );
    fixture.foreignCover = false;
    fixture.unauthorized = true;
    await expectLater(repo.loadPacks(PackQuery()), throwsA(isA<ApiFailure>()));
    expect(repo.snapshot.connected, isFalse);
    expect(repo.capabilities.imagePacks, isFalse);
  });

  test('old services reject pack requests explicitly without affecting legacy videos', () async {
    fixture.supported = false;
    await connect();
    await expectLater(
      repo.loadPacks(PackQuery()),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(repo.loadPackTags(), throwsA(isA<LibraryFailure>()));
    expect(fixture.reads.any((u) => u.path.endsWith('/packs')), isFalse);
    expect(repo.snapshot.connected, isTrue);
  });

  test('a pending tag retry belongs to its service and is not sent to another connection', () async {
    await connect();
    fixture.loseWrite = true;
    await expectLater(repo.editPackTag(name: '新建'), throwsA(isA<ApiFailure>()));
    final originalKey = fixture.writes.single.body['request_id'];
    final other = PackServer();
    await other.start();
    addTearDown(() => other.server.close(force: true));
    await repo.connect('http://127.0.0.1', other.server.port, 'fixture');
    await repo.editPackTag(name: '新建');
    expect(other.writes.single.body['request_id'], isNot(originalKey));
    expect(other.packTags['new-tag'], '新建');
  });
}
