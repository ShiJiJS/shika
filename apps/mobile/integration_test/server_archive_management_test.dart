import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/backup_document.dart';
import 'package:video_viewer/library/backup_file_picker.dart';
import 'package:video_viewer/library/backup_work_store.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/management_archives.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import '../test/support/reveal_action.dart';

class _ObservedArchiveRepository extends ServerLibraryRepository {
  _ObservedArchiveRepository(
    super.credentials, {
    super.backupWork,
    super.fileCommands,
    super.packCommands,
    super.port,
    required this.captureFailures,
  });
  final bool captureFailures;
  ApiFailure? lastUploadFailure;

  @override
  Future<ArchivePreview> inspectArchive(BackupDocument document) {
    final result = super.inspectArchive(document);
    if (!captureFailures) return result;
    return result.onError<ApiFailure>((error, stack) {
      lastUploadFailure = error;
      final cause = error.transportCause;
      final detail = switch (cause) {
        SocketException e => {
          'message': e.message,
          'errno': e.osError?.errorCode,
        },
        FileSystemException e => {
          'message': e.message,
          'errno': e.osError?.errorCode,
        },
        HttpException e => {'message': e.message},
        _ => <String, Object?>{},
      };
      debugPrint(
        'ARCHIVE_TRANSPORT_FAILURE:${jsonEncode({'phase': error.transportPhase?.name, 'cause_type': cause.runtimeType.toString(), 'code': error.code, 'bytes': document.bytes, 'sha256': document.sha256, ...detail})}',
      );
      Error.throwWithStackTrace(error, stack);
    });
  }
}

/// Default private-file boundary preserves the existing UI checks; opt-in
/// ARCHIVE_NATIVE_DOCUMENTS drives the same pages with real Android DocumentsUI.
class _PrivateFiles implements BackupArchiveFiles {
  BackupDocument? selected;
  @override
  Future<BackupDocument?> pick(
    BackupFileStore store, {
    required int maximumBytes,
    RequestScope? scope,
  }) async => selected;
  @override
  Future<bool> save(BackupDocument document, {RequestScope? scope}) async {
    await selected?.delete();
    selected = await document.store.capture(
      document.verifiedRead(scope: scope),
      maximumBytes: 64 * 1024 * 1024,
      expectedBytes: document.bytes,
      expectedSha256: document.sha256,
      scope: scope,
    );
    return true;
  }
}

/// Observes the production Android bridge without replacing its file provider.
class _SystemFiles implements BackupArchiveFiles {
  _SystemFiles(this.journal, {this.cancelFirst = false});
  final BackupWorkStore journal;
  final bool cancelFirst;
  var saves = 0, picks = 0, cancelledPicks = 0;
  Map<String, dynamic>? firstSaveJournal;
  final native = const NativeBackupArchiveFiles();
  int? exportedBytes;
  String? exportedSha256;
  BackupDocument? selected;

  @override
  Future<bool> save(BackupDocument document, {RequestScope? scope}) async {
    saves++;
    final operation = cancelFirst && saves == 1 ? 'cancel-save' : 'save';
    exportedBytes = document.bytes;
    exportedSha256 = document.sha256;
    final persisted = await journal.read();
    expect(persisted, isNotNull);
    expect(persisted!.length, lessThan(64 * 1024));
    firstSaveJournal ??= Map<String, dynamic>.from(
      jsonDecode(persisted) as Map,
    );
    debugPrint(
      'ARCHIVE_JOURNAL:${jsonEncode({'stage': 'before-system-save', 'state': jsonDecode(persisted)})}',
    );
    debugPrint(
      'ARCHIVE_SYSTEM_STAGE:${jsonEncode({'stage': operation, 'bytes': document.bytes, 'sha256': document.sha256})}',
    );
    final saved = await native.save(document, scope: scope);
    debugPrint(
      'ARCHIVE_SYSTEM_DONE:${jsonEncode({'stage': operation, 'saved': saved})}',
    );
    return saved;
  }

