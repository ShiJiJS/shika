import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/features/packs/reader_images.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF6 quick cleanup receipt, fixed tag range, exact undo and ordinary reader return',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '整包整理图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final all = await repo.loadPacks(PackQuery(), limit: 100);
      final first = all.items.first,
          second = all.items[1],
          last = all.items[24];
      final tag = await repo.createPackTag('整理范围');
      await repo.setPackTags(all.items.take(25).map((p) => p.id).toSet(), {
        tag.id,
      });
      await t.pumpWidget(VideoViewerApp(repository: repo));
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      PackCatalogPageState catalog() => t.state(find.byType(PackCatalogPage));
      Future<void> until(bool Function() done, String why) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint('CLEANUP_TIMEOUT $why');
            if (find.byType(PackReaderPage).evaluate().isNotEmpty) {
              debugPrint(
                'CLEANUP_STATE ${reader().session.cleanupError} / ${reader().session.error}',
              );
            }
            for (final image in t.widgetList<ReaderImage>(
              find.byType(ReaderImage),
            )) {
              debugPrint(
                'CLEANUP_IMAGE page=${image.page.id} readable=${image.page.readable} error=${image.page.error} source=${image.page.image?.location} viewport=${image.viewport}',
              );
            }
            for (final image in t.widgetList<Image>(find.byType(Image))) {
              image.image
                  .resolve(ImageConfiguration.empty)
                  .addListener(
                    ImageStreamListener(
                      (_, _) {},
                      onError: (Object error, StackTrace? stack) =>
                          debugPrint('CLEANUP_IMAGE_FAILURE $error'),
                    ),
                  );
            }
            await t.pump(const Duration(milliseconds: 100));
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $why');
          }
          await t.pump(const Duration(milliseconds: 60));
        }
        await t.pump(const Duration(milliseconds: 150));
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        await until(() => target.evaluate().isNotEmpty, 'target exists');
        await t.ensureVisible(target);
        // A hit-test alone can succeed during route entry while the control is
        // still moving. Wait for the actual route animation as well.
        await until(
          () =>
              target.hitTestable().evaluate().isNotEmpty &&
              ModalRoute.of(t.element(target))?.animation?.status ==
                  AnimationStatus.completed,
          'stable hit target',
        );
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 100));
      }

      Future<void> shot(String name) async {
        await until(
          () => find.byType(PopupMenuItem<String>).evaluate().isEmpty,
          'menu exit before screenshot',
        );
        await fixture('/__fixture/checkpoint/cleanup-$name');
        await t.pump(const Duration(seconds: 1));
        expect(t.takeException(), isNull);
      }

      Future<void> opened(String id) => until(
        () =>
            find.byType(PackReaderPage).evaluate().isNotEmpty &&
            reader().session.cursor?.packId == id &&
            reader().session.opened &&
            !reader().session.inputBlocked,
        'decoded and confirmed $id',
      );
      Future<Map> progress(String id) async =>
          (await repo.api.json('GET', '/api/v1/packs/$id'))['progress'] as Map;

      await tap(find.byKey(const Key('nav-tags')));
      await tap(find.byKey(const Key('kind-pack')));
      await tap(find.byKey(Key('pack-tag-${tag.id}')));
      await tap(find.byKey(const Key('tag-view-results')));
      await until(
        () =>
            find.byKey(const Key('pack-search')).evaluate().isNotEmpty &&
            catalog().data.total == 25 &&
            !catalog().data.loading,
        'full tag scope',
      );
      final query = catalog().entry.queryKey;
      await tap(find.byKey(const Key('pack-quick-cleanup')));
      await opened(first.id);
      final identity = reader().session.range!.id;
      expect(reader().session.range!.candidateCount, 25);
      expect(reader().session.entry.source, BrowseSource.tags);
      await tap(find.byTooltip('下一张'));
      await until(
        () => reader().session.index == 1 && reader().session.unsaved,
        'second page',
      );
      final pageId = reader().session.currentPage!.id;
      await shot('ready');
      await fixture('/__fixture/actions/lose-file-response');
      await tap(find.byKey(const Key('reader-trash-pack')));
      await until(
        () => reader().session.hasCleanup && !reader().session.cleanupBusy,
        'lost acknowledgement retained',
      );
      expect(reader().session.cursor!.packId, first.id);
      expect(reader().session.cleanupFrozen, isTrue);
      final command = reader().session.cleanupCommand!;
      expect((await progress(first.id))['page_id'], pageId);
      await shot('unknown');
      await tap(find.text('查询原结果'));
      await opened(second.id);
      expect(reader().session.range!.id, identity);
      expect(reader().session.range!.candidateCount, 25);
      final trace = await fixture('/__fixture/trace', method: 'GET');
      expect(
        (trace['items'] as List)
            .where(
              (r) =>
                  r['method'] == 'POST' && r['path'] == '/api/v1/packs/trash',
            )
            .length,
        1,
      );
      expect(
        (trace['items'] as List).any(
          (r) =>
              r['method'] == 'GET' &&
              r['path'] == '/api/v1/pack-file-requests/${command.requestId}',
        ),
        isTrue,
      );
      // Capture after the undo interaction so screenshot latency cannot consume
      // the server's eight-second undo window.
      await tap(find.text('撤销'));
      await opened(first.id);
      expect(reader().session.index, 1);
      expect(reader().session.range!.id, identity);
      await shot('undo');
      const rounds = int.fromEnvironment(
        'PACK_CLEANUP_ROUNDS',
        defaultValue: 1,
      );
      for (var attempt = 1; attempt < rounds; attempt++) {
        final current = all.items[attempt], following = all.items[attempt + 1];
        expect(await reader().session.move(current.id), isTrue);
        await opened(current.id);
        debugPrint('CLEANUP_REPEAT $attempt: ${current.id} -> ${following.id}');
        await fixture('/__fixture/actions/lose-file-response');
        await tap(find.byKey(const Key('reader-trash-pack')));
        await until(
          () => reader().session.hasCleanup && !reader().session.cleanupBusy,
          'repeat lost acknowledgement',
        );
        final pending = reader().session.cleanupCommand!;
        expect(reader().session.cursor!.packId, current.id);
        await tap(find.text('查询原结果'));
        await opened(following.id);
        expect(reader().session.range!.id, identity);
        expect(reader().session.range!.candidateCount, 25);
        final repeatedTrace = await fixture('/__fixture/trace', method: 'GET');
        expect(
          (repeatedTrace['items'] as List).any(
            (row) =>
                row['method'] == 'GET' &&
                row['path'] ==
                    '/api/v1/pack-file-requests/${pending.requestId}',
          ),
          isTrue,
        );
        await tap(find.text('撤销'));
        await opened(current.id);
        expect(reader().session.range!.id, identity);
      }
      if (rounds > 1) {
        expect(await reader().session.move(first.id), isTrue);
        await opened(first.id);
        expect(reader().session.index, 1);
      }
      await tap(find.text('完成'));
      expect(reader().quick, isFalse);
      await tap(find.byTooltip('图包更多'));
      await tap(find.text('整包移入回收站'));
      await tap(find.text('移入回收站'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'normal delete returns source',
      );
      expect(catalog().entry.queryKey, query);
      await tap(find.text('撤销'));
      await opened(first.id);
      expect(reader().quick, isFalse);
      expect(reader().session.index, 1);
      expect(reader().session.range!.id, identity);
      expect(reader().session.entry.source, BrowseSource.tags);
      await shot('resumed');
      // Select the tail within the same immutable range, then use the visible
      // quick cleanup entry and removal action.
      expect(await reader().session.move(last.id), isTrue);
      await opened(last.id);
      await tap(find.byTooltip('图包更多'));
      await tap(find.text('快速整理当前范围'));
      await shot('tail');
      await tap(find.byKey(const Key('reader-trash-pack')));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'tail returns original tag results',
      );
      expect(catalog().entry.queryKey, query);
      expect(catalog().data.total, 24);
      expect(
        (await repo.api.json(
          'GET',
          '/api/v1/pack-sessions/$identity',
        ))['finished'],
        isTrue,
      );
      await shot('return');
    },
  );
}
