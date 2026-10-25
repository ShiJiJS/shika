import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart' hide Json;

import 'server_maintenance_tasks_test.dart' show TaskServerFixture, Json;
import 'support/maintenance_fixture.dart' show taskSummary;

class AuthorityFixture extends TaskServerFixture {
  AuthorityFixture({CredentialStore? credentials, FileCommandStore? videoStore})
    : saved = credentials ?? MemoryCredentialStore(),
      suppliedVideos = videoStore;
  final CredentialStore saved;
  final FileCommandStore? suppliedVideos;
  FileCommandStore get videoStore => suppliedVideos ?? videos;
  String epoch = 'a' * 32;
  final events = <({String method, String path, String? epoch})>[];
  bool failVideo = false, failExport = false;
  bool authoritySupported = true;
  Completer<void>? pageEntered, pageRelease;
  bool delayPage = false;
  @override
  Future<void> start({
    bool videoPending = false,
    bool backupPending = false,
  }) async {
    server.handle = handle;
    await server.start();
    final endpoint = ServerLibraryRepository.endpoint(
      'http://127.0.0.1',
      server.server.port,
    );
    scope = jsonEncode([endpoint.toString(), 'packs', epoch]);
    final legacy = jsonEncode([endpoint.toString(), 'packs']);
    if (videoPending) {
      await videoStore.write(
        jsonEncode({
          'scope': legacy,
          'pending': {
            'key': 'legacy-video',
            'path': '/api/v1/videos/trash',
            'body': {
              'video_ids': ['old-video'],
            },
          },
        }),
      );
    }
    if (backupPending) {
      backup.value = jsonEncode({
        'scope': legacy,
        'restore': {'key': 'legacy-restore'},
      });
    }
    repo = ServerLibraryRepository(
      saved,
      packCommands: packs,
      fileCommands: videoStore,
      backupWork: backup,
    );
    await repo.connect('http://127.0.0.1', server.server.port, 'test');
  }

  @override
  Future<({int status, Json body})?> handle(
    HttpRequest request,
    Json body,
  ) async {
    final path = request.uri.path, captured = epoch;
    events.add((
      method: request.method,
      path: path,
      epoch: request.headers.value('X-Management-Epoch'),
    ));
    request.response.headers.set('X-Management-Epoch', captured);
    if (path == '/api/v1/maintenance-tasks' && delayPage) {
      delayPage = false;
      pageEntered!.complete();
      await pageRelease!.future;
    }
    if (path == '/api/v1/info') {
      final base = (await super.handle(request, body))!;
      return (
        status: 200,
        body: {
          ...base.body,
          if (authoritySupported) 'management_epoch': captured,
          'capabilities': [
            ...base.body['capabilities'] as List,
            if (authoritySupported) 'management_authority',
            'pack_restore_plans',
            'pack_missing_cleanup',
            'pack_reading_sessions',
            'managed_playback_defaults',
          ],
        },
      );
    }
    if (authoritySupported &&
        request.method != 'GET' &&
        !path.endsWith('/auth/login') &&
        request.headers.value('X-Management-Epoch') != epoch) {
      return (
        status: 409,
        body: {
          'error': {'code': 'management_changed', 'message': '旧请求未执行'},
        },
      );
    }
    if (path == '/api/v1/videos/trash' && failVideo ||
        path == '/api/v1/backups' && failExport) {
      return (
        status: 503,
        body: {
          'error': {'code': 'response_lost', 'message': '原结果待核对'},
        },
      );
    }
    if (path.startsWith('/api/v1/pack-restore-requests/') ||
        path.startsWith('/api/v1/pack-missing-requests/')) {
      return missing();
    }
    return super.handle(request, body);
  }

  Future<void> change() async {
    final old = repo.api;
    epoch = 'b' * 32;
    await expectLater(
      old.json('GET', '/api/v1/info'),
      throwsA(isA<ApiFailure>()),
    );
    await repo.managementSynchronization;
    expect(repo.api.managementEpoch, epoch);
    expect(identical(old, repo.api), isFalse);
  }

  @override
  Future<void> close() async {
    if (pageRelease?.isCompleted == false) pageRelease!.complete();
    await super.close();
  }
}

