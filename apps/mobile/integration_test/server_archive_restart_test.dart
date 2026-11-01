import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/settings/archive_backup_page.dart';
import 'package:video_viewer/library/backup_file_picker.dart';
import 'package:video_viewer/library/backup_work_store.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

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
  const resume = bool.fromEnvironment('ARCHIVE_RESTART_RESUME');
  const phase = String.fromEnvironment(
    'ARCHIVE_RESTART_PHASE',
    defaultValue: 'snapshot_written',
  );
  testWidgets(
    'v2 original secure journals survive actual force-stop and epoch replacement',
    (t) async {
      final credentials = SecureCredentialStore(
        key: 'video_viewer.archive_restart.connection',
      );
      final backups = SecureBackupWorkStore(
        key: 'video_viewer.archive_restart.backups',
      );
      final packs = SecureFileCommandStore(
        key: 'video_viewer.archive_restart.packs',
      );
      final videos = SecureFileCommandStore(
        key: 'video_viewer.archive_restart.videos',
      );
      final metadata = SecureFileCommandStore(
        key: 'video_viewer.archive_restart.metadata',
      );
      final repo = ServerLibraryRepository(
        credentials,
        backupWork: backups,
        packCommands: packs,
        fileCommands: videos,
        port: 8762,
      );
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      Future<void> until(bool Function() ready, String reason) async {
        final end = DateTime.now().add(const Duration(seconds: 60));
        while (!ready()) {
          if (DateTime.now().isAfter(end)) {
            fail(
              'Archive restart timeout: $reason; ${repo.backupStatus.value}',
            );
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target, {bool activate = true}) async {
        final end = DateTime.now().add(const Duration(seconds: 45));
        var attempts = 0, direction = 1;
        bool enabled(Element element) {
          bool? value;
          void inspect(Widget widget) {
            if (widget is ButtonStyleButton) value = widget.onPressed != null;
            if (widget is CheckboxListTile) value = widget.onChanged != null;
            if (widget is ListTile) value = widget.onTap != null;
            if (widget is ChoiceChip) value = widget.onSelected != null;
          }

          inspect(element.widget);
          if (value == null) {
            element.visitAncestorElements((parent) {
              inspect(parent.widget);
              return value == null;
            });
          }
          return value ?? true;
        }

        bool ready() =>
            target.hitTestable().evaluate().isNotEmpty &&
            target.evaluate().every(enabled);
        while (!ready()) {
          if (DateTime.now().isAfter(end)) {
            debugPrint(
              'ARCHIVE_RESTART_VISIBLE:${t.widgetList<Text>(find.byType(Text)).map((v) => v.data).join(' | ')}',
            );
            fail('Control did not become visible: $target');
          }
          final list = find.byType(ListView).hitTestable();
          if (target.hitTestable().evaluate().isEmpty &&
              list.evaluate().isNotEmpty) {
            await t.drag(list.last, Offset(0, -250.0 * direction));
            if (++attempts % 35 == 0) direction = -direction;
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(target.hitTestable(), findsOneWidget);
        if (activate) await t.tap(target);
        await t.pump(const Duration(milliseconds: 180));
      }

      Future<void> shot(String name) async {
        await control('/checkpoint/$name', method: 'POST');
        final end = DateTime.now().add(const Duration(seconds: 25));
        while (!(await control('/status'))['display_ack']) {
          if (DateTime.now().isAfter(end)) fail('Host did not capture $name');
          await t.pump(const Duration(milliseconds: 120));
        }
      }

      Future<void> checkPackBook(Map<String, dynamic> original) async {
        final actual = Map<String, dynamic>.from(
          jsonDecode((await packs.read())!) as Map,
        );
        final before = original['pack_book'] as Map;
        final scope = original['scope'];
        expect(
          (actual['scopes'] as Map)[scope],
          (before['scopes'] as Map)[scope],
        );
        final oldSelections =
            ((before['purge_selections_v1'] as Map)[scope] as Map);
        final selections =
            ((actual['purge_selections_v1'] as Map)[scope] as Map);
        expect(selections, {
          for (final e in oldSelections.entries)
            e.key: {
              ...Map<String, dynamic>.from(e.value as Map),
              'historical': true,
            },
        });
      }

      Map<String, dynamic> original;
      if (!resume) {
        await credentials.clear();
        await backups.write('{"version":2,"scopes":{}}');
        await packs.write('{"version":1,"scopes":{}}');
        await videos.write('{"version":2,"scopes":{}}');
        await repo.connect(
          'http://10.0.2.2',
          8762,
          'archive-app-isolated-only',
        );
        final saved = (await credentials.read())!;
        final scope = jsonEncode([
          saved.endpoint.toString(),
          saved.serverId,
          saved.managementEpoch,
        ]);
        final exported = await repo.exportArchive();
        final preview = await repo.inspectArchive(exported.document);
        expect(preview.rootsTotal, 27);
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final pack =
            ((await repo.api.json('GET', '/api/v1/packs'))['items'] as List)
                    .first
                as Map;
        final files = repo.createPackFiles();
        final trashCommand = PackFileCommand.trash('restart-trash-$stamp', [
          pack['id'] as String,
        ]);
        final trashed = (await files.resolve(trashCommand, submit: true))!;
        expect(trashed.result!.succeeded, 1);
        final selection = await PackPurgeSelections(files)
            .save([trashed.result!.items.single.trashId]);
        final restoreCommand = PackFileCommand.restore(
          'restart-pack-restore-$stamp',
          [trashed.result!.items.single.trashId],
        );
        final restored = (await files.resolve(restoreCommand, submit: true))!;
        expect(restored.result!.succeeded, 1);
        final late = await repo.api.json(
          'POST',
          '/api/v1/pack-tags',
          body: {'name': '强停前图包标签$stamp', 'request_id': 'restart-late-$stamp'},
        );
        original = {
          'scope': scope,
          'epoch': saved.managementEpoch,
          'phase': phase,
          'file': exported.document.toJson(),
          'export': exported.taskId,
          'inspect': preview.taskId,
          'selection': selection.id,
          'late_tag': late['id'],
          'pack_id': pack['id'],
          'pack_tasks': {
            trashCommand.requestId: {'id': trashed.id, 'kind': trashed.kind},
            restoreCommand.requestId: {
              'id': restored.id,
              'kind': restored.kind,
            },
          },
        };
        await metadata.write(jsonEncode(original));
        expect(await repo.createMaintenanceTasks().pending(), hasLength(5));
        await control('/arm/$phase', method: 'POST');
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            debugShowCheckedModeBanner: false,
            home: ArchiveRestorePage(
              repository: repo,
              archives: repo,
              preview: preview,
            ),
          ),
        );
        await until(
          () =>
              find.byKey(const Key('archive-root-count')).evaluate().isNotEmpty,
          'root page',
        );
        await tap(find.text('下一页'));
        await until(
          () => find.text('2 / 2').evaluate().isNotEmpty,
          'all roots',
        );
        await tap(find.byKey(const Key('archive-confirm')), activate: false);
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('archive-confirm')),
              )
              .value,
          isFalse,
        );
        await tap(find.byKey(const Key('archive-confirm')));
        // The real widget starts unchecked; inspect before submitting its sole POST.
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('archive-confirm')),
              )
              .value,
          isTrue,
        );
        await shot('restart-confirmed');
        await tap(find.byKey(const Key('archive-restore-submit')));
        final end = DateTime.now().add(const Duration(seconds: 70));
        while (true) {
          final state = await control('/status');
          if (state['hit'] == phase && state['response_held'] == true) break;
          if (DateTime.now().isAfter(end)) fail('Restore never reached $phase');
          await t.pump(const Duration(milliseconds: 150));
        }
        final book = Map<String, dynamic>.from(
          jsonDecode((await backups.read())!) as Map,
        );
        final old = Map<String, dynamic>.from(
          (book['scopes'] as Map)[scope] as Map,
        );
        final command = Map<String, dynamic>.from(old['restore'] as Map);
        expect(command['version'], 2);
        expect(command['task'], isNull);
        original = {
          ...original,
          'request_id': command['key'],
          'backup_scope': old,
          'pack_book': jsonDecode((await packs.read())!),
        };
        await metadata.write(jsonEncode(original));
        await shot('restart-unknown-before-stop');
        debugPrint(
          'ARCHIVE_RESTART_STOP_READY:${jsonEncode({'phase': phase, 'request_id': command['key'], 'scope': scope})}',
        );
        while (true) {
          await t.pump(const Duration(milliseconds: 200));
        }
      } else {
        original = Map<String, dynamic>.from(
          jsonDecode((await metadata.read())!) as Map,
        );
        expect(original['phase'], phase);
        expect((await credentials.read())!.managementEpoch, original['epoch']);
        await t.pumpWidget(
          VideoViewerApp(
            repository: repo,
            preferences: preferences,
            initializeRepository: true,
          ),
        );
        await until(
          () =>
              repo.snapshot.connected && find.text('设置').evaluate().isNotEmpty,
          'new process reconnects',
        );
        expect(repo.api.managementEpoch, isNot(original['epoch']));
        expect(
          (await credentials.read())!.managementEpoch,
          repo.api.managementEpoch,
        );
        expect(find.text('个人口令'), findsNothing);
        debugPrint('ARCHIVE_RESTART_NEW_PROCESS');
        final catalog = repo.createMaintenanceTasks();
        final pending = await catalog.pending();
        expect(pending, hasLength(6));
        expect(
          pending.every(
            (r) => r.historical && r.journalScope == original['scope'],
          ),
          isTrue,
        );
        final originalFiles = await NativeBackupArchiveFiles.storeFor(
          original['scope'] as String,
        );
        final document = originalFiles.restore(
          Map<String, dynamic>.from(original['file'] as Map),
        );
        await document.verify();
        final before = Map<String, dynamic>.from(
          jsonDecode((await backups.read())!) as Map,
        )['scopes'][original['scope']];
        expect(before, original['backup_scope']);
        await checkPackBook(original);
        final restoreReceipt = pending.singleWhere(
          (r) =>
              r.source == MaintenanceReceiptSource.backup &&
              r.kind == 'restore',
        );
        expect(restoreReceipt.requestId, original['request_id']);
        expect(restoreReceipt.protocolVersion, 2);
        final completed = (await catalog.reconcile(restoreReceipt))!;
        expect(completed.kind, 'backup_restore_v2');
        expect(completed.status, 'completed');
        expect(completed.historical, isTrue);
        final graphs = <Map<String, dynamic>>[];
        for (final receipt in pending.where(
          (r) => r.source == MaintenanceReceiptSource.pack,
        )) {
          final expected =
              (original['pack_tasks'] as Map)[receipt.requestId] as Map;
          final task = (await catalog.reconcile(receipt))!;
          expect(task.id, expected['id']);
          expect(task.kind, expected['kind']);
          expect(task.historical, isTrue);
          expect(task.succeeded, 1);
          expect(task.graphId, isNotNull);
          graphs.add({
            'request_id': receipt.requestId,
            'id': task.id,
            'graph_id': task.graphId,
          });
          final detail = (catalog as GraphTaskCatalog).forTask(task);
          expect((await detail.task(task.id)).historical, isTrue);
          final members = await detail.items(task.id, unfinished: false);
          expect(members.total, 1);
          expect(members.items.single.outcome, 'succeeded');
          detail.dispose();
        }
        expect(
          (await repo.api.json('GET', '/api/v1/pack-tags'))['items'].toString(),
          isNot(contains(original['late_tag'])),
        );
        await tap(find.text('设置'));
        await tap(find.text('操作任务'));
        await until(
          () => find.text('本机 6 项历史记录').evaluate().isNotEmpty,
          'six historical intents',
        );
        await tap(find.byKey(const Key('task-filter-historical')));
        await until(
          () => find.text('本机 6 项历史记录').evaluate().isNotEmpty,
          'historical filter',
        );
        await shot('restart-historical-intents');
        await tap(find.byKey(Key('task-receipt-${restoreReceipt.id}')));
        await tap(
          find.byKey(const Key('task-download-snapshot')),
          activate: false,
        );
        await shot('restart-original-restore');
        debugPrint('ARCHIVE_RESTART_CANCEL_SAF');
        await tap(find.byKey(const Key('task-download-snapshot')));
        await until(
          () =>
              t
                  .widget<TextButton>(
                    find.byKey(const Key('task-download-snapshot')),
                  )
                  .onPressed !=
              null,
          'snapshot system save cancelled',
        );
        expect(find.text('恢复前快照已保存'), findsNothing);
        await tap(find.byTooltip('返回操作任务'));
        await t.pump(const Duration(milliseconds: 200));
        final selection = pending.singleWhere(
          (r) => r.source == MaintenanceReceiptSource.purgeSelection,
        );
        await tap(find.byKey(Key('task-receipt-${selection.id}')));
        await until(
          () => find
              .byKey(const Key('purge-selection-remaining'))
              .evaluate()
              .isNotEmpty,
          'historical choice',
        );
        expect(find.byKey(const Key('purge-selection-next')), findsNothing);
        await shot('restart-readonly-selection');
        await document.verify();
        final after = Map<String, dynamic>.from(
          jsonDecode((await backups.read())!) as Map,
        )['scopes'][original['scope']];
        expect(after, original['backup_scope']);
        await checkPackBook(original);
        expect((await catalog.pending()).every((r) => r.historical), isTrue);
        catalog.dispose();
        expect(t.takeException(), isNull);
        debugPrint(
          'ARCHIVE_RESTART_VERIFIED:${jsonEncode({'request_id': original['request_id'], 'restore_id': completed.id, 'original_epoch': original['epoch'], 'current_epoch': repo.api.managementEpoch, 'retained_intents': 6, 'graphs': graphs, 'file_bytes': document.bytes, 'file_sha256': document.sha256})}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
