import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_trash_page.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/main.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/restore_plan_fixture.dart';
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

void main() {
  testWidgets(
    'entering whole plan immediately after acceptance dismisses the root snackbar before the secondary route',
    (t) async {
      final repo = RestoreLibrary();
      final original = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      await repo.initialize();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        VideoPlayerPlatform.instance = original;
      });
      await t.pumpWidget(VideoViewerApp(repository: repo));
      Future<void> tap(Finder target) async {
        for (var i = 0; i < 80 && target.evaluate().isEmpty; i++) {
          await t.pump(const Duration(milliseconds: 40));
        }
        await t.ensureVisible(target);
        await t.pump(const Duration(milliseconds: 250));
        await t.tap(target);
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
      }

      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('回收站'));
      await tap(find.byKey(const Key('trash-kind-pack')));
      await tap(find.byKey(const Key('pack-trash-select-all')));
      await tap(find.byKey(const Key('pack-trash-restore')));
      await tap(find.byKey(const Key('pack-restore-plan-confirm')));
      for (var i = 0; i < 40 && find.byType(SnackBar).evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(repo.planBodies.length, 1);
      expect(find.byType(SnackBar), findsWidgets);
      await tap(find.byKey(const Key('pack-trash-plan-result')));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('maintenance-detail-state')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
  ]) {
    testWidgets(
      'whole restore confirmation, lost stop receipt and paged stopped results ${sample.$1}/${sample.$2}',
      (t) async {
        final repo = RestoreLibrary();
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = sample.$1;
        t.platformDispatcher.textScaleFactorTestValue = sample.$2;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: SafeArea(
                child: PackTrashPage(repository: repo, active: true),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        Future<void> tap(Finder target) async {
          if (target.evaluate().isEmpty) {
            await t.scrollUntilVisible(
              target,
              350,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 60,
            );
          }
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await Scrollable.ensureVisible(t.element(target), alignment: .5);
          await t.pumpAndSettle();
          expect(target.hitTestable(), findsOneWidget);
          await t.tap(target);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }

        await tap(find.byKey(const Key('pack-trash-select-all')));
        await tap(find.byKey(const Key('pack-trash-restore')));
        await tap(find.text('取消').last);
        expect(repo.planBodies, isEmpty);
        expect(find.text('已选 27'), findsOneWidget);
        await tap(find.byKey(const Key('pack-trash-restore')));
        await tap(find.byKey(const Key('pack-restore-plan-confirm')));
        expect(repo.planBodies.length, 1);
        expect((repo.planBodies.single['trash_ids'] as List).length, 27);
        expect(repo.posts, isEmpty);
        expect(find.text('已选 0'), findsOneWidget);
        await tap(find.byKey(const Key('pack-trash-plan-result')));
        await tap(find.byKey(const Key('restore-plan-stop')));
        await tap(find.text('取消'));
        expect(repo.planBodies.length, 1);
        repo.loseStop = true;
        await tap(find.byKey(const Key('restore-plan-stop')));
        await tap(find.byKey(const Key('restore-plan-stop-confirm')));
        expect(find.textContaining('停止结果待核对'), findsOneWidget);
        expect(repo.planBodies.length, 2);
        await tap(find.byTooltip('查询原结果'));
        expect(find.textContaining('停止请求已受理'), findsOneWidget);
        expect(repo.planBodies.length, 2);
        final old = repo.planBook['plan-0']!;
        repo.planBook['plan-0'] = planJson(
          'plan-0',
          old['request_id'],
          27,
          succeeded: 2,
          stopped: 25,
          stopRequested: true,
        );
        repo.rows = [MaintenanceTask(planSummary(repo.planBook['plan-0']!))];
        await tap(find.byTooltip('查询原结果'));
        expect(find.textContaining('已停止 25'), findsOneWidget);
        expect(find.byKey(const Key('restore-plan-stop')), findsNothing);
        expect(find.text('已停止，未执行恢复'), findsWidgets);
        await tap(find.byKey(const Key('task-items-next')));
        expect(find.byKey(const Key('task-member-member-26')), findsOneWidget);
        expect(await repo.createPackRestorePlans().pending(), isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
