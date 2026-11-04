import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class LegacyBackLibrary extends WorkspaceLibrary {
  @override
  bool get supportsFixedPreviews => false;
}

void main() {
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  for (final destination in ['媒体目录', '回收站', '备份与恢复', '操作任务', '服务连接']) {
    testWidgets(
      'new workspace back from $destination never exposes legacy browse',
      (t) async {
        final repo = WorkspaceLibrary();
        await repo.initialize();
        await t.pumpWidget(ShikaApp(repository: repo));
        await frames(t);
        await t.tap(find.byKey(const Key('nav-settings')));
        await frames(t);
        await t.ensureVisible(find.text(destination));
        await t.tap(find.text(destination));
        await frames(t);
        await t.binding.handlePopRoute();
        await frames(t);
        expect(find.byKey(const Key('nav-settings')), findsOneWidget);
        expect(find.byKey(const Key('nav-browse')), findsNothing);
        expect(find.text('设置'), findsNWidgets(2));
        expect(find.byType(MovieStage), findsNothing);
        await t.binding.handlePopRoute();
        await frames(t);
        expect(find.byKey(const Key('video-search')), findsOneWidget);
        expect(find.byKey(const Key('nav-browse')), findsNothing);
        expect(find.byType(MovieStage), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
        repo.dispose();
      },
    );
  }

  testWidgets('old service still returns from settings to legacy browse', (
    t,
  ) async {
    final repo = LegacyBackLibrary();
    await repo.initialize();
    await t.pumpWidget(ShikaApp(repository: repo));
    await frames(t);
    expect(find.byKey(const Key('nav-browse')), findsOneWidget);
    await t.tap(find.byKey(const Key('nav-settings')));
    await frames(t);
    await t.binding.handlePopRoute();
    await frames(t);
    expect(find.byKey(const Key('nav-browse')), findsOneWidget);
    expect(find.byType(MovieStage), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await frames(t);
    repo.dispose();
  });
}
