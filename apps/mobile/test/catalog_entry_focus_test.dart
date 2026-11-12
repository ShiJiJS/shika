import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

void main() {
  testWidgets(
    'leaving video search for preview does not restore input focus on return',
    (t) async {
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final repo = WorkspaceLibrary();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await frames(t);
        repo.dispose();
        VideoPlayerPlatform.instance = previous;
      });
      await repo.initialize();
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      final search = find.byKey(const Key('video-search'));
      await t.enterText(search, '花间微风');
      await frames(t);
      await t.showKeyboard(search);
      final editable = t.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await t.tap(find.byKey(const Key('video-quick-cleanup')));
      await frames(t);
      expect(find.byKey(const Key('preview-back')), findsOneWidget);
      await t.tap(find.byKey(const Key('preview-back')));
      await frames(t);
      expect(editable.focusNode.hasFocus, isFalse);
      expect(t.testTextInput.isVisible, isFalse);
      expect(t.widget<TextField>(search).controller!.text, '花间微风');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving pack search for reading does not restore input focus on return',
    (t) async {
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final repo = AssetReadingLibrary();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await frames(t);
        repo.dispose();
        VideoPlayerPlatform.instance = previous;
      });
      await repo.initialize();
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      await t.tap(find.byKey(const Key('kind-pack')));
      await frames(t);
      final search = find.byKey(const Key('pack-search'));
      await t.enterText(search, '春日');
      await frames(t);
      await t.showKeyboard(search);
      final editable = t.widget<EditableText>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      final page = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      final scroll = page.scroll.offset;
      await t.tap(find.byKey(const Key('pack-tile-p1')));
      await frames(t);
      expect(find.byType(PackReaderPage), findsOneWidget);
      await t.tap(find.byTooltip('返回来源'));
      await frames(t);
      expect(find.byType(PackReaderPage), findsNothing);
      expect(editable.focusNode.hasFocus, isFalse);
      expect(t.testTextInput.isVisible, isFalse);
      expect(t.widget<TextField>(search).controller!.text, '春日');
      expect(page.scroll.offset, closeTo(scroll, 1));
      expect(
        find.byKey(const Key('pack-tile-p1')).hitTestable(),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('pack-tile-p1')));
      await frames(t);
      expect(find.byType(PackReaderPage), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
