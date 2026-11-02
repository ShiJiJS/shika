import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class SelectableWorkspace extends WorkspaceLibrary {
  @override
  Future<Set<String>> selectPackIds(PackQuery query) async =>
      (await loadPacks(query, limit: 100)).items.map((p) => p.id).toSet();
}

void main() {
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
        await t.pumpWidget(VideoViewerApp(repository: repo));
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
        await tap(find.text('追加标签'));
        expect(find.byType(InputChip), findsNothing);
        await tap(
          find.ancestor(
            of: find.text('收藏'),
            matching: find.bySubtype<FilterChip>(),
          ),
        );
        await tap(find.text('追加所选标签'));
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
