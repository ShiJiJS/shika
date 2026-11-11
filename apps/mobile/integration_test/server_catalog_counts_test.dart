import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';

import 'native_workspace_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'authoritative type totals survive scopes, real trash/restore and failed reads',
    (t) async {
      final previousError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('CATALOG_COUNTS_ERROR:$details');
        previousError?.call(details);
      };
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
        FlutterError.onError = previousError;
      });
      await repo.connect(
        'http://10.0.2.2',
        8768,
        'client-ui-owned-only',
      );
      final initial = repo.catalogCounts.value;
      expect(initial, const MediaCatalogCounts(2, 4));
      final all = await repo.loadPacks(PackQuery());
      final pack = all.items.singleWhere((p) => p.name.contains('034'));
      Future<Map<String, dynamic>> progress() async =>
          Map<String, dynamic>.from(
            (await repo.api.json('GET', '/api/v1/packs/${pack.id}'))['progress']
                as Map,
          );
      final before = await progress();
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      Future<void> until(bool Function() condition, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            final page = find.byType(PackCatalogPage);
            if (page.evaluate().length == 1) {
              final state = t.state<PackCatalogPageState>(page);
              debugPrint(
                'COUNTS_TIMEOUT_STATE:${jsonEncode({'query': state.entry.query.toJson(), 'search': state.search.text, 'active': state.widget.active, 'loading': state.data.loading, 'total': state.data.total, 'error': state.data.error, 'generation': state.generation, 'continuationLoading': state.continuationLoading})}',
              );
            }
            fail('Catalog counts timeout: $reason');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder finder) async {
        await until(() => finder.evaluate().length == 1, 'one target $finder');
        if (finder.hitTestable().evaluate().isEmpty) {
          await t.ensureVisible(finder);
        }
        await until(
          () => finder.hitTestable().evaluate().length == 1,
          'visible $finder',
        );
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 350));
      }

      PackCatalogPageState catalog() => t.state(find.byType(PackCatalogPage));
      void shown(int videos, int packs) {
        expect(
          t.widget<Text>(find.byKey(const Key('catalog-count-video'))).data,
          '$videos',
        );
        expect(
          t.widget<Text>(find.byKey(const Key('catalog-count-pack'))).data,
          '$packs',
        );
      }

      Future<void> decodedCovers() => until(
        () =>
            find
                .byType(RawImage)
                .evaluate()
                .where((e) => (e.widget as RawImage).image != null)
                .length >=
            2,
        'two decoded visible covers',
      );

      Future<void> capture(String name) async {
        await t.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        final media = MediaQuery.of(
          t.element(find.byKey(const Key('app-shell'))),
        );
        List<double> rectangle(Rect r) => [r.left, r.top, r.width, r.height];
        final texts = <Map<String, dynamic>>[];
        for (final element in find.byType(Text).evaluate()) {
          final widget = element.widget as Text, box = element.renderObject;
          if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
          final pos = box.localToGlobal(Offset.zero);
          if (pos.dy < 0 || pos.dy >= media.size.height) continue;
          texts.add({
            'text': widget.data ?? widget.textSpan?.toPlainText(),
            'rect': rectangle(pos & box.size),
            'fontSize': widget.style?.fontSize,
          });
        }
        final keys = <String, List<double>>{};
        for (final key in [
          'app-navigation',
          'catalog-count-video',
          'catalog-count-pack',
          'pack-search',
          'video-search',
          'pack-count',
        ]) {
          final finder = find.byKey(Key(key));
          if (finder.evaluate().length == 1) {
            keys[key] = rectangle(t.getRect(finder));
          }
        }
        debugPrint(
          'WORKSPACE_METRICS:${jsonEncode({
            'state': name,
            'size': [media.size.width, media.size.height],
            'dpr': media.devicePixelRatio,
            'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
            'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
            'textScale': media.textScaler.scale(14) / 14,
            'keys': keys,
            'texts': texts,
            'counts': repo.catalogCounts.value == null ? null : {'video': repo.catalogCounts.value!.videos, 'pack': repo.catalogCounts.value!.packs},
          })}',
        );
        await control('/checkpoint/$name', post: true);
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Host did not capture $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      await until(
        () =>
            find.byKey(const Key('catalog-count-video')).evaluate().length == 1,
        'initial library',
      );
      shown(2, 4);
      await decodedCovers();
      await capture('counts-home');
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () => catalog().initialized && !catalog().data.loading,
        'pack catalog',
      );
      shown(2, 4);
      await decodedCovers();
      await capture('counts-packs');
      await t.enterText(
        find.byKey(const Key('pack-search')),
        'no-pack-matches',
      );
      await until(
        () => !catalog().data.loading && catalog().data.total == 0,
        'empty filtered result',
      );
      shown(2, 4);
      await capture('counts-filter');
      await tap(find.byKey(const Key('nav-tags')));
      expect(find.byKey(const Key('catalog-count-pack')), findsNothing);
      await capture('counts-tags');
      await tap(find.byKey(const Key('nav-recent')));
      expect(find.byKey(const Key('catalog-count-video')), findsNothing);
      await capture('counts-recent');
      await tap(find.byKey(const Key('nav-library')));
      expect(catalog().entry.query.search, 'no-pack-matches');
      // Use the visible scope-clear action after returning from another tab;
      // do not inject an empty platform editing value into a closing IME.
      await tap(find.text('清除'));
      await until(
        () => !catalog().data.loading && catalog().data.total == 4,
        'clear scope',
      );
      final files = repo.createPackFiles();
      final trash = PackFileCommand.trash(packFileRequestId(), [pack.id]);
      final trashed = await files.resolve(trash, submit: true);
      expect(trashed?.result?.succeeded, 1);
      await files.acknowledge(trash);
      repo.packFilesChanged();
      await until(
        () =>
            repo.catalogCounts.value == const MediaCatalogCounts(2, 3) &&
            !catalog().data.loading &&
            catalog().data.total == 3,
        'real logical trash updates totals',
      );
      shown(2, 3);
      await capture('counts-trash');
      final trashCatalog = repo.createPackTrash();
      final trashRow = (await trashCatalog.page()).items.single;
      trashCatalog.dispose();
      final restore = PackFileCommand.restore(packFileRequestId(), [
        trashRow.id,
      ]);
      final restored = await files.resolve(restore, submit: true);
      expect(restored?.result?.succeeded, 1);
      await files.acknowledge(restore);
      repo.packFilesChanged();
      await until(
        () =>
            repo.catalogCounts.value == const MediaCatalogCounts(2, 4) &&
            !catalog().data.loading &&
            catalog().data.total == 4,
        'real restore updates totals',
      );
      shown(2, 4);
      await capture('counts-restore');
      await control('/catalog-counts-failure/on', post: true);
      await repo.refreshCatalogCounts();
      expect(repo.catalogCounts.value, isNull);
      expect(repo.snapshot.connected, isTrue);
      expect(catalog().data.total, 4);
      await capture('counts-error');
      await control('/catalog-counts-failure/off', post: true);
      await tap(find.byKey(const Key('catalog-count-pack')));
      await until(
        () => repo.catalogCounts.value == const MediaCatalogCounts(2, 4),
        'badge retry',
      );
      shown(2, 4);
      await capture('counts-retry');
      expect(await progress(), before);
      expect(
        (await repo.api.json(
          'GET',
          '/api/v1/packs',
          query: {'source': 'recent', 'sort': 'recent'},
        ))['total'],
        0,
      );
      debugPrint(
        'CATALOG_COUNTS_VERIFIED:${jsonEncode({
          'pack': pack.id,
          'before_progress': before,
          'after_progress': await progress(),
          'trash_task': trashed!.id,
          'restore_task': restored!.id,
          'transitions': [
            [2, 4],
            [2, 3],
            [2, 4],
          ],
          'recent': 0,
        })}',
      );
      debugPrint('WORKSPACE_VERIFIED');
      expect(t.takeException(), isNull);
    },
  );
}
