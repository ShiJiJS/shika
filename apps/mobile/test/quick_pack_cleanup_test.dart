import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reading_session.dart';
import 'package:video_viewer/features/packs/quick_pack_cleanup.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';

import 'support/pack_cleanup_fixture.dart';

void main() {
  late CleanupReaderLibrary repo;
  late PackReadingSession reader;
  late QuickPackCleanup cleanup;
  setUp(() {
    repo = CleanupReaderLibrary(count: 170);
    reader = PackReadingSession(
      repo,
      PackReadingEntry(PackQuery()),
      saveDelay: const Duration(days: 1),
    );
    cleanup = QuickPackCleanup(reader.cleanupFiles);
    cleanup.addListener(() => reader.excludePacks(cleanup.hiddenIds));
  });
  tearDown(() {
    cleanup.dispose();
    reader.dispose();
    repo.dispose();
  });
  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> start() async {
    expect(await reader.start(), isTrue);
    await until(() => reader.manifestReady);
    reader.visibleFrame(0, 'p0-0', reader.packEpoch);
    await until(() => reader.opened && !reader.busy);
  }

  test('held background removal permits navigation; late receipt cannot move newer cursor', () async {
    await start();
    repo.fileStarted = Completer<void>();
    repo.fileRelease = Completer<void>();
    final item = await cleanup.enqueue(repo.pack('p0'));
    await repo.fileStarted!.future;
    expect(reader.inputBlocked, isFalse);
    expect(reader.displayCount, 169);
    expect(
      (await reader.cleanupFiles.pending()).single.requestId,
      item.command.requestId,
    );
    expect(repo.filePosts.single.containsKey('reading'), isFalse);
    expect(await reader.move('p1'), isTrue);
    expect(await reader.move('p2'), isTrue);
    expect(reader.displayPosition, 2);
    expect(reader.displayCount, 169);
    final revision = reader.cursor!.sessionRevision;
    repo.fileRelease!.complete();
    await until(
      () => item.state == QuickRemovalState.succeeded && !item.working,
    );
    expect(reader.cursor!.packId, 'p2');
    expect(repo.cursor, 2);
    expect(
      reader.displayCount,
      169,
      reason: 'a late receipt must not subtract twice',
    );
    expect(reader.displayPosition, 2);
    expect(reader.cursor!.sessionRevision, revision);
    expect((await reader.cleanupFiles.pending()), isEmpty);
    expect(await reader.move('p0'), isFalse);
    expect((await reader.findNeighbor(-1))!.packId, 'p1');
    expect(await cleanup.undo(item), isTrue);
    expect(
      reader.cursor!.packId,
      'p2',
      reason: 'only an explicit UI undo may select the old pack',
    );
    expect(repo.cursor, 2);
    expect(cleanup.hiddenIds, isEmpty);
    expect(reader.displayCount, 170);
    expect(reader.displayPosition, 3);
    expect(repo.filePosts, hasLength(2));
  });

  for (final lostAfter in [false, true]) {
    test(
      'unknown ${lostAfter ? 'committed' : 'unsubmitted'} request is queried with its original ID, never automatically replayed',
      () async {
        await start();
        repo.loseBefore = !lostAfter;
        repo.loseAfter = lostAfter;
        final item = await cleanup.enqueue(repo.pack('p0'));
        await until(() => !item.working);
        expect(item.state, QuickRemovalState.unknown);
        expect(reader.inputBlocked, isFalse);
        expect(await reader.move('p1'), isTrue);
        await cleanup.query(item);
        expect(repo.filePosts, hasLength(1));
        expect(repo.fileReads.last, endsWith(item.command.requestId));
        expect(
          item.state,
          lostAfter ? QuickRemovalState.succeeded : QuickRemovalState.unknown,
        );
        expect(reader.cursor!.packId, 'p1');
        expect((await reader.cleanupFiles.pending()).length, lostAfter ? 0 : 1);
      },
    );
  }

  test('excluded neighbours are skipped across more than a cache window without changing the original scope', () async {
    await start();
    reader.excludePacks({for (var i = 1; i < 160; i++) 'p$i'});
    expect((await reader.findNeighbor(1))!.packId, 'p160');
    expect(repo.scopes, 1);
    expect(reader.range!.candidateCount, 170);
  });

  test('one quick viewing style spans packs and changes without rewriting their saved styles', () async {
    repo.prefs['p0'] = const ReaderPreferences(mode: ReaderMode.vertical);
    repo.prefs['p1'] = const ReaderPreferences(mode: ReaderMode.horizontal);
    await start();
    reader.setQuickPreferences(true);
    expect(await reader.move('p1'), isTrue);
    expect(reader.preferences.mode, ReaderMode.vertical);
    expect(
      await reader.setPreferences(
        const ReaderPreferences(mode: ReaderMode.horizontal),
      ),
      isTrue,
    );
    expect(await reader.move('p0'), isTrue);
    expect(reader.preferences.mode, ReaderMode.horizontal);
    expect(repo.prefs['p0']!.mode, ReaderMode.vertical);
    expect(repo.prefs['p1']!.mode, ReaderMode.horizontal);
    expect(repo.writes.whereType<WritePackPreferences>(), isEmpty);
    reader.setQuickPreferences(false);
    expect(reader.preferences.mode, ReaderMode.vertical);
  });
  test('consecutive optimistic removals and undo each update the displayed range exactly once', () async {
    await start();
    repo.fileRelease = Completer<void>();
    final first = await cleanup.enqueue(repo.pack('p0'));
    expect(await reader.move('p1'), isTrue);
    final second = await cleanup.enqueue(repo.pack('p1'));
    expect(await reader.move('p2'), isTrue);
    expect(reader.displayCount, 168);
    expect(reader.displayPosition, 1);
    expect(reader.range!.candidateCount, 170);
    repo.fileRelease!.complete();
    await until(() => !first.working && !second.working);
    expect(reader.displayCount, 168);
    expect(reader.displayPosition, 1);
    expect(await cleanup.undo(first), isTrue);
    expect(reader.displayCount, 169);
    expect(reader.displayPosition, 2);
    expect(await cleanup.undo(second), isTrue);
    expect(reader.displayCount, 170);
    expect(reader.displayPosition, 3);
    expect(repo.scopes, 1);
  });

  test(
    'a definite rejection restores the count without selecting another pack',
    () async {
      await start();
      repo.rejectTrash = true;
      final observed = <int>[];
      reader.addListener(() => observed.add(reader.displayCount));
      final item = await cleanup.enqueue(repo.pack('p0'));
      await until(() => !item.working);
      expect(item.state, QuickRemovalState.failed);
      expect(observed, contains(169));
      expect(reader.displayCount, 170);
      expect(reader.displayPosition, 1);
      expect(reader.cursor!.packId, 'p0');
      expect(repo.unavailable, isEmpty);
    },
  );
}
