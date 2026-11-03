import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/features/packs/pack_file_action.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/main.dart';

import 'media_workspace_widget_test.dart' show frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_cleanup_widget_test.dart' show CleanupLibrary;

class BulkLibrary extends CleanupLibrary {
  BulkLibrary({this.directoryDelete = false});
  final bool directoryDelete;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    if (directoryDelete) 'pack_directory_delete',
  ]);
  final submitted = <Set<String>>[];
  @override
  Future<Set<String>> selectPackIds(PackQuery query) async =>
      (await loadPacks(query, limit: 1000)).items.map((p) => p.id).toSet();
  @override
  PackFiles createPackFiles() {
    final base = super.createPackFiles();
    return PackFiles(
      journal: base.journal,
      scope: base.scope,
      isCurrent: base.isCurrent,
      call: (method, path, {body}) async {
        if (method == 'POST' && path == '/api/v1/packs/trash') {
          submitted.add((body!['pack_ids'] as List).cast<String>().toSet());
        }
        return base.call(method, path, body: body);
      },
    );
  }
}

void main() {
  testWidgets(
    'current service recycles and undoes selected packs without an operation sheet',
    (t) async {
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final repo = BulkLibrary(directoryDelete: true);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        VideoPlayerPlatform.instance = previous;
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      Future<void> tap(Finder finder) async {
        await t.ensureVisible(finder);
        await t.tap(finder);
        await frames(t);
      }

      await tap(find.byKey(const Key('kind-pack')));
      final state = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      await tap(find.byKey(const Key('pack-multi-select')));
      await tap(find.byKey(const Key('pack-tile-p0')));
      await tap(find.byKey(const Key('pack-delete-selected')));
      expect(find.byType(PackFileAction), findsNothing);
      expect(find.textContaining('待核对'), findsNothing);
      expect(repo.submitted.single, {'p0'});
      expect(state.data.total, 26);
      expect(state.selected, isEmpty);
      await tap(find.text('撤销'));
      expect(find.byType(PackFileAction), findsNothing);
      expect(state.data.total, 27);
      expect(await repo.createPackFiles().pending(), isEmpty);
      expect(t.takeException(), isNull);
    },
  );

  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 2.0),
  ]) {
    testWidgets(
      'explicit multi-select, long press and exact batch cleanup $sample',
      (t) async {
        final previous = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = UnreadyVideo();
        final repo = BulkLibrary();
        t.view.physicalSize = sample.$1;
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = sample.$2;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          repo.dispose();
          VideoPlayerPlatform.instance = previous;
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await repo.initialize();
        await t.pumpWidget(VideoViewerApp(repository: repo));
        Future<void> tap(Finder f) async {
          if (f.hitTestable().evaluate().isEmpty) {
            await Scrollable.ensureVisible(t.element(f), alignment: .5);
            await t.pump();
          }
          await t.tap(f);
          await frames(t);
          expect(t.takeException(), isNull);
        }

        await frames(t);
        await tap(find.byKey(const Key('kind-pack')));
        final state = t.state<PackCatalogPageState>(
          find.byType(PackCatalogPage),
        );
        await tap(find.byKey(const Key('pack-multi-select')));
        expect(state.selecting, isTrue);
        await tap(find.byKey(const Key('pack-tile-p0')));
        expect(state.selected, {'p0'});
        await tap(find.byKey(const Key('pack-multi-select')));
        expect(state.selected, isEmpty);
        final tile = t.getRect(find.byKey(const Key('pack-tile-p0')));
        final viewport = t.getRect(find.byKey(const Key('pack-grid')));
        expect(tile.intersect(viewport).height, greaterThan(24));
        await t.longPressAt(tile.intersect(viewport).center);
        await frames(t);
        expect(state.selecting, isTrue);
        expect(state.selected, {'p0'});
        await tap(find.byKey(const Key('pack-tile-p1')));
        expect(state.selected, {'p0', 'p1'});
        expect(find.text('已选 2'), findsOneWidget);
        await tap(find.byKey(const Key('pack-delete-selected')));
        expect(find.text('已选择 2 个图包。保留源文件，可在回收站恢复。'), findsOneWidget);
        await tap(find.text('取消'));
        expect(repo.submitted, isEmpty);
        expect(state.selected, {'p0', 'p1'});
        await tap(find.byKey(const Key('pack-delete-selected')));
        await tap(find.widgetWithText(FilledButton, '移入回收站'));
        expect(repo.submitted, [
          {'p0', 'p1'},
        ]);
        expect(repo.packLinks.containsKey('p0'), isFalse);
        expect(repo.packLinks.containsKey('p1'), isFalse);
        expect(repo.packLinks['p2'], {'自然', '收藏'});
        expect(state.data.total, 25);
        expect(state.selected, isEmpty);
        expect(await repo.createPackFiles().pending(), isEmpty);
      },
    );
  }

  testWidgets(
    'selection spans pages and an uncertain batch is queried without another POST',
    (t) async {
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final repo = BulkLibrary();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        VideoPlayerPlatform.instance = previous;
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.tap(f);
        await frames(t);
      }

      await tap(find.byKey(const Key('kind-pack')));
      final state = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      await t.longPress(find.byKey(const Key('pack-tile-p0')));
      await frames(t);
      await t.scrollUntilVisible(
        find.byKey(const Key('pack-tile-p24')),
        500,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('pack-grid')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 30,
      );
      await frames(t);
      await tap(find.byKey(const Key('pack-tile-p24')));
      expect(state.selected, {'p0', 'p24'});
      repo.lose = true;
      await tap(find.byKey(const Key('pack-delete-selected')));
      await tap(find.widgetWithText(FilledButton, '移入回收站'));
      expect(repo.submitted, [
        {'p0', 'p24'},
      ]);
      expect((await repo.createPackFiles().pending()), hasLength(1));
      await tap(find.widgetWithText(FilledButton, '查询原结果'));
      expect(repo.submitted, hasLength(1));
      expect(state.data.total, 25);
      expect(state.selected, isEmpty);
      expect(repo.packLinks.containsKey('p1'), isTrue);
      expect(await repo.createPackFiles().pending(), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'select all matched packs can be recycled and the empty selection can still finish',
    (t) async {
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final repo = BulkLibrary();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        VideoPlayerPlatform.instance = previous;
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await frames(t);
      Future<void> tap(Finder f) async {
        await t.tap(f);
        await frames(t);
      }

      await tap(find.byKey(const Key('kind-pack')));
      await tap(find.byKey(const Key('pack-multi-select')));
      await tap(find.byKey(const Key('pack-select-all')));
      final state = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      expect(state.selected, hasLength(27));
      await tap(find.byKey(const Key('pack-delete-selected')));
      await tap(find.widgetWithText(FilledButton, '移入回收站'));
      expect(repo.submitted.single, hasLength(27));
      expect(state.data.total, 0);
      expect(state.selected, isEmpty);
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('pack-multi-select')))
            .onPressed,
        isNotNull,
      );
      await tap(find.byKey(const Key('pack-multi-select')));
      expect(state.selecting, isFalse);
      expect(find.byKey(const Key('pack-search')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
