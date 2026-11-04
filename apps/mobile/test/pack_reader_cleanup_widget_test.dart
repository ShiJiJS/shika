import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_file_action.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/ui/paper.dart';

import 'support/pack_cleanup_fixture.dart';

void main() {
  slowCleanupTests();
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 2.0),
  ]) {
    for (final scenario in ['quick', 'normal', 'unknown', 'tail']) {
      testWidgets(
        '$scenario cleanup preserves reader and source ${sample.$1} / ${sample.$2}',
        (t) async {
          final repo = CleanupReaderLibrary();
          repo.prefs['p1'] = const ReaderPreferences(
            mode: ReaderMode.horizontal,
          );
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
            await tap(find.text('移入回收站'));
            expect(find.text('移入回收站？'), findsOneWidget);
            await tap(find.text('移入回收站'));
          } else {
            if (scenario == 'unknown') repo.loseAfter = true;
            await tap(find.byKey(const Key('reader-trash-pack')));
          }
          if (scenario == 'normal') {
            await until(
              () =>
                  find.byType(PackReaderPage).evaluate().isEmpty &&
                  returned != null,
            );
            expect(returned!.command.readerContext!.quick, isFalse);
            expect(returned!.command.readingSessionId, repo.identity);
            expect(repo.marks[original]!.pageId, '$original-1');
            return;
          }
          if (scenario == 'tail') {
            await until(
              () =>
                  state().showingEnd &&
                  !state().quickCleanup.items.single.working,
            );
            expect(state().session.displayCount, 2);
            expect(state().session.displayPosition, 2);
            expect(find.byKey(const Key('reader-notice-undo')), findsOneWidget);
            await tap(find.byKey(const Key('reader-notice-undo')));
            await until(
              () =>
                  state().session.opened &&
                  !state().session.inputBlocked &&
                  !state().showingEnd,
            );
            expect(state().session.range!.pack!.id, 'p2');
            expect(state().session.displayCount, 3);
            expect(state().session.displayPosition, 3);
            expect(state().session.index, 1);
            await tap(find.byTooltip('返回来源'));
            await until(() => find.byType(PackReaderPage).evaluate().isEmpty);
            expect(returned, isNull);
            return;
          }
          await until(
            () =>
                state().session.cursor?.packId == 'p1' &&
                state().session.opened &&
                !state().session.inputBlocked,
          );
          await until(() => !state().quickCleanup.items.single.working);
          expect(
            find.byKey(const Key('reader-cleanup-notice')),
            scenario == 'unknown' ? findsNothing : findsOneWidget,
            reason: 'the automatic successor retains the short undo notice',
          );
          expect(find.byKey(const Key('reader-quick-mode')), findsNothing);
          expect(find.byType(Slider), findsNothing);
          if (scenario == 'unknown') {
            expect(state().quickCleanup.unresolved, 1);
            await tap(find.byTooltip('图包更多'));
            await tap(find.text('移除记录（1）'));
            await tap(find.text('查询原结果'));
            await until(() => state().quickCleanup.unresolved == 0);
            Navigator.of(t.element(find.text('移除记录'))).pop();
            await t.pump(const Duration(milliseconds: 350));
          }
          expect(state().session.preferences.mode, ReaderMode.vertical);
          expect(repo.filePosts.length, 1);
          expect(repo.scopes, 1);
          expect(state().session.range!.candidateCount, 3);
          await tap(find.byTooltip('图包更多'));
          await tap(find.text('撤销移除'));
          await until(
            () =>
                state().session.cursor?.packId == 'p0' &&
                state().session.opened &&
                !state().session.inputBlocked,
          );
          expect(state().session.index, 1);
          expect(find.text('已撤销移除'), findsOneWidget);
          final notice = t.getRect(
            find.byKey(const Key('reader-cleanup-notice')),
          );
          final next = t.getRect(find.text('下一个').last);
          expect(notice.overlaps(next), isFalse);
          await t.pump(const Duration(milliseconds: 2100));
          expect(find.byKey(const Key('reader-cleanup-notice')), findsNothing);
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

void slowCleanupTests() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('quick reader stays usable while POST is held $size', (
      t,
    ) async {
      final repo = CleanupReaderLibrary(count: 4);
      repo.prefs['p1'] = const ReaderPreferences(mode: ReaderMode.horizontal);
      repo.fileStarted = Completer<void>();
      repo.fileRelease = Completer<void>();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(() async {
        if (!repo.fileRelease!.isCompleted) repo.fileRelease!.complete();
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: PackReaderPage(
            repository: repo,
            entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
            quick: true,
            editTags: (_) async {},
          ),
        ),
      );
      PackReaderPageState state() => t.state(find.byType(PackReaderPage));
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 150; i++) {
          await t.pump(const Duration(milliseconds: 30));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 3)),
          );
          expect(t.takeException(), isNull);
          if (ready()) return;
        }
        fail('reader failed to advance while background POST is held');
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 300));
        await t.tap(f);
        await t.pump();
      }

      await until(
        () => state().session.opened && !state().session.inputBlocked,
      );
      await tap(find.byKey(const Key('reader-trash-pack')));
      await until(
        () =>
            repo.fileStarted!.isCompleted &&
            state().session.cursor?.packId == 'p1' &&
            state().session.opened &&
            !state().session.inputBlocked,
      );
      expect(state().session.preferences.mode, ReaderMode.vertical);
      expect(state().quickCleanup.items.single.working, isTrue);
      expect(find.byKey(const Key('reader-cleanup-notice')), findsNothing);
      await tap(find.text('下一个').last);
      await until(
        () =>
            state().session.cursor?.packId == 'p2' &&
            state().session.opened &&
            !state().session.inputBlocked,
      );
      repo.fileRelease!.complete();
      await until(() => !state().quickCleanup.items.single.working);
      expect(state().session.cursor!.packId, 'p2');
      expect(repo.filePosts, hasLength(1));
      expect(find.byKey(const Key('reader-cleanup-notice')), findsNothing);
      await tap(find.byTooltip('图包更多'));
      await tap(find.text('阅读方式'));
      await tap(find.text('横向翻页'));
      await until(
        () => state().session.preferences.mode == ReaderMode.horizontal,
      );
      await tap(find.byKey(const Key('reader-settings-done')));
      await t.pump(const Duration(milliseconds: 350));
      await tap(find.text('下一个').last);
      await until(
        () => state().session.cursor?.packId == 'p3' && state().session.opened,
      );
      expect(state().session.preferences.mode, ReaderMode.horizontal);
      expect(repo.prefs['p2']!.mode, ReaderMode.vertical);
      expect(repo.writes.whereType<WritePackPreferences>(), isEmpty);
    });
  }
}
