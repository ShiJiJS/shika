import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/settings/media_root_sheet.dart';
import 'package:video_viewer/features/settings/missing_media_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF7 real root policy, missing-pack preservation and original cleanup receipt',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final credentials = SecureCredentialStore(
        key: 'video_viewer.connection.missing.v1',
      );
      final commands = SecureFileCommandStore(
        key: 'video_viewer.pack_commands.missing.v1',
      );
      await credentials.clear();
      await commands.write(jsonEncode({'version': 1, 'scopes': {}}));
      var repo = ServerLibraryRepository(
        credentials,
        packCommands: commands,
        port: 8761,
      );
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      final video = (await repo.loadVideos(limit: 1)).items.single;
      await repo.beginPreview(
        VideoEntryScope(),
        anchor: video.id,
        order: PlayOrder.random,
      );
      final currentVideo = await repo.api.json(
        'GET',
        '/api/v1/playback',
        query: {'create': 'false'},
      );
      await fixture('/__fixture/actions/reset-task-trace');
      await t.pumpWidget(VideoViewerApp(repository: repo));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint(
              t
                  .widgetList<Text>(find.byType(Text))
                  .map((w) => w.data)
                  .join(' | '),
            );
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        await t.pump(const Duration(milliseconds: 120));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        for (final direction in [1, -1]) {
          for (var i = 0; target.evaluate().isEmpty && i < 60; i++) {
            final scroll = find.byType(Scrollable).hitTestable();
            if (scroll.evaluate().isEmpty) break;
            await t.drag(scroll.last, Offset(0, -200.0 * direction));
            await t.pump(const Duration(milliseconds: 100));
          }
          if (target.evaluate().isNotEmpty) break;
        }
        expect(target.evaluate(), isNotEmpty);
        await t.ensureVisible(target.last);
        await t.pump(const Duration(milliseconds: 120));
        await Scrollable.ensureVisible(t.element(target.last), alignment: .5);
        await t.pump(const Duration(milliseconds: 160));
        await until(
          () => target.last.hitTestable().evaluate().isNotEmpty,
          'action target is visible and hittable',
        );
        await t.tap(target.last);
        await t.pump(const Duration(milliseconds: 220));
      }

      Future<void> shot(String state) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled',
        );
        await fixture('/__fixture/checkpoint/$state');
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }

      Future<void> saveRoot() async {
        await tap(find.byKey(const Key('root-save')));
        await until(
          () => find.byType(MediaRootSheet).evaluate().isEmpty,
          'root saved',
        );
      }

      Future<void> editRoot() => tap(find.byTooltip('编辑目录 原生图包目录'));
      Future<void> enabled(bool value) async {
        await editRoot();
        final control = t.widget<SwitchListTile>(
          find.byKey(const Key('root-enabled')),
        );
        if (control.value != value) {
          await tap(find.byKey(const Key('root-enabled')));
        }
        await saveRoot();
      }

      Future<void> openMissing() async {
        await tap(find.text('缺失内容'));
        await until(
          () => find.byType(MissingMediaPage).evaluate().isNotEmpty,
          'missing page',
        );
        await tap(find.byKey(const Key('missing-kind-pack')));
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'missing list',
        );
      }

      Future<void> cleanup({bool cancel = false}) async {
        await tap(find.byKey(const Key('clear-missing-kind')));
        await tap(
          cancel
              ? find.text('取消').last
              : find.byKey(const Key('missing-confirm')),
        );
      }

      Future<Map<String, dynamic>> waitCleanup(int count) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (true) {
          final value = await fixture(
            '/__fixture/actions/missing-native-stats',
          );
          final jobs = value['cleanups'] as List;
          if (jobs.length == count &&
              jobs.every((j) => j['status'] == 'completed')) {
            return value;
          }
          if (DateTime.now().isAfter(deadline)) {
            fail('Cleanup did not settle: $value');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('媒体目录'));
      await tap(find.text('添加目录'));
      await t.enterText(find.byKey(const Key('root-name')), '原生图包目录');
      await t.enterText(find.byKey(const Key('root-path')), seed['path']);
      await tap(find.byKey(const Key('root-kind-pack')));
      await saveRoot();
      var roots =
          (await repo.api.json('GET', '/api/v1/roots'))['items'] as List;
      expect(
        roots.singleWhere((r) => r['path'] == seed['path'])['kind'],
        'pack',
      );
      await shot('roots-created');
      await enabled(false);
      await shot('roots-disabled');
      await enabled(true);
      await tap(find.text('同步外部变更'));
      await until(
        () =>
            !repo.libraryPreparation.value.scanning &&
            repo.libraryPreparation.value.ready,
        'real root scan',
      );
      final catalog = await repo.loadPacks(PackQuery());
      expect(catalog.total, 27);
      final first = catalog.items.firstWhere((p) => p.name == '图包01');
      final reader = repo.createPackReader();
      final range = await reader.submit(
        CreatePackReading(
          'missing-native-before',
          PackReadingEntry(PackQuery(), anchorId: first.id),
        ),
      );
      await reader.submit(
        OpenPackReading(
          'missing-native-open',
          range.ownership!,
          range.resume!.page.id,
        ),
      );
      reader.dispose();
      final label = await repo.createPackTag('缺失前标签');
      await repo.setPackTags({first.id}, {label.id});
      await editRoot();
      await tap(find.byKey(const Key('root-kind-video')));
      await tap(find.byKey(const Key('root-save')));
      await until(
        () => find.textContaining('已有内容的目录不能直接更改媒体类型').evaluate().isNotEmpty,
        'kind conflict retains form',
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('root-name')))
            .controller!
            .text,
        '原生图包目录',
      );
      await shot('roots-conflict');
      await tap(find.byTooltip('关闭面板'));
      await fixture('/__fixture/actions/missing-native-folders');
      await tap(find.text('同步外部变更'));
      await until(
        () => !repo.libraryPreparation.value.scanning,
        'missing scan',
      );
      await enabled(false);
      await openMissing();
      await until(
        () => find.text('共 25 个缺失图包').evaluate().isNotEmpty,
        '25 missing packs',
      );
      await tap(find.text('下一页'));
      await shot('missing-paged');
      await cleanup(cancel: true);
      expect(
        (await fixture('/__fixture/actions/missing-native-stats'))['cleanups'],
        isEmpty,
      );
      await cleanup();
      final preserved = await waitCleanup(1);
      expect(preserved['cleanups'][0]['result']['skipped'], 25);
      expect(preserved['first_pack']['progress'], isTrue);
      expect(preserved['first_pack']['tag_links'], 1);
      await tap(find.byTooltip('刷新缺失内容'));
      await shot('missing-preserved');
      await tap(find.byTooltip('返回媒体目录'));
      await enabled(true);
      await fixture('/__fixture/actions/return-native-missing-one');
      await openMissing();
      await fixture('/__fixture/actions/lose-missing-response');
      await cleanup();
      await until(
        () => find.text('查询原清理请求').evaluate().isNotEmpty,
        'unknown cleanup',
      );
      final completed = await waitCleanup(2);
      expect(completed['cleanups'][1]['result']['succeeded'], 24);
      expect(completed['cleanups'][1]['result']['skipped'], 1);
      await shot('missing-unknown');
      final pending = repo.createPackMissing();
      expect((await pending.pending()).length, 1);
      pending.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 500));
      repo.dispose();
      repo = ServerLibraryRepository(
        credentials,
        packCommands: commands,
        port: 8761,
      );
      await repo.initialize();
      expect(repo.snapshot.connected, isTrue);
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('媒体目录'));
      await openMissing();
      await until(
        () => find.text('查询原清理请求').evaluate().isNotEmpty,
        'secure journal reopened',
      );
      await shot('missing-reopened');
      await tap(find.text('查询原清理请求'));
      await until(
        () =>
            find.byKey(const Key('missing-cleanup-task')).evaluate().isNotEmpty,
        'original task',
      );
      await shot('missing-result');
      expect(find.text('共 1 个缺失图包'), findsOneWidget);
      final result = await fixture('/__fixture/actions/missing-native-stats');
      expect(result['first_pack']['id'], first.id);
      expect(result['first_pack']['status'], 'deleted');
      expect(result['first_pack']['progress'], isFalse);
      expect(result['first_pack']['preferences'], isFalse);
      expect(result['first_pack']['tag_links'], 0);
      expect(result['first_pack']['recent'], 0);
      expect(result['first_pack']['session_members'], 1);
      await tap(find.byKey(const Key('missing-cleanup-task')));
      await until(
        () => find.text('已保留，未清除').evaluate().isNotEmpty,
        'preserved member',
      );
      await tap(find.text('全部'));
      await until(
        () => find.text('共 25 项').evaluate().isNotEmpty,
        'all members',
      );
      await tap(find.text('下一页'));
      await shot('missing-task-paged');
      expect(
        jsonEncode(
          await repo.api.json(
            'GET',
            '/api/v1/playback',
            query: {'create': 'false'},
          ),
        ),
        jsonEncode(currentVideo),
      );
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace
            .where(
              (e) =>
                  e['method'] == 'POST' &&
                  e['path'] == '/api/v1/packs/forget-missing',
            )
            .length,
        2,
      );
      expect(
        trace
            .where(
              (e) =>
                  e['method'] == 'GET' &&
                  e['path'].startsWith('/api/v1/pack-missing-requests/'),
            )
            .length,
        1,
      );
      expect(
        trace.where(
          (e) =>
              e['method'] == 'POST' &&
              (e['path'].contains('/trash') ||
                  e['path'].contains('/permanent')),
        ),
        isEmpty,
      );
      debugPrint(
        'VV_MISSING_PROOF ${jsonEncode({'preserved_disabled': 25, 'removed': 24, 'returned_preserved': 1, 'old_id_retained': true, 'current_video_unchanged': true})}',
      );
    },
  );
}
