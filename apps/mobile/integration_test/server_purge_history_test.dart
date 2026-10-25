import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/backup_work_store.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

Future<Map<String, dynamic>> control(
  String path, {
  String method = 'GET',
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://10.0.2.2:8763/__history_fixture$path'),
    );
    request.headers.set('X-Fixture-Key', 'history-purge-isolated-control');
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('History control ${response.statusCode}:$path');
    }
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'settings original graph purge plan, files, partial result and read-only retry',
    (t) async {
      final setup = await control('/setup');
      final credentials = SecureCredentialStore(
        key: 'video_viewer.purge_history.connection',
      );
      final packs = SecureFileCommandStore(
        key: 'video_viewer.purge_history.packs',
      );
      final videos = SecureFileCommandStore(
        key: 'video_viewer.purge_history.videos',
      );
      final backups = SecureBackupWorkStore(
        key: 'video_viewer.purge_history.backups',
      );
      await credentials.clear();
      await packs.write('{"version":1,"scopes":{}}');
      await videos.write('{"version":2,"scopes":{}}');
      await backups.write('{"version":2,"scopes":{}}');
      final repo = ServerLibraryRepository(
        credentials,
        packCommands: packs,
        fileCommands: videos,
        backupWork: backups,
        port: 8763,
      );
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect(
        'http://10.0.2.2',
        8763,
        'history-purge-isolated-only',
      );
      expect(repo.capabilities.managementPurgeHistory, isTrue);
      final catalog = repo.createMaintenanceTasks();
      await catalog.pending();
      catalog.dispose();
      final journals = [
        await packs.read(),
        await videos.read(),
        await backups.read(),
      ];
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );

      Future<void> until(bool Function() ready, String reason) async {
        final end = DateTime.now().add(const Duration(seconds: 45));
        while (!ready()) {
          if (DateTime.now().isAfter(end)) fail('History App timeout: $reason');
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 180));
        expect(t.takeException(), isNull);
      }

      bool enabled(Element element) {
        bool? value;
        void inspect(Widget widget) {
          if (widget is ButtonStyleButton) value = widget.onPressed != null;
          if (widget is ListTile) value = widget.onTap != null;
          if (widget is ChoiceChip) value = widget.onSelected != null;
          if (widget is IconButton) value = widget.onPressed != null;
          if (widget is DropdownButton<String>) {
            value = widget.onChanged != null;
          }
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

      Future<void> tap(
        Finder target, {
        bool activate = true,
        bool waitEnabled = false,
      }) async {
        final end = DateTime.now().add(const Duration(seconds: 60));
        var direction = 1;
        bool ready() =>
            target.hitTestable().evaluate().length == 1 &&
            (!activate && !waitEnabled ||
                target.hitTestable().evaluate().every(enabled));
        while (!ready()) {
          if (DateTime.now().isAfter(end)) {
            debugPrint(
              'HISTORY_VISIBLE:${t.widgetList<Text>(find.byType(Text)).map((v) => v.data).join(' | ')}',
            );
            fail(
              'History control did not become actionable; see visible text above',
            );
          }
          final list = find.byType(ListView).hitTestable();
          if (target.hitTestable().evaluate().isEmpty &&
              list.evaluate().isNotEmpty) {
            final scrollable = find
                .descendant(of: list.last, matching: find.byType(Scrollable))
                .first;
            final state = t.state<ScrollableState>(scrollable);
            final before = state.position.pixels;
            await t.drag(list.last, Offset(0, -260.0 * direction));
            await t.pump(const Duration(milliseconds: 100));
            if (state.mounted && (state.position.pixels - before).abs() < 1) {
              direction = -direction;
            }
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(target.hitTestable(), findsOneWidget);
        if (activate) await t.tap(target.hitTestable());
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

      Future<void> noCommands() async {
        expect(find.text('重试原任务'), findsNothing);
        expect(find.text('确认永久删除'), findsNothing);
        expect(find.text('确认删除'), findsNothing);
        expect([
          await packs.read(),
          await videos.read(),
          await backups.read(),
        ], journals);
      }

      await tap(find.text('设置'));
      await tap(find.text('操作任务'));
      await tap(find.byKey(const Key('task-filter-historical')));
      await tap(find.byKey(Key('maintenance-task-${setup['purge_id']}')));
      await tap(find.byKey(const Key('task-history-image-results')));
      await until(
        () => find.text('当时没有读取或删除权限').evaluate().isNotEmpty,
        'original permission failure',
      );
      await tap(find.text('当时没有读取或删除权限').first, activate: false);
      await shot('history-original-partial');
      await noCommands();
      await tap(find.byKey(const Key('purge-history-outcome-false')));
      await tap(
        find.byKey(const Key('purge-history-next')),
        activate: false,
        waitEnabled: true,
      );
      await control('/fail-next/pages', method: 'POST');
      await tap(find.byKey(const Key('purge-history-next')));
      await until(
        () =>
            find.byKey(const Key('purge-history-error')).evaluate().isNotEmpty,
        'next page 503 shown',
      );
      await tap(find.byKey(const Key('purge-history-next')), activate: false);
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('purge-history-previous')))
            .onPressed,
        isNull,
      );
      await shot('history-query-error-kept-page');
      await noCommands();
      await tap(find.byKey(const Key('purge-history-next')));
      await until(
        () => find.byKey(const Key('purge-history-error')).evaluate().isEmpty,
        'same original page query retried',
      );
      await tap(
        find.byKey(const Key('purge-history-previous')),
        activate: false,
      );
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('purge-history-previous')))
            .onPressed,
        isNotNull,
      );
      await shot('history-result-next-page');
      await tap(find.byKey(const Key('purge-history-kind')));
      await tap(find.text('只看目录').last);
      await tap(find.byTooltip('查询原历史记录'), activate: false, waitEnabled: true);
      await tap(find.byKey(const Key('purge-history-total')), activate: false);
      await shot('history-directory-results');
      await noCommands();
      await tap(find.byKey(const Key('purge-history-review')));
      await tap(find.byKey(const Key('purge-history-next')));
      await tap(find.byKey(const Key('purge-history-total')), activate: false);
      expect(
        t.widget<Text>(find.byKey(const Key('purge-history-total'))).data,
        '共 27 项',
      );
      await shot('history-last-three-packs');
      if (setup['large_member_offset'] == 0) {
        await tap(find.byKey(const Key('purge-history-previous')));
      }
      final member = Map<String, dynamic>.from(setup['large_member'] as Map);
      await tap(find.byKey(Key('purge-history-pack-${member['trash_id']}')));
      await tap(find.byKey(const Key('purge-history-next')));
      await tap(find.text('127 · 0127.png'), activate: false);
      await shot('history-last-image-page');
      await noCommands();
      await tap(find.byTooltip('返回历史清单'));
      await tap(find.byTooltip('返回任务详情'));
      await tap(find.byTooltip('返回操作任务'));
      await tap(find.byKey(Key('maintenance-task-${setup['plan_id']}')));
      await tap(find.byKey(const Key('task-history-purge-review')));
      await until(
        () =>
            find.byKey(const Key('purge-history-review')).evaluate().isNotEmpty,
        'original preview review',
      );
      expect(find.byKey(const Key('purge-history-results')), findsNothing);
      await shot('history-original-preview');
      await noCommands();
      expect(repo.api.managementEpoch, setup['current_epoch']);
      expect(t.takeException(), isNull);
      debugPrint(
        'HISTORY_PURGE_VERIFIED:${jsonEncode({'purge_id': setup['purge_id'], 'plan_id': setup['plan_id'], 'graph_id': setup['graph_id'], 'packs': 27, 'images_in_large_pack': 127, 'journals_unchanged': true})}',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
