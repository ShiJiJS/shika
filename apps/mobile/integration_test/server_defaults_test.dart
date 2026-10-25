import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/settings/default_settings_sheet.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF7 managed defaults preserve current range and opened pack; migration, cancellation and unknown receipt',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final credentials = SecureCredentialStore(
        key: 'video_viewer.connection.defaults.v1',
      );
      await credentials.clear();
      var repo = ServerLibraryRepository(credentials, port: 8761);
      final directory = await Directory.systemTemp.createTemp(
        'vv-defaults-native-',
      );
      final file = File('${directory.path}/preferences.json');
      await file.writeAsString(
        jsonEncode({
          'dark': false,
          'preloadAdjacent': false,
          'videoOrder': 'sequential',
        }),
      );
      var local = await UiPreferences.load(file: file);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        local.dispose();
        await directory.delete(recursive: true);
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '默认值图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final packs = await repo.loadPacks(PackQuery());
      expect(packs.total, 27);
      final reader = repo.createPackReader();
      final prior = await reader.submit(
        CreatePackReading(
          'native-defaults-opened',
          PackReadingEntry(PackQuery(), anchorId: packs.items.first.id),
        ),
      );
      final opened = await reader.submit(
        OpenPackReading(
          'native-defaults-freeze',
          prior.ownership!,
          prior.resume!.page.id,
        ),
      );
      expect(opened.preferences.mode, ReaderMode.horizontal);
      expect(opened.preferences.overridden, isTrue);
      reader.dispose();
      final first = (await repo.loadVideos(limit: 1)).items.single;
      await repo.beginPreview(
        VideoEntryScope(),
        anchor: first.id,
        order: PlayOrder.random,
      );
      final active = await repo.api.json(
        'GET',
        '/api/v1/playback',
        query: {'create': 'false'},
      );
      await fixture('/__fixture/actions/reset-task-trace');
      await t.pumpWidget(VideoViewerApp(repository: repo, preferences: local));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
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
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        for (final direction in [1, -1]) {
          for (
            var attempt = 0;
            target.evaluate().isEmpty && attempt < 12;
            attempt++
          ) {
            final scroll = find.byType(Scrollable).hitTestable();
            if (scroll.evaluate().isEmpty) break;
            await t.drag(scroll.last, Offset(0, -180.0 * direction));
            await t.pump(const Duration(milliseconds: 100));
          }
          if (target.evaluate().isNotEmpty) break;
        }
        expect(target.evaluate(), isNotEmpty);
        await t.ensureVisible(target.last);
        await until(
          () => target.last.hitTestable().evaluate().isNotEmpty,
          'tap $target',
        );
        await t.tap(target.last);
        await t.pump(const Duration(milliseconds: 220));
      }

      Future<void> settled() => until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'settings read',
      );
      Future<void> shot(String state) async {
        await settled();
        await fixture('/__fixture/checkpoint/defaults-$state');
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }

      Future<void> open(String title) async {
        await tap(find.text(title));
        await until(
          () => find.byType(DefaultSettingsSheet).evaluate().isNotEmpty,
          'settings sheet',
        );
        await settled();
      }

      await tap(find.byKey(const Key('nav-settings')));
      await open('默认播放顺序');
      expect(find.textContaining('此设备旧默认'), findsOneWidget);
      await shot('migration');
      await tap(find.text('选用本机旧顺序'));
      await tap(find.text('保存默认设置'));
      await until(
        () => find.byType(DefaultSettingsSheet).evaluate().isEmpty,
        'default saved',
      );
      expect(
        (await repo.api.json('GET', '/api/v1/playback-defaults'))['order'],
        'sequential',
      );
      expect(
        jsonEncode(
          await repo.api.json(
            'GET',
            '/api/v1/playback',
            query: {'create': 'false'},
          ),
        ),
        jsonEncode(active),
      );
      await open('默认播放顺序');
      expect(find.textContaining('此设备旧默认'), findsNothing);
      await shot('video');
      await tap(find.byTooltip('关闭面板'));
      await open('阅读偏好');
      await tap(find.text('纵向拼接'));
      await tap(find.byTooltip('关闭面板'));
      expect(
        (await repo.api.json('GET', '/api/v1/reading-defaults'))['mode'],
        'horizontal',
      );
      await open('阅读偏好');
      await tap(find.text('纵向拼接'));
      await tap(find.text('从右向左'));
      await tap(find.text('图片间距'));
      await tap(find.text('铺满宽度'));
      await shot('reader');
      await fixture('/__fixture/actions/lose-default-response');
      await tap(find.text('保存默认设置'));
      await until(
        () => find.textContaining('保存结果待核对').evaluate().isNotEmpty,
        'unknown settings reply',
      );
      await shot('unknown');
      await tap(find.text('核对原设置请求'));
      await until(
        () => find.byType(DefaultSettingsSheet).evaluate().isEmpty,
        'original defaults receipt',
      );
      expect(
        jsonEncode(
          await repo.api.json(
            'GET',
            '/api/v1/playback',
            query: {'create': 'false'},
          ),
        ),
        jsonEncode(active),
      );
      final currentReader = repo.createPackReader();
      final stillOpened = await currentReader.read(prior.id);
      expect(stillOpened.resume!.preferences.values, opened.preferences.values);
      final next = await currentReader.submit(
        CreatePackReading(
          'native-defaults-unread',
          PackReadingEntry(PackQuery(), anchorId: packs.items[1].id),
        ),
      );
      expect(next.resume!.preferences.mode, ReaderMode.vertical);
      expect(next.resume!.preferences.direction, ReaderDirection.rtl);
      expect(next.resume!.preferences.gap, isTrue);
      expect(next.resume!.preferences.fit, ReaderFit.width);
      expect(next.resume!.preferences.overridden, isFalse);
      currentReader.dispose();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 400));
      repo.dispose();
      local.dispose();
      repo = ServerLibraryRepository(credentials, port: 8761);
      await repo.initialize();
      local = await UiPreferences.load(file: file);
      expect(repo.snapshot.connected, isTrue);
      expect(local.preloadAdjacent, isFalse);
      expect(
        await repo.defaultVideoOrder(PlayOrder.random),
        PlayOrder.sequential,
      );
      await t.pumpWidget(VideoViewerApp(repository: repo, preferences: local));
      await tap(find.byKey(const Key('nav-settings')));
      await open('阅读偏好');
      await shot('reopened');
      final chosen = t.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '纵向拼接'),
      );
      expect(chosen.selected, isTrue);
      await tap(find.byTooltip('关闭面板'));
      await open('默认播放顺序');
      expect(find.textContaining('此设备旧默认'), findsNothing);
      await tap(find.byTooltip('关闭面板'));
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      final defaults = trace
          .where(
            (e) =>
                e['method'] == 'PATCH' &&
                [
                  '/api/v1/playback-defaults',
                  '/api/v1/reading-defaults',
                ].contains(e['path']),
          )
          .toList();
      expect(defaults.length, 2);
      expect(
        defaults
            .where((e) => e['path'] == '/api/v1/reading-defaults')
            .single['status'],
        503,
      );
      expect(
        trace
            .where(
              (e) => e['path'].startsWith(
                '/api/v1/pack-reading-requests/defaults/',
              ),
            )
            .length,
        1,
      );
      expect(
        trace.where(
          (e) => e['method'] == 'POST' && e['path'] == '/api/v1/rounds',
        ),
        isEmpty,
      );
      debugPrint(
        'VV_DEFAULTS_PROOF ${jsonEncode({'patches': defaults.length, 'old_pack_preserved': true, 'unread_pack_inherits': true, 'current_video_range_preserved': true, 'local_migration_reopened': true})}',
      );
    },
  );
}
