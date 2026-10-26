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
import 'package:video_viewer/library/request_scope.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import '../test/support/reveal_action.dart';

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

Future<Map<String, dynamic>> control(
  String path, {
  String method = 'GET',
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://10.0.2.2:8762/__archive_fixture$path'),
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
  testWidgets(
    'LF8 real App v2 export, keyboard mapping, replacement and snapshot',
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
      final preferences = UiPreferences(preloadAdjacent: false);
      await repo.connect('http://10.0.2.2', 8762, 'archive-app-isolated-only');
      final originalEpoch = repo.api.managementEpoch;
      expect(repo.archiveBackupsAvailable, isTrue);
      expect(repo.archiveMaximumBytes, 64 * 1024 * 1024);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await files.selected?.delete();
        repo.dispose();
        preferences.dispose();
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

      Future<void> visible(Finder target) => revealAction(t, target);

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
        await control('/checkpoint/archive-ui-$name', method: 'POST');
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (!(await control('/status'))['display_ack']) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Host did not capture $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
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
      await shot('backup-start');
      await preferences.setDark(true);
      await shot('backup-dark');
      await preferences.setDark(false);
      await t.pumpAndSettle();
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
      await shot('snapshot-confirm-off');

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
        'ARCHIVE_UI_VERIFIED:${jsonEncode({'roots': 27, 'epoch_changed': true, 'snapshot': snapshot, 'restore_task': restored.id, 'kind': restored.kind, 'state': restored.state, 'replacement_removed_late_tags': true, 'snapshot_not_confirmed': true})}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
