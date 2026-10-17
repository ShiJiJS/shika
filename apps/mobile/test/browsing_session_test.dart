import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/ui/browsing_session.dart';

class SlowLibrary extends DemoLibraryRepository {
  SlowLibrary() : super(MemoryStateStore(), latency: Duration.zero);
  Completer<void>? navigation, deletion;
  Completer<void>? fileQuery;
  @override
  bool get fileOperationPending => fileQuery != null && !fileQuery!.isCompleted;
  @override
  Future<void> reconcileFileOperation() async {
    await fileQuery?.future;
  }

  bool failDelete = false;
  final moves = <String>[];
  final deletes = <Set<String>>[];
  @override
  Future<void> moveToVideo(String id) async {
    moves.add(id);
    await navigation?.future;
    final index = snapshot.round.indexOf(id);
    if (index >= 0) await step(index - snapshot.position);
  }

  @override
  Future<void> deleteVideos(
    Set<String> ids, {
    required String requestId,
  }) async {
    deletes.add({...ids});
    await deletion?.future;
    if (failDelete) throw const LibraryFailure('模拟拒绝删除');
    await super.deleteVideos(ids, requestId: requestId);
  }
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late SlowLibrary repo;
  late BrowsingSession browsing;
  setUp(() async {
    repo = SlowLibrary();
    await repo.initialize();
    await repo.setScope(VideoQuery(), order: PlayOrder.sequential);
    browsing = BrowsingSession(repo);
    await tick();
  });
  tearDown(() {
    browsing.dispose();
    repo.dispose();
  });

  test('repeated swipes select immediately while position acknowledgement is blocked', () async {
    final ids = browsing.snapshot.round;
    repo.navigation = Completer<void>();
    expect(browsing.step(1), isTrue);
    await tick();
    expect(repo.moves, [ids[1]]);
    expect(browsing.step(1), isTrue);
    expect(browsing.step(1), isTrue);
    expect(browsing.current!.id, ids[3]);
    expect(repo.current!.id, ids[0]);
    repo.navigation!.complete();
    await tick();
    await tick();
    expect(repo.moves, [ids[1], ids[3]]);
    expect(browsing.current!.id, ids[3]);
    expect(repo.current!.id, ids[3]);
  });

  test(
    'consecutive deletions and further swipes do not wait for a file receipt',
    () async {
      final ids = browsing.snapshot.round;
      repo.deletion = Completer<void>();
      final first = browsing.delete({ids[0]}, 'one');
      expect(browsing.current!.id, ids[1]);
      final second = browsing.delete({ids[1]}, 'two');
      expect(browsing.current!.id, ids[2]);
      expect(browsing.step(1), isTrue);
      expect(browsing.current!.id, ids[3]);
      await tick();
      expect(repo.deletes, [
        {ids[0]},
      ]);
      repo.deletion!.complete();
      await Future.wait([first, second]);
      await tick();
      expect(repo.deletes, [
        {ids[0]},
        {ids[1]},
      ]);
      expect(browsing.current!.id, ids[3]);
      expect(browsing.snapshot.round, isNot(contains(ids[0])));
      expect(browsing.snapshot.round, isNot(contains(ids[1])));
      expect(repo.current!.id, ids[3]);
    },
  );

  test('a rejected delete restores visibility without pulling the viewer backwards', () async {
    final ids = browsing.snapshot.round;
    repo.failDelete = true;
    final work = browsing.delete({ids.first}, 'rejected');
    expect(browsing.current!.id, ids[1]);
    await expectLater(work, throwsA(isA<LibraryFailure>()));
    expect(browsing.snapshot.round, contains(ids.first));
    expect(browsing.current!.id, ids[1]);
    expect(repo.query().map((v) => v.id), contains(ids.first));
  });

  test(
    'explicit undo follows the restored item with original tags and path',
    () async {
      final original = browsing.current!;
      await browsing.delete({original.id}, 'undoable');
      await repo.undoDelete(operationId: repo.snapshot.lastDelete!.id);
      browsing.followRepository();
      expect(browsing.current!.id, original.id);
      expect(browsing.current!.path, original.path);
      expect(browsing.current!.tags, original.tags);
    },
  );
}
