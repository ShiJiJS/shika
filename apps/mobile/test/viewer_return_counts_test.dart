import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/main.dart';

import 'media_workspace_widget_test.dart' show frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

class ViewerCountsLibrary extends AssetReadingLibrary {
  ViewerCountsLibrary() {
    catalogCounts.value = const MediaCatalogCounts(270, 730);
  }
  MediaCatalogCounts next = const MediaCatalogCounts(271, 731);
  Future<void>? delayed;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    'media_catalog_counts',
  ]);
  @override
  Future<void> refreshCatalogCounts() async {
    if (delayed != null) {
      await delayed;
    }
    catalogCounts.value = next;
  }
}

void main() {
  for (final pack in [false, true]) {
    for (final delayed in [false, true]) {
      testWidgets(
        'return from ${pack ? 'reader' : 'preview'} refreshes inventory; delayed=$delayed',
        (t) async {
          final original = VideoPlayerPlatform.instance;
          VideoPlayerPlatform.instance = UnreadyVideo();
          final repo = ViewerCountsLibrary();
          addTearDown(() {
            repo.dispose();
            VideoPlayerPlatform.instance = original;
          });
          await repo.initialize();
          await t.pumpWidget(
            VideoViewerApp(repository: repo, initializeRepository: false),
          );
          await frames(t);
          String total(String kind) =>
              t.widget<Text>(find.byKey(Key('catalog-count-$kind'))).data!;
          expect(total('video'), '270');
          expect(total('pack'), '730');
          if (pack) {
            await t.tap(find.byKey(const Key('kind-pack')));
            await frames(t);
            await t.tap(find.byKey(const Key('pack-tile-p1')));
          } else {
            await t.tap(find.text('预览此范围'));
          }
          await frames(t);
          final gate = delayed ? Completer<void>() : null;
          repo.delayed = gate?.future;
          await t.tap(
            pack
                ? find.byTooltip('返回来源')
                : find.byKey(const Key('preview-back')),
          );
          await frames(t);
          expect(
            find.byKey(Key(pack ? 'pack-grid' : 'video-grid')),
            findsOneWidget,
          );
          // An independent count read must not prevent the source from returning.
          if (gate != null) {
            expect(total('video'), '270');
            gate.complete();
            await frames(t);
          }
          expect(total('video'), '271');
          expect(total('pack'), '731');
          await t.pumpWidget(const SizedBox());
          await frames(t);
        },
      );
    }
  }
}
