import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/backup_work_store.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart' hide Json;

import 'pack_files_test.dart' show FilesFixture;
import 'server_pack_catalog_test.dart' show PackServer;
import 'support/maintenance_fixture.dart' show taskSummary;
import 'support/pack_purge_fixture.dart' show purgeHash, purgeTaskJson;

typedef Json = Map<String, dynamic>;

class TaskServerFixture {
  final server = PackServer();
  final packs = MemoryFileCommandStore(), videos = MemoryFileCommandStore();
  final backup = MemoryBackupWorkStore();
  late ServerLibraryRepository repo;
  late String scope;
  final summaries = <String, Json>{},
      full = <String, Json>{},
      receipts = <String, String>{};
  final artifact = <String, dynamic>{
    'format': 'video-viewer-management',
    'version': 1,
    'payload': {'kept': '原备份'},
  };
  bool supported = true,
      lose = false,
      corruptDownload = false,
      malformed = false;
  Completer<void>? started, release;
  Future<void> start({
    bool videoPending = false,
    bool backupPending = false,
  }) async {
    server.handle = handle;
    await server.start();
    scope = jsonEncode([
      ServerLibraryRepository.endpoint(
        'http://127.0.0.1',
        server.server.port,
      ).toString(),
      'packs',
    ]);
    if (videoPending) {
      videos.value = jsonEncode({
        'scope': scope,
        'pending': {
          'key': 'video-local',
          'path': '/api/v1/trash/restore',
          'body': {
            'trash_ids': ['v-trash'],
          },
        },
      });
    }
    if (backupPending) {
      backup.value = jsonEncode({
        'scope': scope,
        'export': {'key': 'backup-local'},
      });
    }
    repo = ServerLibraryRepository(
      MemoryCredentialStore(),
      packCommands: packs,
      fileCommands: videos,
      backupWork: backup,
    );
    await repo.connect('http://127.0.0.1', server.server.port, 'test');
  }

  Future<({int status, Json body})?> handle(
    HttpRequest request,
    Json body,
  ) async {
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
            'pack_logical_trash',
            'pack_purge_preview',
            'pack_permanent_delete',
            if (supported) 'maintenance_tasks',
          ],
        },
      );
    }
    if (path == '/api/v1/maintenance-tasks') {
      if (started != null) {
        started!.complete();
        await release!.future;
      }
      final offset = int.parse(query['offset']!),
          limit = int.parse(query['limit']!);
      final values = summaries.values
          .where(
            (t) => query['family'] == 'all' || t['family'] == query['family'],
          )
          .toList();
      return (
        status: 200,
        body: {
          'items': values.skip(offset).take(limit).toList(),
          'total': malformed ? values.length + 1 : values.length,
          'offset': offset,
          'limit': limit,
        },
      );
    }
    if (path.startsWith('/api/v1/maintenance-tasks/')) {
      final id = request.uri.pathSegments[3];
      if (path.endsWith('/items')) {
        return (
          status: 200,
          body: {
            'operation_id': malformed ? 'wrong' : id,
            'historical': false,
            'items': [],
            'total': 0,
            'offset': int.parse(query['offset']!),
            'limit': int.parse(query['limit']!),
          },
        );
      }
      return summaries.containsKey(id)
          ? (status: 200, body: summaries[id]!)
          : missing();
    }
    if (path.contains('/pack-file-requests/') ||
        path.contains('/pack-retry-requests/') ||
        path.contains('/file-requests/') ||
        path.contains('/backup-requests/')) {
      final id = receipts[request.uri.pathSegments.last];
      return id == null ? missing() : (status: 200, body: full[id]!);
    }
    if (path.startsWith('/api/v1/tasks/')) {
      final id = request.uri.pathSegments.last;
      return full.containsKey(id) ? (status: 200, body: full[id]!) : missing();
    }
    if (path.endsWith('/download')) {
      return (
        status: 200,
        body: corruptDownload ? {...artifact, 'changed': true} : artifact,
      );
    }
    if (path == '/api/v1/pack-trash/restore' && request.method == 'POST') {
      final key = body['request_id'] as String;
      receipts[key] = 'restore';
      full['restore'] = FilesFixture().task('restore', 'restore', ['trash-0']);
      summaries['restore'] = taskSummary('restore');
      if (lose) {
        return (
          status: 503,
          body: {
            'error': {'code': 'reply_lost', 'message': '结果未知'},
          },
        );
      }
      return (status: 202, body: full['restore']!);
    }
    return null;
  }

  ({int status, Json body}) missing() => (
    status: 404,
    body: {
      'error': {'code': 'not_found', 'message': 'Unknown'},
    },
  );
  Future<void> close() async {
    repo.dispose();
    await server.server.close(force: true);
  }
}

