import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'server_reader_image_error_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'visible last image action belongs to clicked image, not viewport top',
    (t) async {
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8764);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect(
        'http://10.0.2.2',
        8764,
        'reader-image-errors-owned-only',
      );
      final root = repo.snapshot.roots.single;
      await repo.saveRoot(
        MediaRoot(root.id, root.name, root.path, kind: MediaKind.pack),
      );
      await repo.refresh();
      final packs = await repo.loadPacks(PackQuery(), limit: 24);
      final failed = packs.items.singleWhere((v) => v.name == '异常图包 A');
      final good = packs.items.singleWhere((v) => v.name == '正常图包 B');
      final manifest = await repo.api.json(
        'GET',
        '/api/v1/packs/${failed.id}/pages',
        query: {'v': '${failed.contentVersion}'},
      );
      final pages = (manifest['items'] as List).cast<Map>();
      expect(pages.length, 3);
      final previousId = pages[1]['id'] as String,
          lastId = pages[2]['id'] as String;
      final armed = await control(
        '/arm/missing?pack_id=${failed.id}&last_only=true',
        post: true,
      );
      expect(armed['page_ids'], [lastId]);
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      Future<void> until(bool Function() done, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 40));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Visible skip timeout: $label');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        await until(() => target.evaluate().length == 1, 'one target');
        if (target.hitTestable().evaluate().isEmpty) {
          await Scrollable.ensureVisible(
            t.element(target),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
        await until(
          () => target.hitTestable().evaluate().length == 1,
          'target visible',
        );
        await t.tap(target.hitTestable());
        await t.pump(const Duration(milliseconds: 350));
      }

      Future<void> capture(String name) async {
        await control('/checkpoint/$name', post: true);
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Missing host screenshot: $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      Future<Map<String, dynamic>> progress() async =>
          Map<String, dynamic>.from(
            (await repo.api.json(
                  'GET',
                  '/api/v1/packs/${failed.id}',
                ))['progress']
                as Map,
          );
      await tap(find.byKey(const Key('kind-pack')));
      await tap(find.byKey(Key('pack-tile-${failed.id}')));
      await until(
        () => reader().session.opened && !reader().session.busy,
        'first decoded image',
      );
      await tap(find.byTooltip('阅读设置'));
      await tap(find.text('纵向拼接'));
      await until(
        () =>
            reader().session.preferences.mode == ReaderMode.vertical &&
            !reader().session.busy,
        'vertical mode',
      );
      await tap(find.text('继续阅读'));
      await tap(find.byTooltip('下一张'));
      await until(
        () => reader().session.index == 1 && reader().session.offsetRatio < .05,
        'previous page top',
      );
      final skip = find.byKey(Key('reader-image-skip-$lastId'));
      final list = find.byKey(const Key('reader-vertical'));
      for (var i = 0; i < 28; i++) {
        if (reader().session.index == 1 &&
            reader().session.offsetRatio > .7 &&
            skip.hitTestable().evaluate().length == 1) {
          break;
        }
        expect(
          reader().session.index,
          1,
          reason: 'Never scroll the last image to the top',
        );
        await t.drag(list, const Offset(0, -45));
        await t.pump(const Duration(milliseconds: 180));
      }
      expect(reader().session.index, 1);
      expect(reader().session.offsetRatio, greaterThan(.7));
      expect(skip.hitTestable(), findsOneWidget);
      await until(
        () =>
            !reader().session.unsaved &&
            !reader().session.hasPending &&
            !reader().session.busy,
        'saved previous image',
      );
      final before = await progress();
      expect(before['page_id'], previousId);
      expect(before['completed'], isFalse);
      final viewportIndex = reader().session.index,
          ratio = reader().session.offsetRatio;
      await capture('visible-last-before');
      // This action is already visible. Do not reveal or change the scroll here.
      expect(reader().session.index, viewportIndex);
      await t.tap(skip.hitTestable());
      await until(
        () => find.text('跳过这一张').evaluate().isEmpty,
        'clicked last image reaches end',
      );
      expect(reader().session.index, 2);
      await t.pump(const Duration(seconds: 1));
      final after = await progress();
      expect(after, before);
      expect(reader().session.range!.pack!.id, failed.id);
      await capture('visible-last-end');
      await tap(find.text('返回最后一张'));
      await until(
        () => skip.hitTestable().evaluate().length == 1,
        'original failed last image',
      );
      expect(reader().session.index, 2);
      expect(await progress(), before);
      await capture('visible-last-returned');
      await tap(find.byTooltip('返回来源'));
      await until(
        () => find.byType(PackReaderPage).evaluate().isEmpty,
        'source',
      );
      await tap(find.byKey(Key('pack-tile-${failed.id}')));
      await until(
        () =>
            reader().session.opened &&
            !reader().session.busy &&
            skip.hitTestable().evaluate().length == 1,
        'resume previous real image',
      );
      expect(reader().session.index, 1);
      expect(reader().session.offsetRatio, greaterThan(.7));
      expect((await progress())['page_id'], previousId);
      await capture('visible-last-resumed');
      await t.tap(skip.hitTestable());
      await until(
        () => find.text('跳过这一张').evaluate().isEmpty,
        'second explicit end',
      );
      await tap(find.text('阅读下一包'));
      await until(
        () =>
            reader().session.range!.pack!.id == good.id &&
            reader().session.opened &&
            !reader().session.busy,
        'explicit normal next pack',
      );
      final finalProgress = await progress();
      expect(finalProgress['page_id'], previousId);
      expect(finalProgress['completed'], isFalse);
      await capture('visible-last-next-pack');
      debugPrint(
        'READER_VISIBLE_SKIP_VERIFIED:${jsonEncode({'failed_pack': failed.id, 'good_pack': good.id, 'previous_page': previousId, 'failed_page': lastId, 'viewport_index': viewportIndex, 'clicked_index': 2, 'ratio': ratio, 'before': before, 'after': after, 'final_progress': finalProgress})}',
      );
      expect(t.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
