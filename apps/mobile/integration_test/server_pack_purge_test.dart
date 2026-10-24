import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF6 exact review, cancel, lost physical reply, partial result and original retry',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      await fixture('/__fixture/actions/purge-pack-attachments');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '永久删除图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
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
      await t.pumpWidget(VideoViewerApp(repository: repo));
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

      Future<void> tap(Finder target) async {
        await until(() => target.evaluate().isNotEmpty, 'target exists');
        await t.ensureVisible(target);
        await until(
          () =>
              target.hitTestable().evaluate().isNotEmpty &&
              ModalRoute.of(t.element(target))?.animation?.status ==
                  AnimationStatus.completed,
          'stable target',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 180));
      }

      Future<void> shot(String name) async {
        await fixture('/__fixture/checkpoint/purge-$name');
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }

      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('回收站'));
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
      await tap(find.text(first.name).last);
      await until(
        () => find.text('10.jpg').evaluate().isNotEmpty,
        'exact image list',
      );
      await shot('files');
      await tap(find.byTooltip('关闭面板').last);
      await tap(find.byTooltip('关闭面板').last);
      await tap(find.text('取消').last);
      expect(
        (await fixture('/__fixture/actions/pack-trash-hashes'))['hashes'],
        originalHashes,
      );
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
      await tap(find.byKey(const Key('pack-trash-pending')));
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
      expect(find.text('已有 2 张永久删除，恢复仅限剩余 1 张'), findsOneWidget);
      await tap(find.text('查看原永久删除结果'));
      await until(
        () => find.text('重试原任务').evaluate().isNotEmpty,
        'original result link',
      );
      await fixture('/__fixture/actions/normal-pack-purge');
      await tap(find.text('重试原任务'));
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
    },
  );
}
