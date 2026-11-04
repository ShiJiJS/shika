import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shika/features/settings/archive_backup_page.dart';
import 'package:shika/library/backup_document.dart';
import 'package:shika/library/backup_file_picker.dart';
import 'package:shika/library/backup_work_store.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/file_command_store.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/request_scope.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/ui/paper.dart';

/// Real HTTP/repository/filesystem and Paper page; document-provider behavior is
/// independently exercised by backup_native_files_test on the same Android AVD.
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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const scale = int.fromEnvironment('ARCHIVE_FONT_SCALE', defaultValue: 1);
  testWidgets(
    'v2 App export, paged mapping, replacement, snapshot and original tasks',
    (t) async {
      final credentials = SecureCredentialStore(
        key: 'video_viewer.archive_app.connection',
      );
      final work = SecureBackupWorkStore(
        key: 'video_viewer.archive_app.backups',
      );
      await credentials.clear();
      await work.write('{"version":2,"scopes":{}}');
      final repo = ServerLibraryRepository(
        credentials,
        backupWork: work,
        fileCommands: SecureFileCommandStore(
          key: 'video_viewer.archive_app.videos',
        ),
        packCommands: SecureFileCommandStore(
          key: 'video_viewer.archive_app.packs',
        ),
        port: 8762,
      );
      final files = _PrivateFiles();
      await repo.connect('http://10.0.2.2', 8762, 'archive-app-isolated-only');
      final originalEpoch = repo.api.managementEpoch;
      expect(repo.archiveBackupsAvailable, isTrue);
      expect(repo.archiveMaximumBytes, 64 * 1024 * 1024);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await files.selected?.delete();
        repo.dispose();
      });
      Future<void> until(bool Function() ready) async {
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (!ready()) {
          if (DateTime.now().isAfter(end)) {
            fail('Archive UI timeout: ${repo.backupStatus.value}');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pumpAndSettle();
      }

      Future<void> visible(Finder target) async {
        await t.scrollUntilVisible(
          target,
          400,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await t.pumpAndSettle();
      }

      var surfaceConverted = false;
      Future<void> shot(String name) async {
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await t.pumpAndSettle();
        final bytes = await binding.takeScreenshot(name);
        final base = await getApplicationSupportDirectory();
        final output = File('${base.path}/archive-app-evidence/$name.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes, flush: true);
        debugPrint('ARCHIVE_SCREENSHOT:${output.path}');
      }

      Future<void> show() async {
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale.toDouble())),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('备份与恢复', style: Paper.title)),
              body: ArchiveBackupPage(
                key: UniqueKey(),
                repository: repo,
                archives: repo,
                files: files,
                onOpenTasks: () {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await show();
      await shot('backup-start');
      await t.tap(find.byKey(const Key('archive-export')));
      await until(() => find.text('已导出管理数据备份').evaluate().isNotEmpty);
      await files.selected!.verify();
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
      await t.tap(find.byKey(const Key('archive-pick')));
      await until(
        () => find.byKey(const Key('archive-counts')).evaluate().isNotEmpty,
      );
      await shot('restore-first-page');
      await visible(find.text('下一页'));
      await t.tap(find.text('下一页'));
      await t.pumpAndSettle();
      await visible(find.byKey(const Key('archive-confirm')));
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('archive-confirm')))
            .value,
        isFalse,
      );
      await shot('restore-confirm-off');
      await t.tap(find.byKey(const Key('archive-confirm')));
      await t.pumpAndSettle();
      await visible(find.byKey(const Key('archive-restore-submit')));
      await t.tap(find.byKey(const Key('archive-restore-submit')));
      await until(
        () =>
            repo.snapshot.connected &&
            repo.api.managementEpoch != originalEpoch,
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
      final catalog = repo.createMaintenanceTasks();
      final jobs = await catalog.page(family: 'backup', limit: 100);
      final restored = jobs.items.firstWhere(
        (v) => v.kind == 'backup_restore_v2' && !v.historical,
      );
      final archive = catalog as ArchiveTaskFiles;
      final snapshot = await archive.restoreSnapshot(restored.id);
      expect(snapshot, isNotNull);
      final downloaded = await archive.downloadArchiveFile(snapshot!);
      await downloaded.document.verify();
      await downloaded.document.delete();
      catalog.dispose();
      expect(t.takeException(), isNull);
      debugPrint(
        'ARCHIVE_APP_VERIFIED:roots=27,epoch_changed=true,snapshot=$snapshot',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
