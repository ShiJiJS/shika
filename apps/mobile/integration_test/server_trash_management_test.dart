import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';
import 'package:shika/features/settings/maintenance_task_detail.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF6 typed trash, whole membership, uncertain restore and preserved media/reading',
    (t) async {
      const baseline = bool.fromEnvironment('TRASH_LAYOUT_BASELINE');
      final preferences = UiPreferences(preloadAdjacent: false);
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '恢复图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final all = await repo.loadPacks(PackQuery(), limit: 100);
      expect(all.total, 27);
      final first = all.items.first;
      final tag = await repo.createPackTag('恢复后保留');
      await repo.setPackTags(all.items.map((p) => p.id).toSet(), {tag.id});
      await t.pumpWidget(
        ShikaApp(repository: repo, preferences: preferences),
      );
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint('TRASH_TIMEOUT $why');
            debugPrint(
              t
                  .widgetList<Text>(find.byType(Text))
                  .map((v) => v.data)
                  .join(' | '),
            );
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 60));
        }
        await t.pump(const Duration(milliseconds: 150));
        final error = t.takeException();
        if (error != null) {
          await fixture('/__fixture/checkpoint/error');
          await t.pump(const Duration(seconds: 1));
        }
        expect(error, isNull);
      }

      Future<void> reveal(Finder target) async {
        for (final direction in [1, -1]) {
          for (var i = 0; target.evaluate().isEmpty && i < 60; i++) {
            final scroll = find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable &&
                      axisDirectionToAxis(w.axisDirection) == Axis.vertical,
                )
                .hitTestable();
            if (scroll.evaluate().isEmpty) break;
            await t.drag(scroll.first, Offset(0, -240.0 * direction));
            await t.pump(const Duration(milliseconds: 100));
          }
          if (target.evaluate().isNotEmpty) break;
        }
        await until(() => target.evaluate().isNotEmpty, 'target exists');
        // A completed restore may rebuild the lazy list while the condition
        // settles. Mount the target again after that real asynchronous read.
        if (target.evaluate().isEmpty) {
          await reveal(target);
          return;
        }
        await t.ensureVisible(target);
        await t.pump(const Duration(milliseconds: 180));
        await Scrollable.ensureVisible(t.element(target), alignment: .5);
        await t.pump(const Duration(milliseconds: 180));
        await until(
          () => target.hitTestable().evaluate().isNotEmpty,
          'visible target',
        );
      }

      Future<void> tap(Finder target) async {
        await reveal(target);
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 250));
      }

      Future<void> shot(String name) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled',
        );
        await t.pumpAndSettle();
        final m = MediaQueryData.fromView(t.view);
        if (name == 'keyboard') {
          expect(
            m.viewInsets.bottom,
            greaterThan(0),
            reason: 'Capture a stable real IME, not its opening transition',
          );
        }
        debugPrint(
          'TRASH_METRICS:${jsonEncode({
            'state': 'trash-$name',
            'window': [m.size.width, m.size.height],
            'dpr': m.devicePixelRatio,
            'text13': m.textScaler.scale(13),
            'viewPadding': [m.viewPadding.left, m.viewPadding.top, m.viewPadding.right, m.viewPadding.bottom],
            'keyboard': m.viewInsets.bottom,
            'dark': preferences.dark,
          })}',
        );
        await fixture('/__fixture/checkpoint/trash-$name');
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }

      await tap(find.byKey(const Key('kind-pack')));
      final tile = find.byKey(Key('pack-tile-${first.id}'));
      await until(
        () => t
            .widgetList<RawImage>(
              find.descendant(of: tile, matching: find.byType(RawImage)),
            )
            .any((v) => v.image != null),
        'cover',
      );
      await tap(tile);
      await until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            reader().session.opened &&
            !reader().session.inputBlocked,
        'actual first frame',
      );
      final sessionId = reader().session.range!.id;
      await tap(find.byTooltip('下一张'));
      await until(
        () => reader().session.index == 1 && reader().session.unsaved,
        'second page',
      );
      await tap(find.byTooltip('阅读设置'));
      await tap(find.text('纵向拼接'));
      await until(
        () =>
            reader().session.preferences.mode == ReaderMode.vertical &&
            !reader().session.busy,
        'vertical preference',
      );
      await tap(find.text('图片之间留间距'));
      await until(
        () => reader().session.preferences.gap && !reader().session.busy,
        'gap preference',
      );
      await tap(find.text('继续阅读'));
      await t.drag(
        find.byKey(const Key('reader-vertical')),
        const Offset(0, -80),
      );
      await until(
        () => reader().session.index == 1 && reader().session.offsetRatio > .02,
        'actual vertical inset',
      );
      expect(await reader().session.flush(), isTrue);
      await shot('reader');
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'source',
      );
      final beforePack = await repo.api.json(
        'GET',
        '/api/v1/packs/${first.id}',
      );
      final beforeRange = await repo.api.json(
        'GET',
        '/api/v1/pack-sessions/$sessionId',
      );
      final hashes = await fixture('/__fixture/actions/pack-trash-hashes');
      expect((hashes['hashes'] as Map).length, 81);
      final files = repo.createPackFiles();
      final command = PackFileCommand.trash(
        packFileRequestId(),
        all.items.map((p) => p.id),
      );
      final task = await files.resolve(command, submit: true);
      expect(task!.result!.succeeded, 27);
      await files.acknowledge(command);
      repo.packFilesChanged();
      expect((await repo.loadPacks(PackQuery())).total, 0);
      expect(
        (await repo.api.json(
          'GET',
          '/api/v1/recent',
          query: {'kind': 'pack'},
        ))['total'],
        0,
      );
      expect(
        (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes'],
        hashes['hashes'],
      );
      final listing = await repo.api.json(
        'GET',
        '/api/v1/pack-trash',
        query: {'limit': '200'},
      );
      final excluded = (listing['items'] as List).first['id'] as String;
      await repo.deleteVideos({
        repo.snapshot.videos.first.id,
      }, requestId: 'native-typed-trash-video');
      final video = (await repo.loadVideos(limit: 1)).items.single;
      await repo.beginPreview(VideoEntryScope(), anchor: video.id);
      final currentVideo = await repo.api.json(
        'GET',
        '/api/v1/playback',
        query: {'create': 'false'},
      );
      await fixture('/__fixture/actions/reset-task-trace');
      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('回收站'));
      await until(() => find.text('共 1 个视频').evaluate().isNotEmpty, 'video');
      await shot('video');
      await fixture('/__fixture/actions/fail-pack-trash-read');
      await tap(find.byKey(const Key('trash-kind-pack')));
      await until(
        () => find.byKey(const Key('pack-trash-retry')).evaluate().isNotEmpty,
        'read failure',
      );
      expect(find.text('图包回收站是空的'), findsNothing);
      expect(find.text('共 0 个图包'), findsNothing);
      await shot('read-error');
      await tap(find.byKey(const Key('pack-trash-retry')));
      await until(
        () => find.text('共 27 个图包').evaluate().isNotEmpty,
        '27 packs',
      );
      await shot('packs');
      final search = find.byKey(const Key('pack-trash-search'));
      await tap(search);
      await t.enterText(search, '不匹配的回收内容');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await until(
        () => MediaQueryData.fromView(t.view).viewInsets.bottom == 0,
        'keyboard hidden',
      );
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'empty search read settled',
      );
      await reveal(find.text('没有匹配的图包'));
      await shot('empty');
      await tap(search);
      await t.enterText(search, '图包');
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'search all read settled',
      );
      await until(
        () => MediaQueryData.fromView(t.view).viewInsets.bottom > 0,
        'actual IME',
      );
      await shot('keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await until(
        () => MediaQueryData.fromView(t.view).viewInsets.bottom == 0,
        'keyboard hidden',
      );
      await reveal(find.text('共 27 个图包'));
      expect(find.text('共 27 个图包'), findsOneWidget);
      await tap(find.byKey(const Key('pack-trash-select-all')));
      await reveal(find.text('已选 27'));
      await tap(find.byKey(Key('pack-trash-item-$excluded')));
      await tap(find.byKey(const Key('pack-trash-next')));
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'page two settled',
      );
      await reveal(find.text('2 / 2'));
      await shot('paged');
      await reveal(find.byKey(const Key('pack-trash-restore')));
      await t.pumpAndSettle();
      expect(find.text('已选 26'), findsOneWidget);
      await shot('selected');
      await preferences.setDark(true);
      await shot('dark');
      await preferences.setDark(false);
      await t.pumpAndSettle();
      if (baseline) {
        expect(
          (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes'],
          hashes['hashes'],
        );
        debugPrint('TRASH_BASELINE_VERIFIED');
        return;
      }
      await tap(find.byKey(const Key('pack-trash-restore')));
      await until(
        () => find
            .byKey(const Key('pack-restore-plan-confirm'))
            .evaluate()
            .isNotEmpty,
        'confirm',
      );
      await shot('confirm');
      await tap(find.text('取消'));
      final cancelled =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(cancelled.where((e) => e['method'] != 'GET'), isEmpty);
      await fixture('/__fixture/actions/lose-file-response');
      await tap(find.byKey(const Key('pack-trash-restore')));
      await tap(find.byKey(const Key('pack-restore-plan-confirm')));
      await until(
        () => find
            .byKey(const Key('pack-trash-plans-pending'))
            .evaluate()
            .isNotEmpty,
        'original pending',
      );
      final plans = repo.createPackRestorePlans();
      final original = (await plans.pending()).single.command;
      expect(original.ids.length, 26);
      await shot('unknown');
      await tap(find.byKey(const Key('pack-trash-plans-pending')));
      await until(
        () => find.byType(MaintenanceTaskDetail).evaluate().isNotEmpty,
        'original task',
      );
      await shot('receipt');
      await tap(find.byTooltip('返回操作任务'));
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'excluded read settled',
      );
      await reveal(find.text('共 1 个图包'));
      await reveal(find.text('已选 0'));
      expect(find.text('已选 0'), findsOneWidget);
      await shot('restored');
      await tap(find.byKey(Key('pack-trash-row-restore-$excluded')));
      await until(
        () => find
            .byKey(const Key('pack-restore-plan-confirm'))
            .evaluate()
            .isNotEmpty,
        'single confirm',
      );
      await shot('single-confirm');
      await tap(find.text('取消'));
      expect((await repo.api.json('GET', '/api/v1/pack-trash'))['total'], 1);
      await tap(find.byKey(Key('pack-trash-row-restore-$excluded')));
      await tap(find.byKey(const Key('pack-restore-plan-confirm')));
      for (var i = 0; i < 50; i++) {
        if ((await repo.loadPacks(PackQuery())).total == 27) break;
        await t.pump(const Duration(milliseconds: 100));
      }
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'single restore reads settled',
      );
      await t.pumpAndSettle();
      await tap(find.byKey(const Key('pack-trash-refresh')));
      await tap(find.byTooltip('清除搜索'));
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'empty read settled',
      );
      await reveal(find.text('图包回收站是空的'));
      await until(
        () => find.text('图包回收站是空的').evaluate().isNotEmpty,
        'single restored',
      );
      await shot('single-restored');
      final afterPack = await repo.api.json('GET', '/api/v1/packs/${first.id}');
      final afterRange = await repo.api.json(
        'GET',
        '/api/v1/pack-sessions/$sessionId',
      );
      expect(afterPack['progress'], beforePack['progress']);
      expect(afterPack['tag_ids'], [tag.id]);
      expect(
        (afterRange['resume'] as Map)['preferences'],
        (beforeRange['resume'] as Map)['preferences'],
      );
      expect(
        (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes'],
        hashes['hashes'],
      );
      expect(
        await repo.api.json(
          'GET',
          '/api/v1/playback',
          query: {'create': 'false'},
        ),
        currentVideo,
      );
      expect((await repo.loadTrash()).total, 1);
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace
            .where(
              (e) =>
                  e['method'] == 'POST' &&
                  e['path'] == '/api/v1/pack-restore-plans',
            )
            .length,
        2,
      );
      expect(
        trace
            .where(
              (e) =>
                  e['method'] == 'GET' &&
                  (e['path'] as String).startsWith(
                    '/api/v1/pack-restore-requests/',
                  ),
            )
            .length,
        1,
      );
      expect(
        trace.where(
          (e) =>
              e['method'] != 'GET' && e['path'] != '/api/v1/pack-restore-plans',
        ),
        isEmpty,
      );
      debugPrint(
        'TRASH_MANAGEMENT_VERIFIED:${jsonEncode({'packs': 27, 'restored_bulk': 26, 'restored_single': 1, 'images': 81, 'original_posts': 2, 'receipt_gets': 1, 'cancel_zero_writes': true, 'reading_and_tags_preserved': true, 'video_unchanged': true})}',
      );
    },
  );
}
