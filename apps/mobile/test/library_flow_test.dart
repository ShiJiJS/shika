import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';

void main() {
  late Directory directory;
  late FileStateStore store;
  late DemoLibraryRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'video-viewer-demo-test-',
    );
    store = FileStateStore(directory);
    repo = DemoLibraryRepository(store, latency: Duration.zero);
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    if (!target.startsWith(
      '$root${Platform.pathSeparator}video-viewer-demo-test-',
    )) {
      throw StateError('Refusing cleanup outside the test directory');
    }
    await directory.delete(recursive: true);
  });

  test(
    'directory/tag intersection, batch tags and round survive reopening',
    () async {
      await repo.setVideoTags({'v1', 'v2'}, {'散步'});
      await repo.setScope(
        VideoQuery(folder: '/videos/收集', tags: {'自然', '散步'}),
        order: PlayOrder.sequential,
      );
      expect(repo.query().map((v) => v.id).toSet(), {'v1', 'v2'});
      expect(repo.query().every((v) => v.tags.contains('花卉')), isTrue);
      final round = repo.snapshot.round;
      await repo.step(1);
      final reopened = DemoLibraryRepository(store, latency: Duration.zero);
      await reopened.initialize();
      expect(reopened.snapshot.round, round);
      expect(reopened.current!.id, round[1]);
      await reopened.setScope(VideoQuery(tags: {'自然', '庭院', '微距'}));
      expect(reopened.query(), isEmpty);
      expect(reopened.current, isNull);
      reopened.dispose();
    },
  );
  test(
    'delete is idempotent; undo restores exact item, tags, path and round',
    () async {
      final original = repo.current!;
      final round = repo.snapshot.round;
      await repo.deleteVideos({original.id}, requestId: 'same-request');
      final afterDelete = repo.current!.id;
      await repo.deleteVideos({original.id}, requestId: 'same-request');
      expect(repo.current!.id, afterDelete);
      await repo.undoDelete(operationId: 'same-request');
      await repo.undoDelete(operationId: 'same-request');
      expect(repo.current!.id, original.id);
      expect(repo.current!.path, original.path);
      expect(repo.current!.tags, original.tags);
      expect(repo.snapshot.round, round);
      final reopened = DemoLibraryRepository(store, latency: Duration.zero);
      await reopened.initialize();
      expect(reopened.current!.id, original.id);
      reopened.dispose();
    },
  );
  test('renaming tags preserves associations; deleting an active tag restarts the wider scope', () async {
    await repo.setScope(VideoQuery(tags: {'花卉'}));
    final ids = repo.query().map((v) => v.id).toSet();
    final paths = repo.snapshot.videos.map((v) => v.path).toList();
    await repo.editTag(original: '花卉', name: '花开');
    expect(repo.query().map((v) => v.id).toSet(), ids);
    expect(repo.snapshot.query.tags, {'花开'});
    await repo.editTag(original: '花开', delete: true);
    expect(repo.snapshot.query.tags, isEmpty);
    expect(repo.snapshot.round.toSet(), repo.query().map((v) => v.id).toSet());
    expect(repo.query().length, 6);
    expect(repo.snapshot.videos.map((v) => v.path).toList(), paths);
    expect(repo.snapshot.videos.length, 8);
  });
  test('failed delete and failed save retain position and metadata', () async {
    await repo.reset(scenario: DemoScenario.writeFailure);
    final before = repo.exportBackup();
    await expectLater(
      repo.deleteVideos({'v1'}, requestId: 'fail'),
      throwsA(isA<LibraryFailure>()),
    );
    expect(repo.current!.id, 'v1');
    expect(jsonDecode(repo.exportBackup())['data'], jsonDecode(before)['data']);
    await repo.reset(scenario: DemoScenario.storageFailure);
    await expectLater(
      repo.setVideoTags({'v1'}, {'庭院'}),
      throwsA(isA<LibraryFailure>()),
    );
    expect(repo.current!.tags, {'自然', '花卉'});
    final reopened = DemoLibraryRepository(store, latency: Duration.zero);
    await reopened.initialize();
    expect(reopened.current!.tags, {'自然', '花卉'});
    reopened.dispose();
  });
  test('backup round-trip validates before replace, remaps metadata and excludes secrets', () async {
    await repo.setVideoTags({'v1'}, {'庭院'});
    final backup = repo.exportBackup();
    final j = jsonDecode(backup) as Map;
    expect(j['data'].containsKey('connection'), isFalse);
    expect(backup.contains('headers'), isFalse);
    await expectLater(
      repo.restoreBackup('{bad', {}),
      throwsA(isA<LibraryFailure>()),
    );
    expect(repo.current!.tags.contains('庭院'), isTrue);
    await repo.editTag(name: '临时标签');
    await repo.restoreBackup(backup, {
      'r1': '/new-videos',
      'r2': '/new-collection',
    });
    expect(repo.snapshot.tags.contains('临时标签'), isFalse);
    expect(repo.current!.path.startsWith('/new-videos/'), isTrue);
    expect(
      File('${directory.path}/demo-before-restore.json').existsSync(),
      isTrue,
    );
    final reopened = DemoLibraryRepository(store, latency: Duration.zero);
    await reopened.initialize();
    expect(reopened.current!.tags.contains('庭院'), isTrue);
    reopened.dispose();
  });
  test(
    'root outage, external rename/move and missing recovery keep stable tags',
    () async {
      await repo.reset(scenario: DemoScenario.unavailable);
      expect(repo.snapshot.videos.length, 8);
      expect(repo.query().any((v) => v.rootId == 'r2'), isFalse);
      await expectLater(repo.refresh(), throwsA(isA<LibraryFailure>()));
      await repo.refresh();
      expect(repo.query().any((v) => v.rootId == 'r2'), isTrue);
      await repo.reset(scenario: DemoScenario.changedFiles);
      final tags = repo.current!.tags;
      await repo.refresh();
      expect(
        repo.snapshot.videos.firstWhere((v) => v.id == 'v1').path,
        '/videos/外部移动/花间微风_改名.mp4',
      );
      expect(repo.snapshot.videos.firstWhere((v) => v.id == 'v1').tags, tags);
      expect(repo.query().any((v) => v.id == 'v7'), isTrue);
      await repo.reset(scenario: DemoScenario.identityConflict);
      await repo.refresh();
      expect(
        repo.snapshot.videos.firstWhere((v) => v.id == 'v1').status,
        VideoStatus.missing,
      );
      expect(repo.snapshot.videos.firstWhere((v) => v.id == 'v1').tags, {
        '自然',
        '花卉',
      });
      expect(
        repo
            .query()
            .where((v) => ['v10', 'v11'].contains(v.id))
            .every((v) => v.tags.isEmpty),
        isTrue,
      );
    },
  );
  test(
    'restore conflicts preserve trash; scanning does not add to existing round',
    () async {
      await repo.reset(scenario: DemoScenario.conflict);
      expect(await repo.restoreVideos({'v8'}), isNotEmpty);
      expect(
        repo.snapshot.videos.firstWhere((v) => v.id == 'v8').status,
        VideoStatus.trash,
      );
      await repo.reset();
      final round = repo.snapshot.round;
      await repo.refresh();
      expect(repo.query().length, 7);
      expect(repo.snapshot.round, round);
      await repo.newRound();
      expect(repo.snapshot.round.toSet().length, 7);
    },
  );
}
