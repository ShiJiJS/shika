import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';
import 'package:shika/ui/preferences.dart';

import 'player_lifecycle_test.dart' show ReadyVideo, frames;

class ExitVideo extends ReadyVideo {
  bool Function()? viewMounted;
  int disposedWithView = 0, disposals = 0;
  @override
  Future<void> dispose(int playerId) async {
    disposals++;
    if (viewMounted!()) disposedWithView++;
    await super.dispose(playerId);
  }
}

void main() {
  for (final systemBack in [false, true]) {
    testWidgets(
      'initialized native view detaches before decoder disposal, system back=$systemBack',
      (t) async {
        final original = VideoPlayerPlatform.instance;
        final platform = ExitVideo();
        VideoPlayerPlatform.instance = platform;
        platform.viewMounted = () =>
            find.byKey(const Key('actual-video')).evaluate().isNotEmpty;
        final repo = DemoLibraryRepository(
          MemoryStateStore(),
          latency: Duration.zero,
        );
        final preferences = UiPreferences(preloadAdjacent: false);
        addTearDown(() {
          preferences.dispose();
          repo.dispose();
          VideoPlayerPlatform.instance = original;
        });
        await repo.initialize();
        await t.pumpWidget(
          ShikaApp(repository: repo, preferences: preferences),
        );
        await frames(t);
        await t.tap(find.byKey(const Key('video-quick-cleanup')));
        await frames(t);
        final session = t.widget<MovieStage>(find.byType(MovieStage)).session!;
        expect(session.debugPlayers.single.value.isInitialized, isTrue);
        expect(find.byKey(const Key('actual-video')), findsOneWidget);
        if (systemBack) {
          await t.binding.handlePopRoute();
        } else {
          await t.tap(find.byKey(const Key('preview-back')));
        }
        await frames(t);
        expect(find.byKey(const Key('video-preview-route')), findsNothing);
        expect(platform.disposals, 1);
        expect(platform.disposedWithView, 0);
        expect(platform.events, isEmpty);
        expect(session.debugPlayers, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
  }
}
