import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/main.dart';

import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'support/pack_trash_fixture.dart';

class GatedTrash extends TrashLibrary {
  bool unavailable = false;
  @override
  PackTrashCatalog createPackTrash() {
    if (unavailable) throw const LibraryFailure('恢复任务尚未结束，请稍后重新读取');
    return super.createPackTrash();
  }
}

void main() {
  late GatedTrash repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = GatedTrash();
    await repo.initialize();
    await repo.deleteVideos({
      repo.snapshot.videos.first.id,
    }, requestId: 'fixture-video-trash');
  });
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
  ]) {
    for (final scenario in ['restore', 'unknown', 'gate']) {
      testWidgets(
        'typed trash $scenario from settings ${sample.$1} / ${sample.$2}',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = sample.$1;
          t.platformDispatcher.textScaleFactorTestValue = sample.$2;
          addTearDown(() async {
            await t.pumpWidget(const SizedBox());
            await t.pump();
            repo.dispose();
            VideoPlayerPlatform.instance = original;
            t.view.resetPhysicalSize();
            t.view.resetDevicePixelRatio();
            t.platformDispatcher.clearTextScaleFactorTestValue();
          });
          final videoIds = repo.snapshot.videos
              .where((v) => v.status == VideoStatus.trash)
              .map((v) => v.id)
              .toSet();
          final videoCount = videoIds.length;
          repo.unavailable = scenario == 'gate';
          await t.pumpWidget(VideoViewerApp(repository: repo));
          Future<void> until(bool Function() done) async {
            for (var i = 0; i < 120; i++) {
              await t.pump(const Duration(milliseconds: 40));
              expect(t.takeException(), isNull);
              if (done()) return;
            }
            debugPrint(
              t
                  .widgetList<Text>(find.byType(Text))
                  .map((w) => w.data)
                  .join(' | '),
            );
            debugPrint(
              'TRASH_FIXTURE count=${repo.trashCount} records=${repo.records.length}',
            );
            fail('Trash view did not reach expected state');
          }

          Future<void> tap(Finder target) async {
            await until(() => target.evaluate().isNotEmpty);
            await t.ensureVisible(target);
            await t.pump(const Duration(milliseconds: 350));
            expect(target.hitTestable(), findsOneWidget);
            await t.tap(target);
            await t.pump(const Duration(milliseconds: 350));
            expect(t.takeException(), isNull);
          }

          await tap(find.byKey(const Key('nav-settings')));
          await tap(find.text('回收站'));
          await until(
            () => find.text('共 $videoCount 个视频').evaluate().isNotEmpty,
          );
          expect(repo.pageQueries, isEmpty);
          await tap(find.byKey(const Key('trash-kind-pack')));
          if (scenario == 'gate') {
            expect(find.text('恢复任务尚未结束，请稍后重新读取'), findsOneWidget);
            repo.unavailable = false;
            await tap(find.text('重新读取'));
          }
          await until(() => find.text('共 27 个图包').evaluate().isNotEmpty);
          await tap(find.byKey(const Key('pack-trash-select-all')));
          await until(() => find.text('已选 27').evaluate().isNotEmpty);
          if (scenario != 'unknown') {
            await tap(find.byKey(const Key('pack-trash-item-trash-0')));
            await tap(find.byKey(const Key('pack-trash-next')));
            expect(
              find.byKey(const Key('pack-trash-item-trash-24')),
              findsOneWidget,
            );
            expect(find.text('已选 26'), findsOneWidget);
          } else {
            repo.loseAfter = true;
          }
          await tap(find.byKey(const Key('pack-trash-restore')));
          if (scenario == 'unknown') {
            await until(
              () => find
                  .byKey(const Key('pack-trash-pending'))
                  .evaluate()
                  .isNotEmpty,
            );
            expect(repo.posts.length, 1);
            await tap(find.byKey(const Key('pack-trash-pending')));
            await until(
              () =>
                  find.text('共 0 个图包').evaluate().isNotEmpty &&
                  find
                      .byKey(const Key('pack-trash-pending'))
                      .evaluate()
                      .isEmpty,
            );
            expect(repo.posts.length, 1);
            expect(
              repo.calls.any(
                (r) => r.startsWith('GET /api/v1/pack-file-requests/'),
              ),
              isTrue,
            );
          } else {
            await until(() => find.text('共 1 个图包').evaluate().isNotEmpty);
            expect(repo.records.keys, ['trash-0']);
          }
          await tap(find.byKey(const Key('trash-kind-video')));
          await until(
            () => find.text('共 $videoCount 个视频').evaluate().isNotEmpty,
          );
          expect(
            repo.snapshot.videos
                .where((v) => v.status == VideoStatus.trash)
                .map((v) => v.id)
                .toSet(),
            videoIds,
          );
        },
      );
    }
  }
}
