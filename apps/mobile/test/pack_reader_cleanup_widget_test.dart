import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_file_action.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/pack_cleanup_fixture.dart';

void main() {
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
  ]) {
    for (final scenario in ['quick', 'normal', 'unknown', 'tail']) {
      testWidgets(
        '$scenario cleanup preserves reader and source ${sample.$1} / ${sample.$2}',
        (t) async {
          final repo = CleanupReaderLibrary();
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = sample.$1;
          PackFileOutcome? returned;
          addTearDown(() async {
            await t.pumpWidget(const SizedBox());
            await t.pump();
            repo.dispose();
            t.view.resetPhysicalSize();
            t.view.resetDevicePixelRatio();
          });
          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(sample.$2)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () async {
                        returned = await Navigator.of(context)
                            .push<PackFileOutcome>(
                              MaterialPageRoute<PackFileOutcome>(
                                builder: (_) => PackReaderPage(
                                  repository: repo,
                                  entry: PackReadingEntry(
                                    PackQuery(),
                                    anchorId: scenario == 'tail' ? 'p2' : 'p0',
                                  ),
                                  quick: scenario != 'normal',
                                  editTags: (_) async {},
                                ),
                              ),
                            );
                      },
                      child: const Text('打开'),
                    ),
                  ),
                ),
              ),
            ),
          );
          PackReaderPageState state() => t.state(find.byType(PackReaderPage));
          Future<void> until(bool Function() condition) async {
            for (var i = 0; i < 150; i++) {
              await t.pump(const Duration(milliseconds: 30));
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 3)),
              );
              expect(t.takeException(), isNull);
              if (condition()) return;
            }
            fail('Cleanup did not reach expected state');
          }

          Future<void> tap(Finder target) async {
            await t.pump(const Duration(milliseconds: 350));
            await t.ensureVisible(target);
            await t.pump(const Duration(milliseconds: 300));
            expect(target.hitTestable(), findsOneWidget);
            await t.tap(target);
            await t.pump();
          }

          await tap(find.text('打开'));
          await until(
            () =>
                find.byType(PackReaderPage).evaluate().isNotEmpty &&
                state().session.opened &&
                !state().session.busy,
          );
          state().jump(1);
          await until(
            () => state().session.index == 1 && state().session.unsaved,
          );
          final original = state().session.range!.pack!.id;
          if (scenario == 'normal') {
            await tap(find.byTooltip('图包更多'));
            await tap(find.text('整包移入回收站'));
            expect(find.text('整包移入回收站？'), findsOneWidget);
            await tap(find.text('移入回收站'));
          } else {
            if (scenario == 'unknown') repo.loseAfter = true;
            await tap(find.byKey(const Key('reader-trash-pack')));
          }
          if (scenario == 'normal' || scenario == 'tail') {
            await until(
              () =>
                  find.byType(PackReaderPage).evaluate().isEmpty &&
                  returned != null,
            );
            expect(
              returned!.command.readerContext!.quick,
              scenario != 'normal',
            );
            expect(returned!.command.readingSessionId, repo.identity);
            expect(repo.marks[original]!.pageId, '$original-1');
            expect(repo.finished, scenario == 'tail');
            return;
          }
          if (scenario == 'unknown') {
            await until(
              () => state().session.hasCleanup && !state().session.cleanupBusy,
            );
            expect(state().session.cursor!.packId, 'p0');
            expect(
              find.byKey(const Key('reader-cleanup-status')),
              findsOneWidget,
            );
            final pager = find.byKey(const Key('reader-horizontal'));
            await t.drag(pager, const Offset(-300, 0), warnIfMissed: false);
            await t.pump(const Duration(milliseconds: 300));
            expect(state().session.index, 1);
            expect(
              t
                  .widget<FilledButton>(
                    find.byKey(const Key('reader-trash-pack')),
                  )
                  .onPressed,
              isNull,
            );
            await tap(find.text('查询原结果'));
          }
          await until(
            () =>
                state().session.cursor?.packId == 'p1' &&
                state().session.opened &&
                !state().session.inputBlocked,
          );
          expect(repo.filePosts.length, 1);
          expect(repo.scopes, 1);
          expect(state().session.range!.candidateCount, 3);
          await tap(find.text('撤销'));
          await until(
            () =>
                state().session.cursor?.packId == 'p0' &&
                state().session.opened &&
                !state().session.inputBlocked,
          );
          expect(state().session.index, 1);
          expect(repo.scopes, 1);
          expect(repo.unavailable, isEmpty);
          await tap(find.text('完成'));
          expect(find.byType(PackReaderPage), findsOneWidget);
          expect(state().quick, isFalse);
          expect(find.byTooltip('阅读设置'), findsOneWidget);
          await tap(find.byTooltip('返回来源'));
          await until(() => find.byType(PackReaderPage).evaluate().isEmpty);
          expect(returned, isNull);
        },
      );
    }
  }
}