void main() {
  // The connection and server history remain useful even if a local journal
  // needs manual repair; no invalid intent is silently dropped or replayed.
  late TaskServerFixture fixture;
  setUp(() {
    fixture = TaskServerFixture();
  });
  tearDown(() => fixture.close());
  test('lost accepted pack response is reconciled from task center by original GET and local acknowledgement', () async {
    await fixture.start();
    fixture.lose = true;
    final command = PackFileCommand.restore('local', ['trash-0']);
    await expectLater(
      fixture.repo.createPackFiles().send(command),
      throwsA(isA<LibraryFailure>()),
    );
    final catalog = fixture.repo.createMaintenanceTasks();
    final before = fixture.server.writes.length;
    final pending = await catalog.pending();
    expect(fixture.repo.maintenancePendingCount, 1);
    expect(pending.single.requestId, 'local');
    expect((await catalog.reconcile(pending.single))!.state, 'completed');
    expect(await catalog.pending(), isEmpty);
    expect(fixture.repo.maintenancePendingCount, 0);
    expect(fixture.server.writes.length, before);
    expect(
      fixture.server.reads.any(
        (r) => r.path.endsWith('/pack-file-requests/local'),
      ),
      isTrue,
    );
  });
  test('unknown, forged and stale local receipts never submit or discard original intent', () async {
    await fixture.start();
    final command = PackFileCommand.restore('unknown', ['trash-0']);
    await fixture.repo.packFileJournal.remember(fixture.scope, command);
    final catalog = fixture.repo.createMaintenanceTasks();
    final original = (await catalog.pending()).single;
    expect(await catalog.reconcile(original), isNull);
    final forged = MaintenanceReceipt(
      id: original.id,
      requestId: original.requestId,
      title: original.title,
      source: original.source,
      kind: original.kind,
      packCommand: command,
    );
    await expectLater(
      catalog.reconcile(forged),
      throwsA(isA<LibraryFailure>()),
    );
    await catalog.pending();
    await expectLater(
      catalog.reconcile(original),
      throwsA(isA<LibraryFailure>()),
    );
    expect(fixture.server.writes, isEmpty);
    expect((await catalog.pending()).length, 1);
  });
  test('uncertain image purge keeps journal; settled exact original task later retires it', () async {
    await fixture.start();
    final command = PackFileCommand.permanent(
      'purge-local',
      planId: 'plan',
      digest: purgeHash,
      trashIds: ['trash-0'],
      imageCount: 3,
    );
    await fixture.repo.packFileJournal.remember(fixture.scope, command);
    fixture.receipts['purge-local'] = 'purge-op';
    fixture.full['purge-op'] = purgeTaskJson(['trash-0'], attention: true);
    fixture.summaries['purge-op'] = taskSummary(
      'purge-op',
      kind: 'pack_permanent',
      state: 'attention',
    );
    final catalog = fixture.repo.createMaintenanceTasks();
    expect(
      (await catalog.reconcile((await catalog.pending()).single))!
          .needsAttention,
      isTrue,
    );
    expect((await catalog.pending()).length, 1);
    fixture.full['purge-op'] = purgeTaskJson(['trash-0']);
    fixture.summaries['purge-op'] = taskSummary(
      'purge-op',
      kind: 'pack_permanent',
    );
    expect(
      (await catalog.reconcile((await catalog.pending()).single))!.pagesDeleted,
      3,
    );
    expect(await catalog.pending(), isEmpty);
    expect(fixture.server.writes, isEmpty);
  });
  test('historical original video receipt clears only its local pending record with no replay', () async {
    await fixture.start(videoPending: true);
    fixture.receipts['video-local'] = 'old-video';
    fixture.full['old-video'] = {
      'id': 'old-video',
      'kind': 'restore',
      'status': 'interrupted',
      'result': {},
    };
    fixture.summaries['old-video'] = taskSummary(
      'old-video',
      kind: 'restore',
      state: 'historical',
    );
    final catalog = fixture.repo.createMaintenanceTasks();
    expect(
      (await catalog.reconcile((await catalog.pending()).single))!.historical,
      isTrue,
    );
    expect(fixture.repo.fileOperationPending, isFalse);
    expect(fixture.server.writes, isEmpty);
  });
  test('accepted export receipt binds original task; verified original download retires only after save', () async {
    await fixture.start(backupPending: true);
    fixture.receipts['backup-local'] = 'export';
    fixture.full['export'] = {
      'id': 'export',
      'kind': 'backup_export',
      'status': 'completed',
      'result': {
        'file_sha256': sha256
            .convert(utf8.encode(jsonEncode(fixture.artifact)))
            .toString(),
      },
    };
    fixture.summaries['export'] = taskSummary('export', kind: 'backup_export');
    final catalog = fixture.repo.createMaintenanceTasks();
    await catalog.reconcile((await catalog.pending()).single);
    expect((await catalog.pending()).single.taskId, 'export');
    await expectLater(
      catalog.backupSaved('export'),
      throwsA(isA<LibraryFailure>()),
    );
    fixture.corruptDownload = true;
    await expectLater(
      catalog.downloadBackup('export'),
      throwsA(isA<LibraryFailure>()),
    );
    expect((await catalog.pending()).length, 1);
    fixture.corruptDownload = false;
    expect(
      await catalog.downloadBackup('export'),
      jsonEncode(fixture.artifact),
    );
    expect((await catalog.pending()).length, 1);
    await catalog.backupSaved('export');
    expect(await catalog.pending(), isEmpty);
    expect(fixture.server.writes, isEmpty);
  });
  test('metadata pages and members reject malformed envelopes; cancelled reads cannot publish', () async {
    await fixture.start();
    for (var i = 0; i < 27; i++) {
      fixture.summaries['m$i'] = taskSummary('m$i');
    }
    final catalog = fixture.repo.createMaintenanceTasks();
    expect((await catalog.page(offset: 24)).items.length, 3);
    fixture.malformed = true;
    await expectLater(catalog.page(offset: 24), throwsA(isA<LibraryFailure>()));
    await expectLater(catalog.items('m0'), throwsA(isA<LibraryFailure>()));
    fixture.malformed = false;
    fixture.started = Completer<void>();
    fixture.release = Completer<void>();
    final work = catalog.page();
    final failed = expectLater(work, throwsA(isA<RequestCancelled>()));
    await fixture.started!.future;
    catalog.dispose();
    fixture.release!.complete();
    await failed;
    expect(fixture.server.writes, isEmpty);
  });
  test('capability fallback does not invent task records', () async {
    fixture.supported = false;
    await fixture.start();
    expect(
      () => fixture.repo.createMaintenanceTasks(),
      throwsA(isA<LibraryFailure>()),
    );
  });
  test('corrupt pack journal preserves evidence, marks settings pending and does not block task history', () async {
    fixture.packs.value = '{broken';
    await fixture.start();
    expect(fixture.repo.snapshot.connected, isTrue);
    expect(fixture.repo.maintenanceNeedsCheck, isTrue);
    expect(fixture.repo.maintenancePendingCount, isNull);
    final catalog = fixture.repo.createMaintenanceTasks();
    expect((await catalog.page()).total, 0);
    await expectLater(catalog.pending(), throwsA(isA<LibraryFailure>()));
    expect(fixture.packs.value, '{broken');
    expect(fixture.server.writes, isEmpty);
  });
}
