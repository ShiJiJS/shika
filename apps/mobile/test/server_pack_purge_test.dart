import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart' hide Json;

import 'server_pack_catalog_test.dart' show PackServer;
import 'support/pack_purge_fixture.dart';

void main() {
  late PackServer server;
  late ServerLibraryRepository repo;
  late PackPurgeGateway gateway;
  var supported = true, malformed = '';
  Completer<void>? started, release;
  final calls = <String>[];
  setUp(() async {
    server = PackServer();
    calls.clear();
    supported = true;
    malformed = '';
    started = release = null;
    server.handle = (HttpRequest request, Json body) async {
      final path = request.uri.path, query = request.uri.queryParameters;
      calls.add('${request.method} $path');
      if (path == '/api/v1/info') {
        return (
          status: 200,
          body: {
            'api_version': 1,
            'server_id': 'packs',
            'capabilities': [
              'image_packs',
              'pack_tags',
              'pack_logical_trash',
              'pack_purge_preview',
              if (supported) 'pack_permanent_delete',
            ],
          },
        );
      }
      if (path == '/api/v1/pack-purge-plans' ||
          path == '/api/v1/pack-purge-plans/plan' ||
          path.contains('/pack-purge-requests/')) {
        if (path.endsWith('/missing')) {
          return (
            status: 404,
            body: {
              'error': {'code': 'not_found', 'message': 'Unknown'},
            },
          );
        }
        if (started != null) {
          started!.complete();
          await release!.future;
        }
        final value = purgePlanJson(
          malformed == 'membership' ? ['other'] : ['trash-0'],
        );
        if (malformed == 'identity') value['id'] = 'other';
        if (malformed == 'ready') value['digest'] = null;
        if (malformed == 'count') value['result']['image_bytes'] = 400;
        return (status: 200, body: value);
      }
      if (path.endsWith('/files')) {
        final plan = PackPurgePlan(purgePlanJson(['trash-0']));
        final offset = int.parse(query['offset']!),
            limit = int.parse(query['limit']!);
        final items = [
          for (var i = offset; i < 3 && i < offset + limit; i++)
            {
              'id': 'page-$i',
              'relative_path': '$i.jpg',
              'path': '${plan.members.single.path}/$i.jpg',
              'size': 100,
              'sha256': purgeHash,
              'signature': [
                '37',
                '33837',
                100,
                '1792884555250765506',
                '1792884555250765506',
              ],
            },
        ];
        if (malformed == 'image-path') items.first['path'] = '/outside.jpg';
        if (malformed == 'duplicate') {
          items[1]['id'] = items[0]['id']!;
        }
        return (
          status: 200,
          body: {
            'items': items,
            'total': malformed == 'total' ? 4 : 3,
            'offset': offset,
            'limit': limit,
          },
        );
      }
      if (path.endsWith('/pages')) {
        return (
          status: 200,
          body: {
            'items': [
              {
                'id': 's',
                'pack_id': 'p',
                'pack_name': '图包',
                'kind': 'image',
                'relative_path': '2.jpg',
                'phase': 'prepared',
                'outcome': 'failed',
                'error': 'permission_denied',
              },
            ],
            'total': 1,
            'offset': 0,
            'limit': 24,
          },
        );
      }
      return null;
    };
    await server.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await repo.connect('http://127.0.0.1', server.server.port, 'test');
    gateway = repo.createPackPurge();
  });
  tearDown(() async {
    gateway.dispose();
    repo.dispose();
    await server.server.close(force: true);
  });
  test('preparation, read-only receipt, exact image pagination and unfinished results use typed API', () async {
    final plan = await gateway.prepare('review', ['trash-0']);
    expect(plan.imageCount, 3);
    expect((await gateway.receipt('review'))!.id, 'plan');
    expect(await gateway.receipt('missing'), isNull);
    final images = await gateway.images(
      plan,
      plan.members.single,
      offset: 1,
      limit: 1,
    );
    expect(images.items.single.relativePath, '1.jpg');
    expect(images.total, 3);
    final steps = await gateway.steps('operation');
    expect(steps.items.single.packName, '图包');
    expect(steps.items.single.outcome, 'failed');
    expect(
      calls.where((v) => v.startsWith('POST') && !v.contains('/auth/login')),
      ['POST /api/v1/pack-purge-plans'],
    );
  });
  for (final failure in ['membership', 'ready', 'count']) {
    test('rejects malformed prepared plan $failure', () async {
      malformed = failure;
      await expectLater(
        gateway.prepare('review', ['trash-0']),
        throwsA(isA<LibraryFailure>()),
      );
    });
  }
  test('GET identity mismatch and malformed paginated files never become confirmation', () async {
    malformed = 'identity';
    await expectLater(gateway.plan('plan'), throwsA(isA<LibraryFailure>()));
    malformed = '';
    final plan = await gateway.prepare('review', ['trash-0']);
    for (final failure in ['image-path', 'duplicate', 'total']) {
      malformed = failure;
      await expectLater(
        gateway.images(plan, plan.members.single),
        throwsA(isA<LibraryFailure>()),
      );
    }
  });
  test('old capability does not permit creating purge gateway', () async {
    supported = false;
    await repo.connect('http://127.0.0.1', server.server.port, 'test');
    expect(() => repo.createPackPurge(), throwsA(isA<LibraryFailure>()));
    expect(gateway.isCurrent, isFalse);
  });
  test(
    'disposal cancels an in-flight preparation and its late receipt',
    () async {
      started = Completer<void>();
      release = Completer<void>();
      final work = gateway.prepare('review', ['trash-0']);
      final failure = expectLater(work, throwsA(isA<RequestCancelled>()));
      await started!.future;
      gateway.dispose();
      release!.complete();
      await failure;
      expect(gateway.isCurrent, isFalse);
    },
  );
}
