import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';

import 'server_client_authority_test.dart' show AuthorityFixture;
import 'server_maintenance_tasks_test.dart' show Json;
import 'support/purge_history_fixture.dart';

class PurgeHistoryServer extends AuthorityFixture {
  String historyMalformed = '';
  bool historySupported = true;
  final historyReads = <Uri>[];
  Completer<void>? historyEntered, historyRelease;
  @override
  Future<({int status, Json body})?> handle(
    HttpRequest request,
    Json body,
  ) async {
    final path = request.uri.path, q = request.uri.queryParameters;
    if (path == '/api/v1/info') {
      final base = (await super.handle(request, body))!;
      return (
        status: 200,
        body: {
          ...base.body,
          'capabilities': [
            ...base.body['capabilities'] as List,
            'management_history',
            if (historySupported) 'management_purge_history',
          ],
          'management_history_available': true,
        },
      );
    }
    if (path.startsWith('/api/v1/management-history/')) {
      historyReads.add(request.uri);
      request.response.headers.set('X-Management-Epoch', epoch);
      if (historyEntered != null) {
        historyEntered!.complete();
        await historyRelease!.future;
        historyEntered = null;
      }
      final id = path.contains('/preview-old') ? 'preview-old' : 'purge-old';
      final offset = int.tryParse(q['offset'] ?? '0') ?? 0,
          limit = int.tryParse(q['limit'] ?? '24') ?? 24;
      late Json raw;
      if (path.endsWith('/purge-review')) {
        raw = historyReviewJson(id, offset: offset, limit: limit);
      } else if (path.endsWith('/files')) {
        final index = int.parse(q['trash_id']!.split('-').last);
        raw = historyImagesJson(
          id,
          PackPurgeMember(historyMember(index)),
          offset: offset,
          limit: limit,
        );
        if (historyMalformed == 'file-pack') raw['pack_id'] = 'other';
        if (historyMalformed == 'file-path') {
          (raw['items'] as List).first['path'] = '/outside.png';
        }
      } else if (path.endsWith('/purge-pages')) {
        raw = historyStepsJson(
          id,
          offset: offset,
          limit: limit,
          unfinished: q['outcome'] == 'unfinished',
          kind: q['kind'] ?? 'all',
        );
        if (historyMalformed == 'outcome') {
          (raw['items'] as List).first['outcome'] = 'invented';
        }
      } else {
        raw = historyTaskJson(
          kind: id == 'purge-old' ? 'pack_permanent' : 'pack_purge_preview',
        );
      }
      if (historyMalformed == 'graph') raw['graph_id'] = purgeHistoryOtherGraph;
      if (historyMalformed == 'parent') raw['task_id'] = 'other';
      if (historyMalformed == 'plan') raw['plan_id'] = 'other';
      if (historyMalformed == 'truncated') raw['items'] = [];
      if (historyMalformed == 'duplicate') {
        (raw['items'] as List)[1] = (raw['items'] as List)[0];
      }
      if (historyMalformed == 'ready') raw['ready'] = true;
      return (status: 200, body: raw);
    }
    return super.handle(request, body);
  }
}