  @override
  Future<BackupDocument?> pick(
    BackupFileStore store, {
    required int maximumBytes,
    RequestScope? scope,
  }) async {
    picks++;
    final operation = cancelFirst && picks == 1 ? 'cancel-pick' : 'pick';
    debugPrint(
      'ARCHIVE_SYSTEM_STAGE:${jsonEncode({'stage': operation, 'maximum_bytes': maximumBytes})}',
    );
    selected = await native.pick(
      store,
      maximumBytes: maximumBytes,
      scope: scope,
    );
    if (operation == 'cancel-pick') {
      expect(selected, isNull);
      cancelledPicks++;
      debugPrint(
        'ARCHIVE_SYSTEM_DONE:${jsonEncode({'stage': operation, 'cancelled': true})}',
      );
      return null;
    }
    expect(selected, isNotNull);
    expect(selected!.bytes, exportedBytes);
    expect(selected!.sha256, exportedSha256);
    debugPrint(
      'ARCHIVE_SYSTEM_DONE:${jsonEncode({'stage': 'pick', 'bytes': selected!.bytes, 'sha256': selected!.sha256})}',
    );
    return selected;
  }
}

const archivePort = int.fromEnvironment(
  'ARCHIVE_SERVER_PORT',
  defaultValue: 8762,
);

