import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/ui/paper.dart';

import 'support/pack_cleanup_fixture.dart';

class DelayedQueueLibrary extends CleanupReaderLibrary {
  int queueReads = 0;
  bool holdQueue = false;
  final queueRelease = Completer<void>();
  @override
  PackReader createPackReader() => DelayedQueueReader(this, owner);
}

class DelayedQueueReader extends CleanupReader {
  DelayedQueueReader(DelayedQueueLibrary super.repo, super.owner);
  @override
  Future<ReaderQueuePage> queue(
    String sessionId, {
    int offset = 0,
    int limit = 40,
  }) async {
    final data = repo as DelayedQueueLibrary;
    data.queueReads++;
    if (data.holdQueue) await data.queueRelease.future;
    return super.queue(sessionId, offset: offset, limit: limit);
  }
}

void main() {
  Future<void> until(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 180; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      expect(t.takeException(), isNull);
      if (done()) return;
    }
    fail('Reader did not complete the expected operation');
  }

  Future<void> open(
    WidgetTester t,
    CleanupReaderLibrary repo, {
    String anchor = 'p0',
  }) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(() async {
      if (repo is DelayedQueueLibrary && !repo.queueRelease.isCompleted) {
        repo.queueRelease.complete();
      }
      if (repo.fileRelease?.isCompleted == false) repo.fileRelease!.complete();
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
          entry: PackReadingEntry(PackQuery(), anchorId: anchor),
          quick: true,
          editTags: (_) async {},
        ),
      ),
    );
    await until(t, () {
      final state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
      return state.session.opened && !state.session.inputBlocked;
    });
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'repeated previous taps share one foreground lookup instead of cancelling one another',
    (t) async {
      final repo = DelayedQueueLibrary();
      await open(t, repo, anchor: 'p2');
      final state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
      repo.holdQueue = true;
      state.session.excludePacks({'p1'});
      await until(t, () => repo.queueReads == 1);
      final previous = find.widgetWithText(TextButton, '上一个');
      await t.tap(previous);
      await t.pump();
      expect(t.widget<TextButton>(previous).onPressed, isNull);
      for (var i = 0; i < 5; i++) {
        await t.tap(previous);
        await t.pump();
      }
      expect(repo.queueReads, 2);
      repo.queueRelease.complete();
      await until(
        t,
        () =>
            state.session.range!.pack!.id == 'p0' &&
            state.session.opened &&
            !state.session.inputBlocked,
      );
      expect(repo.writes.whereType<MovePackReading>(), hasLength(1));
      expect(state.session.error, isEmpty);
      expect(find.text('请求已取消'), findsNothing);
      expect(state.session.displayPosition, 1);
      expect(state.session.displayCount, 2);
    },
  );

  testWidgets(
    'recycling updates counts before its receipt and gives a top undo action in immersion',
    (t) async {
      final repo = CleanupReaderLibrary(count: 4);
      repo.fileStarted = Completer<void>();
      repo.fileRelease = Completer<void>();
      await open(t, repo);
      final state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
      await t.tapAt(t.getCenter(find.byKey(const Key('reader-canvas'))));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 200));
      expect(state.controls, isFalse);
      final trash = find.byKey(const Key('reader-trash-pack'));
      expect(t.getSize(trash), const Size(80, 80));
      await t.tap(trash);
      await until(
        t,
        () =>
            state.session.range?.pack?.id == 'p1' &&
            state.session.opened &&
            !state.session.inputBlocked,
      );
      expect(state.session.displayCount, 3);
      expect(state.session.displayPosition, 1);
      expect(
        state.session.range!.candidateCount,
        4,
        reason: 'the stable server range is preserved',
      );
      expect(state.controls, isFalse);
      expect(find.text('正在移入回收站…'), findsNothing);
      expect(find.byKey(const Key('reader-cleanup-notice')), findsNothing);
      repo.fileRelease!.complete();
      final undo = find.byKey(const Key('reader-notice-undo'));
      await until(t, () => undo.evaluate().isNotEmpty);
      expect(t.getRect(undo).top, lessThan(100));
      expect(t.getRect(undo).overlaps(t.getRect(trash)), isFalse);
      await t.tap(undo);
      await until(
        t,
        () =>
            state.session.range?.pack?.id == 'p0' &&
            state.session.opened &&
            !state.session.inputBlocked,
      );
      expect(state.controls, isFalse);
      expect(state.session.displayCount, 4);
      expect(state.session.displayPosition, 1);
      expect(repo.filePosts, hasLength(2));
      expect(find.text('已撤销移除'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2100));
      expect(find.byKey(const Key('reader-cleanup-notice')), findsNothing);
    },
  );
}
