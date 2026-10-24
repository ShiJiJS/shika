import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';

import 'server_pack_catalog_test.dart' show PackServer;

typedef Json = Map<String, dynamic>;
void main() {
  late PackServer server;
  late ServerLibraryRepository repo;
  late PackTrashCatalog catalog;
  var supported = true;
  String malformed = '';
  Completer<void>? started, release;
  Json item(int index) => {
    'id': 'trash-$index',
    'operation_id': 'original-$index',
    'original_path': '/packs/套图$index',
    'deleted_at': 1000.0,
    'page_count': 500,
    'pack': {
      ...server.pack(index),
      'status': malformed == 'status' ? 'available' : 'trash',
    },
  };
  setUp(() async {
    server = PackServer();
    supported = true;
    malformed = '';
    started = release = null;
    server.handle = (HttpRequest request, Json body) async {
      final path = request.uri.path, query = request.uri.queryParameters;
      if (path == '/api/v1/info') {
        return (
          status: 200,
          body: {
            'api_version': 1,
            'server_id': 'packs',
            'capabilities': [
              'image_packs',
              'pack_tags',
              if (supported) 'pack_logical_trash',
            ],
          },
        );
      }
      if (path == '/api/v1/pack-trash/selection') {
        if (started != null) {
          started!.complete();
          await release!.future;
        }
        final ids = [for (var i = 0; i < 1027; i++) 'trash-$i'];
        return (
          status: 200,
          body: {
            'kind': malformed == 'kind' ? 'pack' : 'pack-trash',
            'ids': malformed == 'duplicate-selection' ? ['same', 'same'] : ids,
            'total': malformed == 'incomplete-selection'
                ? 1028
                : malformed == 'duplicate-selection'
                ? 2
                : ids.length,
          },
        );
      }
      if (path == '/api/v1/pack-trash') {
        if (query['search'] == 'slow') {
          started!.complete();
          await release!.future;
        }
        final offset = int.parse(query['offset']!),
            limit = int.parse(query['limit']!);
        final items = [
          for (var i = offset; i < 27 && i < offset + limit; i++) item(i),
        ];
        if (malformed == 'duplicate-page') items[1]['id'] = items[0]['id'];
        if (malformed == 'count') items[0]['page_count'] = 3;
        if (malformed == 'date') items[0]['deleted_at'] = 'bad';
        return (
          status: 200,
          body: {
            'items': items,
            'total': malformed == 'total' ? 28 : 27,
            'offset': malformed == 'offset' ? offset + 1 : offset,
            'limit': limit,
          },
        );
      }
      return null;
    };
    await server.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await repo.connect('http://127.0.0.1', server.server.port, 'test');
    catalog = repo.createPackTrash();
  });
  tearDown(() async {
    catalog.dispose();
    repo.dispose();
    await server.server.close(force: true);
  });
  test('typed trash page and complete selection serialize search without video reads', () async {
    final page = await catalog.page(search: '套图 / +%');
    expect(page.items.length, 24);
    expect(page.total, 27);
    expect(page.items.first.id, 'trash-0');
    expect(page.items.first.pack.id, 'p0');
    expect(page.items.first.pack.readState, PackReadState.reading);
    expect(page.items.first.pack.progress!.offsetRatio, .3);
    expect(page.items.first.pack.tags, {'same-id', 'keep'});
    expect(server.reads.last.queryParameters['search'], '套图 / +%');
    final next = await catalog.page(offset: 24);
    expect(next.items.length, 3);
    final ids = await catalog.select('套图 / +%');
    expect(ids.length, 1027);
    expect(ids, contains('trash-1026'));
    expect(server.reads.last.path, '/api/v1/pack-trash/selection');
  });
  for (final value in ['status', 'count', 'date', 'offset', 'duplicate-page']) {
    test(
      'malformed trash page $value is rejected instead of exposing wrong identities',
      () async {
        malformed = value;
        await expectLater(catalog.page(), throwsA(isA<LibraryFailure>()));
      },
    );
  }
  for (final value in ['kind', 'duplicate-selection', 'incomplete-selection']) {
    test(
      'malformed full selection $value cannot masquerade as complete membership',
      () async {
        malformed = value;
        await expectLater(catalog.select(''), throwsA(isA<LibraryFailure>()));
      },
    );
  }
  test('selection cancellation preserves independent page reads and releases the old request', () async {
    started = Completer<void>();
    release = Completer<void>();
    final old = catalog.select('');
    final rejected = expectLater(old, throwsA(isA<RequestCancelled>()));
    await started!.future;
    catalog.cancelSelection();
    expect((await catalog.page()).total, 27);
    release!.complete();
    await rejected;
  });
  test('disposing the view rejects a late page and does not invalidate the connection', () async {
    started = Completer<void>();
    release = Completer<void>();
    final old = catalog.page(search: 'slow');
    final rejected = expectLater(old, throwsA(isA<RequestCancelled>()));
    await started!.future;
    catalog.dispose();
    release!.complete();
    await rejected;
    expect(repo.snapshot.connected, isTrue);
    final next = repo.createPackTrash();
    expect((await next.page()).total, 27);
    next.dispose();
  });
  test('unsupported service fails before a new trash read', () async {
    supported = false;
    await repo.connect('http://127.0.0.1', server.server.port, 'test');
    final before = server.reads
        .where((r) => r.path.startsWith('/api/v1/pack-trash'))
        .length;
    expect(() => repo.createPackTrash(), throwsA(isA<LibraryFailure>()));
    expect(
      server.reads.where((r) => r.path.startsWith('/api/v1/pack-trash')).length,
      before,
    );
    expect(catalog.isCurrent, isFalse);
  });
}
