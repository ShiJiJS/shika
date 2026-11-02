import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reading_session.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';

import 'support/pack_cleanup_fixture.dart';

void main() {
  late CleanupReaderLibrary repo;
  late PackReadingSession session;
  var nonce = 0;
  setUp(() {
    repo = CleanupReaderLibrary();
    nonce = 0;
    session = PackReadingSession(
      repo,
      PackReadingEntry(PackQuery()),
      nonce: () => 'cleanup-${nonce++}',
      saveDelay: const Duration(days: 1),
    );
  });
  tearDown(() {
    session.dispose();
    repo.dispose();
  });
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out: ${session.cleanupError}');
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  void frame() {
    session.visibleFrame(
      session.index,
      session.currentPage!.id,
      session.packEpoch,
    );
  }

  Future<void> start({String? anchor}) async {
    if (anchor != null) {
      session.dispose();
      session = PackReadingSession(
        repo,
        PackReadingEntry(PackQuery(), anchorId: anchor),
        nonce: () => 'cleanup-${nonce++}',
        saveDelay: const Duration(days: 1),
      );
    }
    expect(await session.start(), isTrue);
    await until(() => !session.loadingPages);
    frame();
    await until(() => session.opened && !session.busy);
  }

  test('quick cleanup flushes, freezes old frames and advances only after a confirmed task', () async {
    await start();
    session.show(1, ratio: .37);
    frame();
    final epoch = session.packEpoch;
    repo.fileStarted = Completer<void>();
    repo.fileRelease = Completer<void>();
    final work = session.removeCurrent(quick: true);
    await repo.fileStarted!.future;
    expect(repo.marks['p0']!.pageId, 'p0-1');
    expect(repo.marks['p0']!.offsetRatio, .37);
    expect(session.cleanupFrozen, isTrue);
    final revision = repo.revisions['p0'];
    session.show(2, ratio: .9);
    session.visibleFrame(2, 'p0-2', epoch);
    expect(session.index, 1);
    expect(await session.flush(), isFalse);
    expect(repo.revisions['p0'], revision);
    repo.fileRelease!.complete();
    final task = await work;
    expect(task!.result!.transition!.packId, 'p1');
    expect(session.cursor!.packId, 'p1');
    expect(session.range!.candidateCount, 3);
    expect(repo.openedCount, 1);
    expect(session.opened, isFalse);
    await until(() => !session.loadingPages);
    frame();
    await until(() => session.opened && !session.busy);
    expect(repo.openedCount, 2);
    expect(repo.scopes, 1);
  });
  test('a lost committed response keeps original view frozen; receipt continues without POST replay', () async {
    await start();
    session.show(1, ratio: .37);
    frame();
    repo.loseAfter = true;
    expect(await session.removeCurrent(quick: true), isNull);
    expect(session.cursor!.packId, 'p0');
    expect(session.hasCleanup, isTrue);
    expect(repo.filePosts.length, 1);
    expect((await session.checkCleanup())!.result!.succeeded, 1);
    expect(repo.filePosts.length, 1);
    expect(session.cursor!.packId, 'p1');
    expect(session.hasPending, isFalse);
  });
  test('unaccepted request 404 needs explicit resubmission with original owner and nonce', () async {
    await start();
    repo.loseBefore = true;
    await session.removeCurrent(quick: true);
    final original = repo.filePosts.single;
    expect(await session.checkCleanup(), isNull);
    expect(session.cleanupCanResend, isTrue);
    expect(repo.filePosts.length, 1);
    expect((await session.checkCleanup(resend: true))!.result!.succeeded, 1);
    expect(repo.filePosts.last, original);
    expect(session.cursor!.packId, 'p1');
  });
  test('metadata failure after confirmed deletion cannot double advance or save the removed pack', () async {
    await start();
    repo.failMetadata = true;
    expect(await session.removeCurrent(quick: true), isNull);
    expect(repo.revision, 1);
    expect(session.cursor, isNull);
    expect(session.hasCleanup, isTrue);
    expect(await session.flush(), isFalse);
    repo.failMetadata = false;
    expect((await session.checkCleanup())!.result!.succeeded, 1);
    expect(repo.revision, 1);
    expect(repo.filePosts.length, 1);
    expect(session.cursor!.packId, 'p1');
  });
  test('undo flushes next pack and restores original page, ratio and preferences within the fixed range', () async {
    await start();
    await session.setPreferences(
      const ReaderPreferences(
        mode: ReaderMode.vertical,
        direction: ReaderDirection.rtl,
        gap: true,
        fit: ReaderFit.width,
      ),
    );
    session.show(1, ratio: .37);
    frame();
    final original = await session.removeCurrent(quick: true);
    await until(() => !session.loadingPages);
    frame();
    await until(() => session.opened && !session.busy);
    session.show(2, ratio: .72);
    frame();
    final result = await session.undoDelete(original!);
    expect(result!.result!.readingRestored, isTrue);
    expect(repo.marks['p1']!.offsetRatio, .72);
    expect(session.cursor!.packId, 'p0');
    expect(session.index, 1);
    expect(session.offsetRatio, .37);
    expect(session.preferences.mode, ReaderMode.vertical);
    expect(session.preferences.direction, ReaderDirection.rtl);
    expect(session.preferences.gap, isTrue);
    expect(session.preferences.fit, ReaderFit.width);
    expect(repo.scopes, 1);
  });
  test(
    'undo returning content only never hijacks the current page or range',
    () async {
      await start();
      final original = await session.removeCurrent(quick: true);
      await until(() => !session.loadingPages);
      frame();
      await until(() => session.opened && !session.busy);
      session.show(1, ratio: .63);
      frame();
      repo.undoRestores = false;
      expect(
        (await session.undoDelete(original!))!.result!.readingRestored,
        isFalse,
      );
      expect(session.cursor!.packId, 'p1');
      expect(session.index, 1);
      expect(session.offsetRatio, .63);
      expect(repo.unavailable, isEmpty);
    },
  );
  test(
    'tail cleanup finishes without loading an earlier available pack',
    () async {
      await start(anchor: 'p2');
      final task = await session.removeCurrent(quick: true);
      expect(task!.result!.transition!.finished, isTrue);
      expect(session.cleanupFinished, isTrue);
      expect(session.cursor, isNull);
      expect(repo.cursor, 2);
      expect(repo.scopes, 1);
    },
  );
  test('normal reader delete returns and can resume the same range after undo without a new session', () async {
    await start();
    session.show(1, ratio: .41);
    frame();
    final task = await session.removeCurrent(quick: false);
    final command = session.lastDeleteCommand!;
    expect(task!.result!.transition, isNull);
    expect(session.cleanupFinished, isTrue);
    expect(repo.cursor, 0);
    expect(command.readerContext!.quick, isFalse);
    final files = repo.createPackFiles();
    final restored = await files.resolve(
      PackFileCommand.undo(
        'external-undo',
        task.id,
        readerContext: command.readerContext,
      ),
      submit: true,
    );
    expect(restored!.result!.readingRestored, isTrue);
    session.dispose();
    session = PackReadingSession(repo, command.readerContext!.entry);
    expect(
      await session.start(resumeSessionId: command.readingSessionId),
      isTrue,
    );
    expect(repo.scopes, 1);
    expect(session.index, 1);
    expect(session.offsetRatio, .41);
  });
  test('a changed connection cannot apply late cleanup results', () async {
    await start();
    repo.fileStarted = Completer<void>();
    repo.fileRelease = Completer<void>();
    final work = session.removeCurrent(quick: true);
    await repo.fileStarted!.future;
    repo.owner = Object();
    repo.notifyListeners();
    repo.fileRelease!.complete();
    expect(await work, isNull);
    expect(session.invalidated, isTrue);
    expect(session.cursor?.packId, 'p0');
    expect(session.cleanupFinished, isFalse);
  });
}