Future<Map<String, dynamic>> control(
  String path, {
  String method = 'GET',
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://10.0.2.2:$archivePort/__archive_fixture$path'),
    );
    request.headers.set('X-Fixture-Key', 'archive-app-isolated-control');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('Archive fixture ${response.statusCode}:$path');
    }
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const nativeDocuments = bool.fromEnvironment('ARCHIVE_NATIVE_DOCUMENTS');
  const largeDocument = bool.fromEnvironment('ARCHIVE_LARGE_DOCUMENT');
  const cancelInputs = bool.fromEnvironment('ARCHIVE_CANCEL_INPUTS');
  const captureFailures = bool.fromEnvironment('ARCHIVE_CAPTURE_FAILURES');
  const resumeFailure = bool.fromEnvironment('ARCHIVE_RESUME_FAILURE');
  const ownedPrefix = nativeDocuments
      ? 'video_viewer.archive_native_app'
      : 'video_viewer.archive_app';
  testWidgets('LF8 real App v2 export, keyboard mapping, replacement and snapshot', (
    t,
  ) async {
    final credentials = SecureCredentialStore(key: '$ownedPrefix.connection');
    final work = SecureBackupWorkStore(key: '$ownedPrefix.backups');
    if (!resumeFailure) {
      await credentials.clear();
      await work.write('{"version":2,"scopes":{}}');
    }
    final repo = _ObservedArchiveRepository(
      credentials,
      captureFailures: captureFailures,
      backupWork: work,
      fileCommands: SecureFileCommandStore(key: '$ownedPrefix.videos'),
      packCommands: SecureFileCommandStore(key: '$ownedPrefix.packs'),
      port: archivePort,
    );
    final privateFiles = _PrivateFiles();
    final systemFiles = _SystemFiles(work, cancelFirst: cancelInputs);
    final BackupArchiveFiles files = nativeDocuments
        ? systemFiles
        : privateFiles;
    final preferences = UiPreferences(preloadAdjacent: false);
    if (resumeFailure) {
      await repo.initialize();
      expect(repo.snapshot.connected, isTrue);
    } else {
      await repo.connect(
        'http://10.0.2.2',
        archivePort,
        'archive-app-isolated-only',
      );
    }
    final originalEpoch = repo.api.managementEpoch;
    expect(repo.archiveBackupsAvailable, isTrue);
    expect(repo.archiveMaximumBytes, 64 * 1024 * 1024);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await privateFiles.selected?.delete();
      await systemFiles.selected?.delete();
      repo.dispose();
      preferences.dispose();
    });
    Future<void> checkpoint(String name) async {
      await control('/checkpoint/archive-ui-$name', method: 'POST');
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!(await control('/status'))['display_ack']) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Host did not capture $name');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(
        largeDocument
            ? const Duration(minutes: 4)
            : const Duration(seconds: 40),
      );
      while (!ready()) {
        if (captureFailures &&
            repo.lastUploadFailure != null &&
            find.byKey(const Key('archive-error')).evaluate().isNotEmpty) {
          debugPrint('ARCHIVE_FAILURE_JOURNAL:${await work.read()}');
          await checkpoint('unexpected-failure');
          fail('Archive upload failed: ${repo.backupStatus.value}');
        }
        if (DateTime.now().isAfter(end)) {
          fail('Archive UI timeout: ${repo.backupStatus.value}');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle();
    }

    Future<void> visible(Finder target) => revealAction(t, target);

    Future<void> journal(String stage) async {
      if (!nativeDocuments) return;
      final text = (await work.read())!;
      expect(text.length, lessThan(64 * 1024));
      debugPrint(
        'ARCHIVE_JOURNAL:${jsonEncode({'stage': stage, 'state': jsonDecode(text)})}',
      );
    }

    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      final m = MediaQueryData.fromView(t.view);
      if (name == 'restore-keyboard') {
        expect(m.viewInsets.bottom, greaterThan(0));
      }
      debugPrint(
        'ARCHIVE_UI_METRICS:${jsonEncode({
          'state': 'archive-ui-$name',
          'window': [m.size.width, m.size.height],
          'dpr': m.devicePixelRatio,
          'text13': m.textScaler.scale(13),
          'viewPadding': [m.viewPadding.left, m.viewPadding.top, m.viewPadding.right, m.viewPadding.bottom],
          'keyboard': m.viewInsets.bottom,
          'dark': preferences.dark,
        })}',
      );
      await checkpoint(name);
    }

    Future<void> show() async {
      await t.pumpWidget(
        VideoViewerApp(
          key: UniqueKey(),
          repository: repo,
          preferences: preferences,
          backupArchiveFiles: files,
        ),
      );
      await t.pumpAndSettle();
      final settings = find.byKey(const Key('nav-settings'));
      await visible(settings);
      await t.tap(settings);
      await t.pumpAndSettle();
      final backup = find.text('备份与恢复');
      await visible(backup);
      await t.tap(backup);
      await t.pumpAndSettle();
    }

    await show();
    if (resumeFailure) {
      final persisted = jsonDecode((await work.read())!) as Map;
      final scopes = (persisted['scopes'] as Map).values.cast<Map>();
      final original = Map<String, dynamic>.from(
        scopes.single['inspect'] as Map,
      );
      await shot('resume-start');
      final resume = find.byKey(const Key('archive-resume-preview'));
      await visible(resume);
      await t.tap(resume);
      await until(
        () => find.byKey(const Key('archive-counts')).evaluate().isNotEmpty,
      );
      await shot('resume-preview');
      await visible(find.text('下一页'));
      await t.tap(find.text('下一页'));
      await until(() => find.text('媒体目录 · 已载入 27/27').evaluate().isNotEmpty);
      await visible(find.byKey(const Key('archive-confirm')));
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('archive-confirm')))
            .value,
        isFalse,
      );
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const Key('archive-restore-submit')),
            )
            .onPressed,
        isNull,
      );
      await shot('resume-confirm-off');
      final after = jsonDecode((await work.read())!) as Map;
      final restored =
          (after['scopes'] as Map).values.cast<Map>().single['inspect'] as Map;
      expect(restored['key'], original['key']);
      expect(restored['digest'], original['digest']);
      expect(restored['file'], original['file']);
      expect(restored['task'], isNotNull);
      debugPrint(
        'ARCHIVE_RESUME_VERIFIED:${jsonEncode({'original_key': original['key'], 'task': restored['task'], 'sha256': original['digest'], 'roots': 27, 'epoch': repo.api.managementEpoch, 'confirmation_off': true})}',
      );
      return;
    }
    await shot('backup-start');
    await preferences.setDark(true);
    await shot('backup-dark');
    await preferences.setDark(false);
    await t.pumpAndSettle();
    if (cancelInputs) {
      expect(nativeDocuments, isTrue);
      await t.tap(find.byKey(const Key('archive-export')));
      await until(() => find.text('保存已取消，原导出任务已保留').evaluate().isNotEmpty);
      expect(jsonDecode((await work.read())!), systemFiles.firstSaveJournal);
      await shot('save-cancelled');
      await journal('after-system-save-cancelled');
    }
    await t.tap(find.byKey(const Key('archive-export')));
    await until(() => find.text('已导出管理数据备份').evaluate().isNotEmpty);
    if (nativeDocuments) {
      expect(systemFiles.exportedBytes, greaterThan(0));
      expect(systemFiles.exportedSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      if (largeDocument) {
        expect(systemFiles.exportedBytes, greaterThan(32 * 1024 * 1024));
      }
    } else {
      await privateFiles.selected!.verify();
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await repo.api.json(
      'POST',
      '/api/v1/tags',
      body: {'name': '恢复前视频标签$stamp', 'request_id': 'late-video-$stamp'},
    );
    await repo.api.json(
      'POST',
      '/api/v1/pack-tags',
      body: {'name': '恢复前图包标签$stamp', 'request_id': 'late-pack-$stamp'},
    );
    await visible(find.byKey(const Key('archive-pick')));
    if (cancelInputs) {
      final originalJournal = jsonDecode((await work.read())!);
      await t.tap(find.byKey(const Key('archive-pick')));
      await until(() => systemFiles.cancelledPicks == 1);
      expect(find.byKey(const Key('archive-counts')), findsNothing);
      expect(jsonDecode((await work.read())!), originalJournal);
      await shot('pick-cancelled');
      await journal('after-system-pick-cancelled');
    }
    await t.tap(find.byKey(const Key('archive-pick')));
    await until(
      () => find.byKey(const Key('archive-counts')).evaluate().isNotEmpty,
    );
    await shot('restore-first-page');
    final mapping = find
        .byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.key is ValueKey<String> &&
              ((w.key! as ValueKey<String>).value).startsWith(
                'archive-mapping-',
              ),
        )
        .first;
    await visible(mapping);
    await t.tap(mapping);
    await until(() => MediaQueryData.fromView(t.view).viewInsets.bottom > 0);
    expect(
      t
          .widget<EditableText>(
            find.descendant(of: mapping, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await shot('restore-keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await until(() => MediaQueryData.fromView(t.view).viewInsets.bottom == 0);

    await visible(find.text('下一页'));
    await t.tap(find.text('下一页'));
    await until(() => find.text('媒体目录 · 已载入 27/27').evaluate().isNotEmpty);
    await visible(find.byKey(const Key('archive-confirm')));
    expect(
      t
          .widget<CheckboxListTile>(find.byKey(const Key('archive-confirm')))
          .value,
      isFalse,
    );
    await shot('restore-confirm-off');
    await journal('before-restore-confirmation');
    await t.tap(find.byKey(const Key('archive-confirm')));
    await t.pumpAndSettle();
    await visible(find.byKey(const Key('archive-restore-submit')));
    await t.tap(find.byKey(const Key('archive-restore-submit')));
    await until(
      () =>
          repo.snapshot.connected && repo.api.managementEpoch != originalEpoch,
    );
    await repo.managementSynchronization;
    expect(
      (await repo.api.json('GET', '/api/v1/tags'))['items'].toString(),
      isNot(contains('恢复前视频标签$stamp')),
    );
    expect(
      (await repo.api.json('GET', '/api/v1/pack-tags'))['items'].toString(),
      isNot(contains('恢复前图包标签$stamp')),
    );
    await show();
    expect(await repo.latestArchiveRestorePoint(), isNotNull);
    await t.pumpAndSettle();
    await visible(find.byKey(const Key('archive-restore-point')));
    await shot('backup-restore-point');
    await t.tap(find.byKey(const Key('archive-restore-point')));
    await until(
      () => find.byKey(const Key('archive-counts')).evaluate().isNotEmpty,
    );
    await shot('snapshot-preview');
    await visible(find.text('下一页'));
    await t.tap(find.text('下一页'));
    await until(() => find.text('媒体目录 · 已载入 27/27').evaluate().isNotEmpty);
    await visible(find.byKey(const Key('archive-confirm')));
    expect(
      t
          .widget<CheckboxListTile>(find.byKey(const Key('archive-confirm')))
          .value,
      isFalse,
    );
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('archive-restore-submit')))
          .onPressed,
      isNull,
    );
    await shot('snapshot-confirm-off');

    final catalog = repo.createMaintenanceTasks();
    final jobs = await catalog.page(family: 'backup', limit: 100);
    final restored = jobs.items.firstWhere(
      (v) => v.kind == 'backup_restore_v2' && !v.historical,
    );
    expect(restored.state, 'completed');
    final archive = catalog as ArchiveTaskFiles;
    final snapshot = await archive.restoreSnapshot(restored.id);
    expect(snapshot, isNotNull);
    final downloaded = await archive.downloadArchiveFile(snapshot!);
    await downloaded.document.verify();
    await downloaded.document.delete();
    catalog.dispose();
    await journal('after-restore-and-snapshot');
    expect(t.takeException(), isNull);
    debugPrint(
      'ARCHIVE_UI_VERIFIED:${jsonEncode({'roots': 27, 'epoch_changed': true, 'snapshot': snapshot, 'restore_task': restored.id, 'kind': restored.kind, 'state': restored.state, 'replacement_removed_late_tags': true, 'snapshot_not_confirmed': true, 'native_documents': nativeDocuments, 'document_bytes': systemFiles.exportedBytes, 'document_sha256': systemFiles.exportedSha256})}',
    );
  }, timeout: Timeout(Duration(minutes: largeDocument ? 10 : 5)));
}
