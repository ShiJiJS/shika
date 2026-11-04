import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/ui/paper.dart';

import 'support/pack_cleanup_fixture.dart';

void main() {
  for (final mode in ReaderMode.values) {
    for (final sample in [
      (const Size(390, 844), 1.0),
      (const Size(360, 740), 2.0),
      (const Size(844, 390), 1.0),
      (const Size(844, 390), 2.0),
    ]) {
      testWidgets(
        'quick $mode compact controls, tap, swipe and floating removal $sample',
        (t) async {
          final repo = CleanupReaderLibrary();
          repo.prefs['p0'] = ReaderPreferences(mode: mode);
          repo.fileStarted = Completer<void>();
          repo.fileRelease = Completer<void>();
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = sample.$1;
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 24, bottom: 20),
                  textScaler: TextScaler.linear(sample.$2),
                ),
                child: child!,
              ),
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
            for (var i = 0; i < 180; i++) {
              await t.pump(const Duration(milliseconds: 30));
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 3)),
              );
              expect(t.takeException(), isNull);
              if (ready()) return;
            }
            fail('quick reader failed to reach expected state');
          }

          final canvas = find.byKey(const Key('reader-canvas'));
          final chrome = find.byKey(const Key('reader-controls'));
          final trash = find.byKey(const Key('reader-trash-pack'));
          Future<void> tapImage() async {
            await t.tapAt(t.getCenter(canvas));
            await t.pump(const Duration(milliseconds: 400));
            await t.pump(const Duration(milliseconds: 200));
            expect(t.takeException(), isNull);
          }

          await until(
            () => state().session.opened && !state().session.inputBlocked,
          );
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byType(Slider), findsNothing);
          expect(find.byKey(const Key('reader-quick-mode')), findsNothing);
          expect(find.text('图包标签'), findsNothing);
          expect(find.byTooltip('上一张'), findsNothing);
          expect(find.byTooltip('下一张'), findsNothing);
          expect(t.getSize(chrome).height, lessThan(sample.$2 == 1 ? 80 : 150));
          final nav = t.getRect(chrome), button = t.getRect(trash);
          expect(button.overlaps(nav), isFalse);
          expect(button.width, inInclusiveRange(80, 88));
          expect(trash.hitTestable(), findsOneWidget);
          final initialHeight = t.getSize(canvas).height;
          await tapImage();
          expect(state().controls, isFalse);
          expect(find.byKey(const Key('reader-header')), findsNothing);
          expect(chrome, findsNothing);
          expect(t.getSize(canvas).height, greaterThan(initialHeight));
          expect(t.getSize(canvas).height, closeTo(sample.$1.height - 44, 1));
          expect(trash.hitTestable(), findsOneWidget);
          await tapImage();
          expect(state().controls, isTrue);
          final center = t.getCenter(canvas);
          final first = await t.startGesture(
            center - const Offset(20, 0),
            pointer: 10,
          );
          final second = await t.startGesture(
            center + const Offset(20, 0),
            pointer: 11,
          );
          for (var step = 1; step <= 4; step++) {
            await first.moveTo(center + Offset(-20 - step * 15, -step * 12));
            await second.moveTo(center + Offset(20 + step * 15, -step * 12));
            await t.pump(const Duration(milliseconds: 30));
          }
          await first.up();
          await second.up();
          await t.pump(const Duration(milliseconds: 300));
          expect(
            state().controls,
            isTrue,
            reason: 'two-finger upward pinch must not enter immersion',
          );
          expect(state().zoomed, isTrue);
          expect(await state().leave(), isFalse);
          await t.pump(const Duration(milliseconds: 400));
          expect(state().zoomed, isFalse);
          expect(state().controls, isTrue);
          if (mode == ReaderMode.horizontal) {
            await t.drag(canvas, const Offset(-90, 0));
            await t.pump(const Duration(milliseconds: 350));
            expect(
              state().controls,
              isTrue,
              reason: 'horizontal paging must not hide chrome',
            );
          }
          await t.drag(canvas, const Offset(0, -90));
          await t.pump(const Duration(milliseconds: 400));
          await t.pump(const Duration(milliseconds: 200));
          expect(state().controls, isFalse);
          expect(chrome, findsNothing);
          if (mode == ReaderMode.vertical) {
            expect(
              state().session.offsetRatio,
              greaterThan(0),
              reason: 'upward gesture still scrolls the images',
            );
          }
          final before = state().session.index;
          final ratio = state().session.offsetRatio;
          await tapImage();
          expect(state().session.index, before);
          expect(state().session.offsetRatio, closeTo(ratio, .015));
          await tapImage();
          expect(state().controls, isFalse);
          await t.tap(trash);
          await until(
            () =>
                repo.fileStarted!.isCompleted &&
                state().session.cursor?.packId == 'p1' &&
                state().session.opened &&
                !state().session.inputBlocked,
          );
          expect(
            state().controls,
            isFalse,
            reason: 'background removal preserves immersion on the next pack',
          );
          expect(trash.hitTestable(), findsOneWidget);
          expect(state().quickCleanup.items.single.working, isTrue);
          expect(repo.filePosts.single.containsKey('reading'), isFalse);
          repo.fileRelease!.complete();
          await until(() => !state().quickCleanup.items.single.working);
          expect(state().controls, isFalse);
          expect(state().session.cursor!.packId, 'p1');
          expect(await state().leave(), isFalse);
          expect(
            state().controls,
            isTrue,
            reason: 'Back first restores controls',
          );
          await t.pump(const Duration(milliseconds: 200));
          expect(find.byKey(const Key('reader-header')), findsOneWidget);
        },
      );
    }
  }
}