void main() {
  late PurgeHistoryServer fixture;
  late MaintenanceTaskCatalog catalog;
  late PurgeHistoryDetails history;
  setUp(() async {
    fixture = PurgeHistoryServer();
    await fixture.start();
    catalog = fixture.repo.createMaintenanceTasks();
    history = (catalog as HistoricalPurgeCatalog).purgeHistory(
      MaintenanceTask(historyTaskJson()),
    );
  });
  tearDown(() async {
    history.dispose();
    catalog.dispose();
    await fixture.close();
  });

  test('original task/graph binds member paging, exact files and typed results without commands or journal changes', () async {
    final packBefore = await fixture.packs.read(),
        backupBefore = await fixture.backup.read(),
        videoBefore = await fixture.videos.read();
    final first = await history.review(),
        last = await history.review(offset: 24);
    expect(first.members.items, hasLength(24));
    expect(last.members.items, hasLength(3));
    final again = await history.review();
    final member = again.members.items.first;
    expect((await history.images(member)).items, hasLength(100));
    final files = await history.images(member, offset: 100);
    expect(files.items, hasLength(27));
    expect(files.items.last.relativePath, '0127.png');
    final failed = await history.steps();
    expect(failed.total, 1);
    expect(failed.items.single.error, 'permission_denied');
    expect(
      (await history.steps(unfinished: false, kind: 'directory')).total,
      27,
    );
    expect(
      (await history.steps(unfinished: false, offset: 24)).items,
      hasLength(24),
    );
    expect(
      fixture.historyReads.every(
        (v) => v.queryParameters['graph_id'] == purgeHistoryGraph,
      ),
      isTrue,
    );
    expect(fixture.events.where((v) => v.method != 'GET').map((v) => v.path), [
      '/api/v1/auth/login',
    ]);
    expect(await fixture.packs.read(), packBefore);
    expect(await fixture.backup.read(), backupBefore);
    expect(await fixture.videos.read(), videoBefore);
  });
  for (final mode in ['graph', 'parent', 'truncated', 'duplicate', 'ready']) {
    test(
      'rejects $mode history review without current-data fallback',
      () async {
        fixture.historyMalformed = mode;
        await expectLater(history.review(), throwsA(isA<LibraryFailure>()));
        expect(fixture.historyReads, hasLength(1));
      },
    );
  }
  for (final mode in ['file-pack', 'file-path', 'plan']) {
    test('rejects $mode exact files after original binding', () async {
      final member = (await history.review()).members.items.first;
      fixture.historyMalformed = mode;
      await expectLater(history.images(member), throwsA(isA<LibraryFailure>()));
    });
  }
  test(
    'requires an issued original member and rejects wrong result type',
    () async {
      await history.review();
      await expectLater(
        history.images(PackPurgeMember(historyMember(0))),
        throwsA(isA<LibraryFailure>()),
      );
      fixture.historyMalformed = 'outcome';
      await expectLater(history.steps(), throwsA(isA<LibraryFailure>()));
    },
  );
  test('legacy service does not expose history reader', () async {
    fixture.historySupported = false;
    await fixture.repo.connect(
      'http://127.0.0.1',
      fixture.server.server.port,
      'test',
    );
    final next = fixture.repo.createMaintenanceTasks();
    expect((next as HistoricalPurgeCatalog).supportsPurgeHistory, isFalse);
    expect(
      () => (next as HistoricalPurgeCatalog).purgeHistory(
        MaintenanceTask(historyTaskJson()),
      ),
      throwsA(isA<LibraryFailure>()),
    );
    next.dispose();
  });
  test('missing graph, current task, wrong kind and cross-graph catalog are rejected before HTTP', () async {
    final source = catalog as HistoricalPurgeCatalog;
    for (final raw in [
      {...historyTaskJson(), 'graph_id': null},
      {...historyTaskJson(), 'kind': 'pack_restore'},
      {
        ...historyTaskJson(),
        'historical': false,
        'state': 'attention',
        'needs_attention': true,
      },
    ]) {
      expect(
        () => source.purgeHistory(MaintenanceTask(raw)),
        throwsA(isA<LibraryFailure>()),
      );
    }
    final bound = (catalog as GraphTaskCatalog).forTask(
      MaintenanceTask(historyTaskJson()),
    );
    expect(
      () => (bound as HistoricalPurgeCatalog).purgeHistory(
        MaintenanceTask({
          ...historyTaskJson(),
          'graph_id': purgeHistoryOtherGraph,
        }),
      ),
      throwsA(isA<LibraryFailure>()),
    );
    bound.dispose();
    expect(fixture.historyReads, isEmpty);
  });
  test('late original read is cancelled on reader disposal', () async {
    fixture.historyEntered = Completer();
    fixture.historyRelease = Completer();
    final read = history.review();
    final asserted = expectLater(read, throwsA(isA<RequestCancelled>()));
    await fixture.historyEntered!.future;
    history.dispose();
    fixture.historyRelease!.complete();
    await asserted;
  });
}
