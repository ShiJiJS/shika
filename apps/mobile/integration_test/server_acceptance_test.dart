import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper_toggle.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'support/fixture.dart';
import 'support/server_ui.dart';

// Run against the disposable 8761 fixture, never a user's media instance.
// The host force-stops Android between the ordinary and E2E_RESUME runs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('V1 network appearance controls and native process reopen', (
    t,
  ) async {
    const resume = bool.fromEnvironment('E2E_RESUME');
    final file = File(
      '${(await getApplicationSupportDirectory()).path}/e2e-v1-appearance.json',
    );
    final store = SecureCredentialStore(key: 'video_viewer.e2e.acceptance.v1');
    if (!resume) {
      await store.clear();
      if (await file.exists()) await file.delete();
    }
    final preferences = await UiPreferences.load(file: file);
    final repo = ServerLibraryRepository(store, port: 8761);
    final ui = ServerUi(t, repo);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 300));
      repo.dispose();
      preferences.dispose();
    });
    if (resume) {
      expect(preferences.dark, isTrue);
      expect(await store.read(), isNotNull);
    } else {
      await preferences.setPreloadAdjacent(false);
      await repo.connect('10.0.2.2', 8761, fixturePassword);
    }
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: preferences,
        initializeRepository: resume,
      ),
    );
    await ui.until(() => repo.snapshot.connected, 'saved network session');
    await ui.ready();
    final videoId = repo.current!.id;
    final controller = t
        .widget<VideoPlayer>(find.byType(VideoPlayer).last)
        .controller;
    if (!resume) {
      await ui.tap(find.byTooltip('更多'));
      await ui.text('切换暗黑模式');
      await ui.until(
        () => preferences.dark && controller.value.isPlaying,
        'dark network playback',
      );
      expect(
        identical(
          t.widget<VideoPlayer>(find.byType(VideoPlayer).last).controller,
          controller,
        ),
        isTrue,
      );
    }
    expect(
      Theme.of(t.element(find.byKey(const Key('nav-browse')))).brightness,
      Brightness.dark,
    );
    expect(repo.current!.id, videoId);
    await ui.nav('settings');
    final toggle = find.byKey(const Key('dark-mode-setting'));
    expect(
      t
          .widget<PaperToggle>(
            find.descendant(of: toggle, matching: find.byType(PaperToggle)),
          )
          .value,
      isTrue,
    );
    if (resume) {
      await ui.tap(toggle);
      await ui.until(() => !preferences.dark, 'settings updates appearance');
      await ui.tap(find.byTooltip('更多'));
      expect(find.text('切换暗黑模式'), findsOneWidget);
      await ui.text('切换暗黑模式');
      await ui.until(() => preferences.dark, 'menu and settings agree');
      for (final page in ['library', 'tags', 'settings']) {
        await ui.nav(page);
        expect(
          Theme.of(t.element(find.byKey(Key('nav-$page')))).brightness,
          Brightness.dark,
        );
      }
      await ui.nav('browse');
      await ui.ready();
      await ui.until(
        () => t
            .widget<VideoPlayer>(find.byType(VideoPlayer).last)
            .controller
            .value
            .isPlaying,
        'native video resumes on themed page',
      );
      expect(repo.current!.id, videoId);
    }
    final saved = await UiPreferences.load(file: file);
    expect(saved.dark, isTrue);
    expect(saved.preloadAdjacent, isFalse);
    saved.dispose();
    debugPrint(
      'V1_APPEARANCE_RESULT {"native_reopen":$resume,"network_video":true,"theme_saved":true,"both_entries":$resume}',
    );
    expect(t.takeException(), isNull);
  });
}
