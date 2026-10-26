import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';
import '../test/support/reveal_action.dart';

import 'package:video_viewer/ui/preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF8 purge management, exact review, cancellation and partial retry',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      await fixture('/__fixture/actions/purge-pack-attachments');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '永久删除图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final videos = await repo.loadVideos(limit: 1);
      final videoId = videos.items.single.id;
      await repo.deleteVideos({
        videoId,
      }, requestId: 'native-purge-video-marker');
      final originalVideoTrash = await repo.api.json('GET', '/api/v1/trash');
      final all = await repo.loadPacks(PackQuery(), limit: 100);
      expect(all.total, 27);
      final first = all.items.first;
      final files = repo.createPackFiles();
      final logical = PackFileCommand.trash('native-purge-logical', [first.id]);
      final moved = await files.resolve(logical, submit: true);
      expect(moved!.result!.succeeded, 1);
      await files.acknowledge(logical);
      final trash = await repo.createPackTrash().page();
      final trashId = trash.items.single.id;
      final originalHashes =
          (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes']
              as Map;
      expect(originalHashes.length, 108);
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
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
        await t.pump(const Duration(milliseconds: 160));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target, {double scroll = 300}) async {
        await revealAction(t, target);
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 180));
        expect(t.takeException(), isNull);
      }

      Future<void> back(String label) async {
        final modern = find.byTooltip(label);
        await tap(
          modern.evaluate().isNotEmpty ? modern : find.byTooltip('关闭面板').last,
        );
      }

      Future<void> savedBack() async {
        final modern = find.byTooltip('返回回收站');
        await tap(
          modern.evaluate().isNotEmpty ? modern : find.byTooltip('Back'),
        );
      }

      Future<void> shot(String name) async {
        await until(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'reads settled before screenshot',
        );
        await t.pump(const Duration(milliseconds: 250));
        final view = MediaQueryData.fromView(t.view);
        debugPrint(
          'PURGE_MANAGEMENT_METRICS:${jsonEncode({
            'state': 'purge-ui-$name',
            'window': [view.size.width, view.size.height],
            'dpr': view.devicePixelRatio,
            'text13': view.textScaler.scale(13),
            'viewPadding': [view.viewPadding.left, view.viewPadding.top, view.viewPadding.right, view.viewPadding.bottom],
            'keyboard': view.viewInsets.bottom,
            'dark': preferences.dark,
          })}',
        );
        await fixture('/__fixture/checkpoint/purge-ui-$name');
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }

      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('回收站'));
      await tap(find.byKey(Key('trash-$videoId')));
      await tap(find.byKey(const Key('video-trash-permanent')));
      if (!const bool.fromEnvironment('PURGE_LAYOUT_BASELINE')) {
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('video-purge-confirm')),
              )
              .value,
          isFalse,
        );
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('video-purge-submit')))
              .onPressed,
          isNull,
        );
      }
      await shot('video-confirm');
      await tap(find.text('取消').last);
      expect(await repo.api.json('GET', '/api/v1/trash'), originalVideoTrash);
      await tap(find.byKey(const Key('trash-kind-pack')));
      await tap(find.byKey(Key('pack-trash-item-$trashId')));
      await shot('selected');
      await fixture(
        '/__fixture/actions/lose-file-response',
      ); // Accepted preparation loses its reply.
      await tap(find.byKey(const Key('pack-trash-permanent')));
      await until(
        () => find.byKey(const Key('pack-purge-summary')).evaluate().isNotEmpty,
        'exact preview',
      );
      final submit = find.byKey(const Key('pack-purge-submit'));
      await until(
        () =>
            t
                .widget<CheckboxListTile>(
                  find.byKey(const Key('pack-purge-confirmation')),
                )
                .onChanged !=
            null,
        'ready preview',
      );
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await shot('review');
      await tap(find.text('查看图包和图片清单'));
      await shot('members');
      await tap(find.text(first.name).last);
      await until(
        () => find.text('10.jpg').evaluate().isNotEmpty,
        'exact image list',
      );
      await shot('files');
      await back('返回图包清单');
      await back('返回删除复核');
      await tap(find.text('取消').last);
      expect(
        (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes'],
        originalHashes,
      );
      // Leaving the cancelled review retains the complete choice, but opening
      // its new home must not prepare or authorize another physical operation.
      final beforeSaved =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      final beforeSavedPosts = beforeSaved
          .where((r) => r['method'] == 'POST')
          .length;
      await tap(find.byKey(const Key('pack-trash-saved-purge')), scroll: -300);
      await until(
        () => find.text('1 个未提交').evaluate().isNotEmpty,
        'saved selection',
      );
      await shot('saved');
      await preferences.setDark(true);
      // Theme and nested button/default-text animations finish on distinct
      // frames. A single large pump can capture their intermediate pairing.
      await t.pumpAndSettle();
      for (final label in ['重新读取', '移除保存的选择', '核对下一批 1 个']) {
        final text = find.text(label);
        final span = t
            .widget<RichText>(
              find.descendant(of: text, matching: find.byType(RichText)),
            )
            .text;
        final background = label.startsWith('核对')
            ? t
                  .widget<Material>(
                    find
                        .descendant(
                          of: find.byKey(const Key('purge-selection-next')),
                          matching: find.byType(Material),
                        )
                        .first,
                  )
                  .color!
            : Theme.of(t.element(text)).scaffoldBackgroundColor;
        final a = span.style!.color!.computeLuminance(),
            b = background.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
          greaterThanOrEqualTo(4.5),
          reason: 'Settled dark action: $label',
        );
      }
      await shot('saved-dark');
      await preferences.setDark(false);
      await t.pumpAndSettle();
      await savedBack();
      await tap(find.byKey(const Key('pack-trash-saved-purge')), scroll: -300);
      await until(
        () => find.text('1 个未提交').evaluate().isNotEmpty,
        'reopened saved selection',
      );
      await shot('saved-reopened');
      final afterSaved =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        afterSaved.where((r) => r['method'] == 'POST').length,
        beforeSavedPosts,
      );
      await savedBack();
      await tap(find.byKey(const Key('pack-trash-permanent')));
      await until(
        () =>
            find
                .byKey(const Key('pack-purge-confirmation'))
                .evaluate()
                .isNotEmpty &&
            t
                    .widget<CheckboxListTile>(
                      find.byKey(const Key('pack-purge-confirmation')),
                    )
                    .onChanged !=
                null,
        'new preview',
      );
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await tap(find.byKey(const Key('pack-purge-confirmation')));
      await fixture('/__fixture/actions/fail-pack-purge');
      await fixture('/__fixture/actions/lose-file-response');
      await tap(submit);
      await until(
        () =>
            find.byKey(const Key('pack-operation-error')).evaluate().isNotEmpty,
        'lost deletion response',
      );
      await shot('unknown');
      await tap(find.text('稍后处理'));
      await tap(find.byKey(const Key('pack-trash-pending')), scroll: -300);
      await until(
        () => find.text('已确认删除 2/3 张').evaluate().isNotEmpty,
        'partial receipt',
      );
      await shot('result');
      final partialHashes =
          (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes']
              as Map;
      expect(partialHashes.length, 106);
      for (final entry in partialHashes.entries) {
        expect(entry.value, originalHashes[entry.key]);
      }
      await tap(find.text('关闭').last);
      await until(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'trash reload after partial result',
      );
      final partialLabel = find.text('已有 2 张永久删除，恢复仅限剩余 1 张');
      if (partialLabel.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          partialLabel,
          300,
          scrollable: find.descendant(
            of: find.byKey(const Key('pack-trash-list')),
            matching: find.byType(Scrollable),
          ),
          maxScrolls: 30,
        );
      }
      expect(find.text('已有 2 张永久删除，恢复仅限剩余 1 张'), findsOneWidget);
      await tap(find.text('查看原永久删除结果'));
      await until(
        () => find.text('重试原任务').evaluate().isNotEmpty,
        'original result link',
      );
      await fixture('/__fixture/actions/normal-pack-purge');
      await tap(find.text('重试原任务'));
      await shot('retry-confirm');
      await tap(find.text('确认重试原任务'));
      await until(
        () => find.text('已确认删除 3/3 张').evaluate().isNotEmpty,
        'same task retry',
      );
      await shot('finished');
      final finalHashes =
          (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes']
              as Map;
      expect(finalHashes.length, 105);
      for (final entry in finalHashes.entries) {
        expect(entry.value, originalHashes[entry.key]);
      }
      expect(
        finalHashes.keys
            .where((v) => (v as String).endsWith('notes.txt'))
            .length,
        27,
      );
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace
            .where(
              (r) =>
                  r['method'] == 'POST' &&
                  r['path'] == '/api/v1/pack-trash/permanent',
            )
            .length,
        1,
      );
      expect(
        trace
            .where(
              (r) =>
                  r['method'] == 'POST' &&
                  r['path'] == '/api/v1/pack-purge-plans',
            )
            .length,
        2,
      );
      expect(
        trace
            .where(
              (r) =>
                  r['method'] == 'POST' &&
                  (r['path'] as String).endsWith('/retry'),
            )
            .length,
        1,
      );
      expect(await repo.createPackFiles().pending(), isEmpty);
      expect(await repo.api.json('GET', '/api/v1/trash'), originalVideoTrash);
      expect(
        trace.where(
          (r) =>
              r['method'] == 'POST' && r['path'] == '/api/v1/trash/permanent',
        ),
        isEmpty,
      );
      debugPrint(
        'PURGE_MANAGEMENT_VERIFIED:108 source files, cancelled video and pack confirmation, exact images, one physical POST, one original retry, 105 preserved files including 27 attachments',
      );
    },
  );
}
