import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/library/video_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class SelectableWorkspace extends WorkspaceLibrary {
  @override
  Future<Set<String>> selectPackIds(PackQuery query) async =>
      (await loadPacks(query, limit: 100)).items.map((p) => p.id).toSet();
}

class TrackingSelectionWorkspace extends SelectableWorkspace {
  final writes =
      <
        ({
          bool pack,
          Set<String> ids,
          Set<String> tags,
          bool replace,
          bool remove,
        })
      >[];
  @override
  Future<void> setVideoTags(
    Set<String> ids,
    Set<String> tags, {
    bool remove = false,
    bool replace = false,
  }) async {
    writes.add((
      pack: false,
      ids: {...ids},
      tags: {...tags},
      replace: replace,
      remove: remove,
    ));
    await super.setVideoTags(ids, tags, remove: remove, replace: replace);
  }

  @override
  Future<void> setPackTags(
    Set<String> ids,
    Set<String> tags, {
    bool replace = false,
  }) async {
    writes.add((
      pack: true,
      ids: {...ids},
      tags: {...tags},
      replace: replace,
      remove: false,
    ));
    await super.setPackTags(ids, tags, replace: replace);
  }
}

void main() {
  for (final kind in MediaKind.values) {
    for (final sample in [
      (const Size(390, 844), 1.0),
      (const Size(360, 740), 2.0),
    ]) {
      testWidgets(
        'long press selects ${kind.name} and batch tags append only to the selected items $sample',
        (t) async {
          final previous = VideoPlayerPlatform.instance;
          VideoPlayerPlatform.instance = UnreadyVideo();
          final repo = TrackingSelectionWorkspace();
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
          const added = '批量新增标签';
          final pack = kind == MediaKind.pack;
          if (pack) {
            repo.packNames[added] = added;
          } else {
            await t.runAsync(() => repo.editTag(name: added));
          }
          final beforeVideos = {
            for (final v in repo.snapshot.videos) v.id: {...v.tags},
          };
          final beforePacks = {
            for (final e in repo.packLinks.entries) e.key: {...e.value},
          };
          await t.pumpWidget(ShikaApp(repository: repo));
          await frames(t);
          Future<void> tap(Finder f) async {
            await t.ensureVisible(f);
            await t.pump();
            await t.tap(f);
            await frames(t);
            expect(t.takeException(), isNull);
          }

          final videoState = t.state<VideoCatalogPageState>(
            find.byType(VideoCatalogPage),
          );
          if (pack) await tap(find.byKey(const Key('kind-pack')));
          final packState = pack
              ? t.state<PackCatalogPageState>(find.byType(PackCatalogPage))
              : null;
          final ids = pack
              ? packState!.data.items.take(2).map((v) => v.id).toList()
              : videoState.data.items.take(2).map((v) => v.id).toList();
          final tile = find.byKey(
            Key('${pack ? 'pack-tile' : 'tile'}-${ids.first}'),
          );
          final viewport = find.byKey(Key(pack ? 'pack-grid' : 'video-grid'));
          await t.longPressAt(
            t.getRect(tile).intersect(t.getRect(viewport)).center,
          );
          await frames(t);
          expect(pack ? packState!.selected : videoState.selected, {ids.first});
          expect(videoState.viewing, isFalse);
          await tap(
            find.byKey(Key('${pack ? 'pack-tile' : 'tile'}-${ids.last}')),
          );
          expect(find.text('已选 2'), findsOneWidget);
          await tap(
            find.byKey(
              Key(pack ? 'pack-add-selected-tags' : 'video-add-selected-tags'),
            ),
          );
          await tap(
            find.ancestor(
              of: find.text(added),
              matching: find.bySubtype<FilterChip>(),
            ),
          );
          await tap(find.byKey(const Key('tag-assignment-save')));
          final write = repo.writes.single;
          expect(write.ids, ids.toSet());
          expect(write.tags, {added});
          expect(write.pack, pack);
          expect(write.replace, isFalse);
          expect(write.remove, isFalse);
          for (final v in repo.snapshot.videos) {
            expect(v.tags, {
              ...beforeVideos[v.id]!,
              if (!pack && ids.contains(v.id)) added,
            });
          }
          for (final e in repo.packLinks.entries) {
            expect(e.value, {
              ...beforePacks[e.key]!,
              if (pack && ids.contains(e.key)) added,
            });
          }
          if (!pack) {
            videoState.toggleSelection();
            await frames(t);
            expect(videoState.selected, isEmpty);
            await t.longPressAt(
              t.getRect(tile).intersect(t.getRect(viewport)).center,
            );
            await frames(t);
            expect(videoState.selected, {ids.first});
            expect(videoState.viewing, isFalse);
          }
        },
      );
    }
  }

  testWidgets(
    'a single remaining batch choice appends and retains its original pack tags',
    (t) async {
      final original = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final repo = SelectableWorkspace();
      await repo.initialize();
      try {
        Future<void> tap(Finder f) async {
          await t.tap(f);
          await frames(t);
        }

        t.view.physicalSize = const Size(360, 740);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        t.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(ShikaApp(repository: repo));
        await frames(t);
        await tap(find.byKey(const Key('kind-pack')));
        await tap(find.byTooltip('更多'));
        await tap(find.text('多选内容'));
        await tap(find.byKey(const Key('pack-select-all')));
        final state = t.state<PackCatalogPageState>(
          find.byType(PackCatalogPage),
        );
        expect(state.selected, {'p1', 'p2'});
        await tap(find.byKey(const Key('pack-tile-p2')));
        expect(state.selected, {'p1'});
        await tap(find.text('添加标签'));
        expect(find.byType(InputChip), findsNothing);
        await tap(
          find.ancestor(
            of: find.text('收藏'),
            matching: find.bySubtype<FilterChip>(),
          ),
        );
        await tap(find.text('添加所选标签'));
        expect(repo.packLinks['p1'], {'自然', '收藏'});
        expect(repo.packLinks['p2'], {'收藏'});
        expect(state.selected, {'p1'});
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      } finally {
        repo.dispose();
        VideoPlayerPlatform.instance = original;
      }
    },
  );
}
