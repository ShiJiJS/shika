import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';

import 'server_client_authority_test.dart' show AuthorityFixture;
import 'server_maintenance_tasks_test.dart' show Json;
import 'support/maintenance_fixture.dart' show taskSummary;

class _History extends AuthorityFixture {
  static const graph = '11111111-1111-4111-8111-111111111111';
  static const other = '22222222-2222-4222-8222-222222222222';
  final reads = <Uri>[];
  bool absentEpoch = false, mismatch = false, badMembers = false;
  @override
  Future<({int status, Json body})?> handle(
    HttpRequest request,
    Json body,
  ) async {
    final path = request.uri.path;
    if (path == '/api/v1/info') {
      final value = (await super.handle(request, body))!;
      return (
        status: 200,
        body: {
          ...value.body,
          'capabilities': [
            ...value.body['capabilities'] as List,
            'management_history',
          ],
          'management_history_available': true,
        },
      );
    }
    if (path.startsWith('/api/v1/management-history/')) {
      reads.add(request.uri);
      request.response.headers.set('X-Management-Epoch', epoch);
      if (absentEpoch) {
        return (
          status: 404,
          body: {
            'error': {'code': 'history_not_found', 'message': '原代次不存在'},
          },
        );
      }
      if (path.contains('/receipts/')) {
        return (
          status: 200,
          body: {
            'graph_id': graph,
            'historical': true,
            'record': {'id': 'files:old-video'},
            'task': {
              'id': 'files:old-video',
              'kind': 'trash',
              'status': 'completed',
              'result': {},
            },
          },
        );
      }
      if (path.endsWith('/items')) {
        return (
          status: 200,
          body: {
            'operation_id': 'files:old-video',
            'historical': true,
            'graph_id': badMembers ? other : graph,
            'items': [],
            'total': 0,
            'offset': 0,
            'limit': 24,
          },
        );
      }
      return (
        status: 200,
        body: {
          ...taskSummary('files:old-video', kind: 'trash', state: 'historical'),
          'historical': true,
          'graph_id': mismatch ? other : graph,
        },
      );
    }
    return super.handle(request, body);
  }
}

void main() {
  late _History f;
  setUp(() async {
    f = _History();
    await f.start();
    f.failVideo = true;
    await expectLater(
      f.repo.operation('/api/v1/videos/trash', {
        'video_ids': ['old-video'],
      }, idempotency: 'old-video'),
      throwsA(isA<LibraryFailure>()),
    );
    await f.change();
  });
  tearDown(() => f.close());
  test(
    'retired receipt, parent and members use the original epoch and graph',
    () async {
      final catalog = f.repo.createMaintenanceTasks();
      final issued = (await catalog.pending()).single;
      final before = f.events.length;
      final task = (await catalog.reconcile(issued))!;
      expect(task.historical, isTrue);
      expect(task.graphId, _History.graph);
      expect(
        f.reads.take(2).every((u) => u.queryParameters['epoch'] == 'a' * 32),
        isTrue,
      );
      final detail = (catalog as GraphTaskCatalog).forTask(task);
      await detail.task(task.id);
      await detail.items(task.id);
      expect(
        f.reads
            .skip(2)
            .every((u) => u.queryParameters['graph_id'] == _History.graph),
        isTrue,
      );
      f.badMembers = true;
      await expectLater(detail.items(task.id), throwsA(isA<LibraryFailure>()));
      expect(f.events.skip(before).every((e) => e.method == 'GET'), isTrue);
      expect((await catalog.pending()).single.requestId, issued.requestId);
      detail.dispose();
      catalog.dispose();
    },
  );
  test(
    'missing original epoch returns no receipt without a current fallback',
    () async {
      f.absentEpoch = true;
      final catalog = f.repo.createMaintenanceTasks();
      final issued = (await catalog.pending()).single;
      final before = f.events.length;
      expect(await catalog.reconcile(issued), isNull);
      expect(f.reads, hasLength(1));
      expect(
        f.events.skip(before).where((e) => e.path.contains('/file-requests/')),
        isEmpty,
      );
      expect((await catalog.pending()).single.requestId, issued.requestId);
    },
  );
  test(
    'a summary from a different graph cannot complete the original receipt',
    () async {
      f.mismatch = true;
      final catalog = f.repo.createMaintenanceTasks();
      await expectLater(
        catalog.reconcile((await catalog.pending()).single),
        throwsA(isA<LibraryFailure>()),
      );
      expect(await catalog.pending(), hasLength(1));
    },
  );
}
