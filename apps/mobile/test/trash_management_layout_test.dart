import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_trash_page.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/pack_trash_fixture.dart';
import 'support/restore_plan_fixture.dart';
import 'support/reveal_action.dart';
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

void main() {
  late TrashLibrary videoRepo;
  setUpAll(() async {
    videoRepo = TrashLibrary();
    await videoRepo.initialize();
    await videoRepo.deleteVideos(
      videoRepo.snapshot.videos.take(2).map((v) => v.id).toSet(),
      requestId: 'two-trash-videos',
    );
  });
  tearDownAll(() => videoRepo.dispose());
  testWidgets(
    'original restore receipt releases only its selection and preserves later choices',
    (t) async {
      final repo = RestoreLibrary()..losePlan = true;
      await repo.initialize();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(body: PackTrashPage(repository: repo, active: true)),
        ),
      );
      await t.pumpAndSettle();
      Future<void> tap(Finder f) async {
        await revealAction(t, f);
        await t.tap(f);
        await t.pumpAndSettle();
      }

      await tap(find.byKey(const Key('pack-trash-select-all')));
      await tap(find.byKey(const Key('pack-trash-item-trash-0')));
      await tap(find.byKey(const Key('pack-trash-restore')));
      await tap(find.byKey(const Key('pack-restore-plan-confirm')));
      expect(repo.planBodies.single['trash_ids'], hasLength(26));
      await revealAction(t, find.byKey(const Key('pack-trash-restore')));
      expect(find.text('保留选择 26'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('pack-trash-restore')))
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('pack-trash-permanent')))
            .onPressed,
        isNull,
      );
      await tap(find.byKey(const Key('pack-trash-item-trash-0')));
      await tap(find.byKey(const Key('pack-trash-plans-pending')));
      await tap(find.byTooltip('返回操作任务'));
      expect(find.text('已选 1'), findsOneWidget);
      expect(repo.planBodies, hasLength(1));
      expect(repo.posts, isEmpty);
    },
  );
  testWidgets(
    'video row restoration retains the other selected video and all packs',
    (t) async {
      final repo = videoRepo;
      final original = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = UnreadyVideo();
      final videos = repo.snapshot.videos.take(2).toList();
      expect(videos, hasLength(2));
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        VideoPlayerPlatform.instance = original;
      });
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await t.pump(const Duration(milliseconds: 500));
      Future<void> tap(Finder f) async {
        await revealAction(t, f);
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
      }

      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('回收站'));
      await tap(find.byKey(Key('trash-${videos[0].id}')));
      await tap(find.byKey(Key('video-trash-row-restore-${videos[1].id}')));
      await t.runAsync(() async {
        final end = DateTime.now().add(const Duration(seconds: 2));
        while (repo.snapshot.videos
                    .singleWhere((v) => v.id == videos[1].id)
                    .status !=
                VideoStatus.available &&
            DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pump(const Duration(milliseconds: 400));
      expect(
        repo.snapshot.videos.singleWhere((v) => v.id == videos[1].id).status,
        VideoStatus.available,
      );
      expect(
        repo.snapshot.videos.singleWhere((v) => v.id == videos[0].id).status,
        VideoStatus.trash,
      );
      expect(find.text('已选 1'), findsOneWidget);
      expect(repo.records, hasLength(27));
      expect(repo.posts, isEmpty);
    },
  );
  for (final wholePlan in [false, true]) {
    testWidgets(
      'row restoration preserves unrelated selection, plan=$wholePlan',
      (t) async {
        final repo = wholePlan ? RestoreLibrary() : TrashLibrary(count: 3);
        await repo.initialize();
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
        });
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(body: PackTrashPage(repository: repo, active: true)),
          ),
        );
        await t.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await revealAction(t, f);
          await t.tap(f);
          await t.pumpAndSettle();
        }

        await tap(find.byKey(const Key('pack-trash-item-trash-0')));
        await tap(find.byKey(const Key('pack-trash-row-restore-trash-1')));
        if (wholePlan) {
          final plans = repo as RestoreLibrary;
          expect(find.text('恢复 1 个图包'), findsOneWidget);
          await tap(find.text('取消'));
          expect(plans.planBodies, isEmpty);
          expect(find.text('已选 1'), findsOneWidget);
          await tap(find.byKey(const Key('pack-trash-row-restore-trash-1')));
          await tap(find.byKey(const Key('pack-restore-plan-confirm')));
          expect(plans.planBodies.single['trash_ids'], ['trash-1']);
        } else {
          expect(repo.posts.single['trash_ids'], ['trash-1']);
          expect(repo.records.keys, contains('trash-0'));
          expect(repo.records.keys, isNot(contains('trash-1')));
        }
        expect(find.text('已选 1'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'short keyboard window retains search and reachable selection actions $scale',
      (t) async {
        final repo = TrashLibrary();
        await repo.initialize();
        t.view.physicalSize = const Size(844, 390);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        Widget host(double inset) => MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: const Size(844, 390),
                viewInsets: EdgeInsets.only(bottom: inset),
                textScaler: TextScaler.linear(scale),
              ),
              child: SizedBox(
                height: 390 - inset,
                child: PackTrashPage(repository: repo, active: true),
              ),
            ),
          ),
        );
        await t.pumpWidget(host(0));
        await t.pumpAndSettle();
        final select = find.byKey(const Key('pack-trash-select-all'));
        await revealAction(t, select);
        await t.tap(select);
        await t.pumpAndSettle();
        await t.pumpWidget(host(280));
        await t.pumpAndSettle();
        final action = find.byKey(const Key('pack-trash-restore'));
        await revealAction(t, action);
        expect(t.getRect(action).bottom, lessThanOrEqualTo(110.1));
        expect(repo.posts, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
