import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'support/fixture.dart';
import 'support/server_ui.dart';

class DelayedReceipts extends ServerLibraryRepository {
  DelayedReceipts() : super(MemoryCredentialStore());
  Completer<void>? navigation, deletion, restoration;
  @override
  Future<void> moveToVideo(String id) async {
    await navigation?.future;
    await super.moveToVideo(id);
  }

  @override
  Future<void> deleteVideos(
    Set<String> ids, {
    required String requestId,
  }) async {
    await deletion?.future;
    await super.deleteVideos(ids, requestId: requestId);
  }

  @override
  Future<List<String>> restoreVideos(Set<String> ids) async {
    await restoration?.future;
    return super.restoreVideos(ids);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native swipes, consecutive marks, top undo and select-all restore remain responsive',
    (t) async {
      final repo = DelayedReceipts();
      final preferences = UiPreferences(preloadAdjacent: false);
      final ui = ServerUi(t, repo);
      addTearDown(() async {
        for (final gate in [repo.navigation, repo.deletion, repo.restoration]) {
          if (gate != null && !gate.isCompleted) gate.complete();
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 300));
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect('10.0.2.2', 8761, fixturePassword);
      await repo.setScope(
        VideoQuery(folder: '/media/shorts/自然/花卉'),
        order: PlayOrder.sequential,
      );
      final page = await repo.loadPlaybackVideos();
      final ids = page.items.map((v) => v.id).toList();
      expect(ids, hasLength(25));
      final files = jsonEncode(
        (await fixture('/__fixture/files', method: 'GET'))['items'],
      );
      await t.pumpWidget(
        VideoViewerApp(repository: repo, preferences: preferences),
      );
      await ui.ready();
      String? visible() {
        if (find.byType(MovieStage).evaluate().isEmpty) return null;
        final stage = t.widget<MovieStage>(find.byType(MovieStage));
        return stage.videos[stage.index].id;
      }

      repo.navigation = Completer<void>();
      for (var i = 1; i <= 3; i++) {
        await t.drag(
          find.byKey(const Key('video-stage')),
          const Offset(0, -500),
        );
        await ui.until(
          () => visible() == ids[i],
          'swipe $i without a saved position',
        );
      }
      expect(repo.current!.id, ids.first);
      repo.navigation!.complete();
      await ui.until(
        () => repo.current?.id == ids[3],
        'latest selection persisted',
      );
      await ui.tap(find.byTooltip('更多'));
      await ui.text('进入快速整理');
      repo.deletion = Completer<void>();
      await ui.tap(find.byKey(const Key('quick-delete')));
      await ui.until(
        () => visible() == ids[4],
        'first mark advances immediately',
      );
      await ui.tap(find.byKey(const Key('quick-delete')));
      await ui.until(
        () => visible() == ids[5],
        'second mark advances before first receipt',
      );
      expect(find.byKey(const Key('management-loading')), findsNothing);
      final banner = find.byKey(const Key('delete-notice'));
      expect(banner, findsOneWidget);
      expect(
        t.getBottomLeft(banner).dy,
        lessThanOrEqualTo(
          t.getTopLeft(find.byKey(const Key('video-stage'))).dy,
        ),
      );
      await fixture('/__fixture/checkpoint/preview');
      await t.pump(const Duration(seconds: 2));
      await ui.nav('settings');
      await ui.nav('browse');
      expect(visible(), ids[5]);
      repo.deletion!.complete();
      await ui.until(
        () => repo.trashCount == 2 && !repo.fileOperationPending,
        'both marks committed',
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(visible(), ids[5]);
      expect(
        jsonEncode((await fixture('/__fixture/files', method: 'GET'))['items']),
        files,
      );
      await t.pump(const Duration(seconds: 9));
      expect(banner, findsNothing);
      // More than one UI page proves full selection includes unloaded records.
      await repo.deleteVideos(
        ids.toSet().difference({ids[3], ids[4]}),
        requestId: requestId(),
      );
      await ui.nav('settings');
      await ui.text('回收站');
      await ui.until(
        () => find.byKey(const Key('trash-select-all')).evaluate().isNotEmpty,
        'trash loads',
      );
      await ui.tap(find.byKey(const Key('trash-select-all')));
      await ui.until(
        () => find.text('已选 25').evaluate().isNotEmpty,
        'select all pages',
      );
      repo.restoration = Completer<void>();
      await ui.text('恢复');
      expect(find.byKey(const Key('management-loading')), findsNothing);
      await fixture('/__fixture/checkpoint/roots');
      await t.pump(const Duration(seconds: 2));
      await ui.nav('settings');
      await ui.nav('browse');
      repo.restoration!.complete();
      await ui.until(
        () => repo.trashCount == 0 && !repo.fileOperationPending,
        'batch restored in background',
      );
      expect(
        jsonEncode((await fixture('/__fixture/files', method: 'GET'))['items']),
        files,
      );
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace.where(
          (r) => r['method'] == 'POST' && r['path'] == '/api/v1/trash/restore',
        ),
        hasLength(1),
      );
      debugPrint(
        'NONBLOCKING: 3 swipes with blocked save; 2 consecutive marks; top timed notice; all 25 restored with one POST; all original file hashes and paths unchanged.',
      );
    },
  );
}