class GatedCredentials extends MemoryCredentialStore {
  Completer<void>? entered, release;
  @override
  Future<ConnectionCredentials?> read() async {
    if (entered != null && !entered!.isCompleted) {
      entered!.complete();
      await release!.future;
    }
    return super.read();
  }
}

class AmbiguousVideoStore extends MemoryFileCommandStore {
  bool fail = false;
  @override
  Future<void> write(String next) async {
    await super.write(next);
    if (fail) {
      fail = false;
      throw StateError('saved then lost acknowledgement');
    }
  }
}

void main() {
  late AuthorityFixture f;
  setUp(() => f = AuthorityFixture());
  tearDown(() => f.close());
  test('confirmed legacy restore retires its generation without erasing video or restore receipts', () async {
    f.authoritySupported = false;
    await f.start(videoPending: true, backupPending: true);
    final oldScope = jsonEncode([
      (await f.saved.read())!.endpoint.toString(),
      'packs',
    ]);
    final old = f.repo.createMaintenanceTasks();
    await f.repo.packFileJournal.remember(
      oldScope,
      PackFileCommand.restore('legacy-pack', ['trash-old']),
    );
    f.receipts['legacy-restore'] = 'legacy-restore-task';
    f.full['legacy-restore-task'] = {
      'id': 'legacy-restore-task',
      'kind': 'backup_restore',
      'status': 'completed',
      'phase': 'completed',
      'result': {},
    };
    await f.repo.reconcileBackupRestore();
    expect(old.isCurrent, isFalse);
    expect((await f.saved.read())!.localGeneration, isNotNull);
    expect(f.repo.fileOperationPending, isFalse);
    expect(f.repo.backupRestorePending, isFalse);
    final pending = await f.repo.createMaintenanceTasks().pending();
    expect(pending, hasLength(3));
    expect(
      pending.every((v) => v.historical && v.journalScope == oldScope),
      isTrue,
    );
    expect(jsonDecode(f.videos.value!)['pending']['key'], 'legacy-video');
    expect(jsonDecode(f.backup.value!)['restore']['key'], 'legacy-restore');
    expect(f.events.where((v) => v.path.endsWith('/auth/login')), hasLength(1));
  });
  test('external restore preserves every old intent and invalidates all gateways without another login', () async {
    await f.start();
    final oldScope = f.scope,
        oldReader = f.repo.createPackReader(),
        oldTasks = f.repo.createMaintenanceTasks(),
        oldMissing = f.repo.createPackMissing(),
        oldDefaults = f.repo.createPlaybackDefaults();
    final oldApi = f.repo.api;
    final oldSource = MediaSource(
      'http://127.0.0.1/video',
      headers: oldApi.authorization,
      asset: false,
    );
    final command = PackFileCommand.restore('pack-original', ['trash-file']);
    await f.repo.packFileJournal.remember(oldScope, command);
    await f.repo.packFileJournal.rememberRestore(
      oldScope,
      RestorePlanCommand.restore('restore-original', ['trash-plan']),
    );
    await f.repo.packFileJournal.rememberMissing(oldScope, 'missing-original');
    final selection = await PackPurgeSelections(f.repo.createPackFiles())
        .save([for (var i = 0; i < 27; i++) 'trash-selection-$i']);
    f.failVideo = f.failExport = true;
    await expectLater(
      f.repo.operation('/api/v1/videos/trash', {
        'video_ids': ['v-old'],
      }, idempotency: 'video-original'),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(
      f.repo.exportBackupFile(),
      throwsA(isA<LibraryFailure>()),
    );
    final before = f.events.length;
    await f.change();
    expect(f.events.skip(before).every((e) => e.method == 'GET'), isTrue);
    expect(f.events.where((e) => e.path.endsWith('/auth/login')), hasLength(1));
    expect([
      oldReader.isCurrent,
      oldTasks.isCurrent,
      oldMissing.isCurrent,
      oldDefaults.isCurrent,
    ], everyElement(isFalse));
    await f.repo.mediaUnauthorized(oldSource);
    expect(f.repo.snapshot.connected, isTrue);
    final tasks = f.repo.createMaintenanceTasks();
    final pending = await tasks.pending();
    expect(pending, hasLength(6));
    expect(pending.every((v) => v.historical), isTrue);
    final saved = pending.singleWhere(
      (v) => v.source == MaintenanceReceiptSource.purgeSelection,
    );
    expect(saved.historyFiles!.readOnly, isTrue);
    final choices = PackPurgeSelections(saved.historyFiles!);
    final previous = await choices.read(selection.id);
    expect(previous.historical, isTrue);
    expect(previous.remaining, selection.remaining);
    await expectLater(
      saved.historyFiles!.send(command),
      throwsA(isA<LibraryFailure>()),
    );
    await expectLater(
      choices.save(['trash-file']),
      throwsA(isA<LibraryFailure>()),
    );
    final books = [
      await f.videoStore.read(),
      await f.backup.read(),
      await f.packs.read(),
    ];
    for (final receipt in pending.where(
      (v) => v.source != MaintenanceReceiptSource.purgeSelection,
    )) {
      expect(await tasks.reconcile(receipt), isNull);
    }
    expect([
      await f.videoStore.read(),
      await f.backup.read(),
      await f.packs.read(),
    ], books);
    expect(f.events.skip(before).every((e) => e.method == 'GET'), isTrue);
    await choices.discard(previous);
    expect(await f.repo.packFileJournal.pending(oldScope), hasLength(1));
    expect(await f.repo.packFileJournal.restorePending(oldScope), hasLength(1));
    expect(await f.repo.packFileJournal.missingPending(oldScope), hasLength(1));
    await f.repo.saveRoot(const MediaRoot('', '新目录', '/media/new'));
    expect(f.events.lastWhere((e) => e.method == 'POST').epoch, f.epoch);
    final savedCredentials = await f.saved.read();
    expect(savedCredentials!.managementEpoch, f.epoch);
    f.repo.dispose();
    f.repo = ServerLibraryRepository(
      f.saved,
      packCommands: f.packs,
      fileCommands: f.videoStore,
      backupWork: f.backup,
    );
    await f.repo.initialize();
    final reopened = f.repo.createMaintenanceTasks();
    expect((await reopened.pending()).where((v) => v.historical), hasLength(5));
    expect(f.events.where((e) => e.path.endsWith('/auth/login')), hasLength(1));
  });
  test('an unversioned old video and restore journal become read-only on first upgraded connection', () async {
    await f.start(videoPending: true, backupPending: true);
    expect(f.repo.fileOperationPending, isFalse);
    expect(f.repo.backupRestorePending, isFalse);
    final catalog = f.repo.createMaintenanceTasks();
    final pending = await catalog.pending();
    expect(pending, hasLength(2));
    expect(pending.every((v) => v.historical), isTrue);
    final before = f.events.length;
    for (final row in pending) {
      expect(await catalog.reconcile(row), isNull);
    }
    expect(f.events.skip(before).every((e) => e.method == 'GET'), isTrue);
    expect(jsonDecode(f.backup.value!)['restore']['key'], 'legacy-restore');
  });
  test(
    'a late page from the old transport cannot publish after recovery',
    () async {
      await f.start();
      final catalog = f.repo.createMaintenanceTasks();
      f.pageEntered = Completer();
      f.pageRelease = Completer();
      f.delayPage = true;
      final delayed = catalog.page();
      final assertion = expectLater(delayed, throwsA(isA<RequestCancelled>()));
      await f.pageEntered!.future;
      await f.change();
      f.pageRelease!.complete();
      await assertion;
      expect(catalog.isCurrent, isFalse);
      expect(f.repo.snapshot.connected, isTrue);
    },
  );
  test('historical successful receipt stays historical on detail refresh and does not acknowledge a current journal', () async {
    await f.start();
    f.failExport = true;
    await expectLater(
      f.repo.exportBackupFile(),
      throwsA(isA<LibraryFailure>()),
    );
    final raw = jsonDecode(f.backup.value!)['scopes'][f.scope] as Map;
    final key = raw['export']['key'] as String;
    f.receipts[key] = 'old-export';
    f.full['old-export'] = {
      'id': 'old-export',
      'kind': 'backup_export',
      'status': 'completed',
    };
    f.summaries['old-export'] = taskSummary(
      'old-export',
      kind: 'backup_export',
    );
    await f.change();
    final catalog = f.repo.createMaintenanceTasks(),
        receipt = (await f.repo.createMaintenanceTasks().pending()).single;
    // Issued receipt identity is local to its catalog.
    final issued = (await catalog.pending()).single;
    final result = await catalog.reconcile(issued);
    expect(result!.historical, isTrue);
    expect(receipt.requestId, key);
    final detail = HistoricalTaskCatalog(catalog);
    expect((await detail.task('old-export')).historical, isTrue);
    expect(
      jsonDecode(f.backup.value!)['scopes'][f.scope]['export']['key'],
      key,
    );
    detail.dispose();
    expect(catalog.isCurrent, isTrue);
  });
  test('manual connection supersedes a paused automatic recovery', () async {
    final credentials = GatedCredentials();
    f = AuthorityFixture(credentials: credentials);
    await f.start();
    credentials.entered = Completer();
    credentials.release = Completer();
    f.epoch = 'b' * 32;
    await expectLater(
      f.repo.api.json('GET', '/api/v1/info'),
      throwsA(isA<ApiFailure>()),
    );
    final recovery = f.repo.managementSynchronization;
    final assertion = expectLater(recovery, throwsA(isA<RequestCancelled>()));
    await credentials.entered!.future;
    await f.repo.connect('http://127.0.0.1', f.server.server.port, 'manual');
    final manual = f.repo.connectionIdentity;
    credentials.release!.complete();
    await assertion;
    expect(identical(f.repo.connectionIdentity, manual), isTrue);
    expect(f.repo.snapshot.connected, isTrue);
  });
  test('ambiguous disk acknowledgement blocks mutations and reopens the original video request without POST', () async {
    final store = AmbiguousVideoStore();
    f = AuthorityFixture(videoStore: store);
    await f.start();
    store.fail = true;
    final before = f.events.length;
    await expectLater(
      f.repo.operation('/api/v1/videos/trash', {
        'video_ids': ['v-old'],
      }, idempotency: 'saved-original'),
      throwsStateError,
    );
    await expectLater(
      f.repo.saveRoot(const MediaRoot('', 'blocked', '/media/new')),
      throwsA(isA<LibraryFailure>()),
    );
    expect(f.events.length, before);
    f.repo.dispose();
    f.repo = ServerLibraryRepository(
      f.saved,
      fileCommands: store,
      packCommands: f.packs,
      backupWork: f.backup,
    );
    await f.repo.initialize();
    await expectLater(
      f.repo.operation('/api/v1/videos/trash', {
        'video_ids': ['v-old'],
      }, idempotency: 'must-not-replace'),
      throwsA(isA<ApiFailure>()),
    );
    expect(f.events.skip(before).every((e) => e.method == 'GET'), isTrue);
    final pending = await f.repo.createMaintenanceTasks().pending();
    expect(pending.single.requestId, 'saved-original');
    expect(f.repo.fileOperationPending, isTrue);
  });
  for (final reopening in [false, true]) {
    test(
      'legacy fallback after authority keeps old scopes historical; reopening=$reopening',
      () async {
        await f.start();
        final originalScope = f.scope;
        await f.repo.packFileJournal.remember(
          originalScope,
          PackFileCommand.restore('old-authority', ['old-trash']),
        );
        f.authoritySupported = false;
        if (reopening) {
          f.repo.dispose();
          f.repo = ServerLibraryRepository(
            f.saved,
            packCommands: f.packs,
            fileCommands: f.videoStore,
            backupWork: f.backup,
          );
          await f.repo.initialize();
        } else {
          await f.repo.connect(
            'http://127.0.0.1',
            f.server.server.port,
            'legacy',
          );
        }
        final credentials = await f.saved.read();
        expect(credentials!.managementEpoch, isNull);
        expect(credentials.localGeneration, isNotNull);
        expect(f.repo.api.managementEpoch, isNull);
        final tasks = f.repo.createMaintenanceTasks();
        final pending = await tasks.pending();
        expect(pending.single.historical, isTrue);
        final local = credentials.localGeneration;
        f.repo.dispose();
        f.repo = ServerLibraryRepository(
          f.saved,
          packCommands: f.packs,
          fileCommands: f.videoStore,
          backupWork: f.backup,
        );
        await f.repo.initialize();
        expect((await f.saved.read())!.localGeneration, local);
        expect(
          (await f.repo.createMaintenanceTasks().pending()).single.historical,
          isTrue,
        );
        expect(
          await f.repo.packFileJournal.pending(originalScope),
          hasLength(1),
        );
      },
    );
  }
}
