import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_trash_session.dart';

import 'support/pack_trash_fixture.dart';

void main() {
  test('whole filtered membership survives paging and exclusions; restore uses trash IDs', () async {
    final repo = TrashLibrary(count: 1027);
    final view = PackTrashSession(repo);
    addTearDown(() {
      view.dispose();
      repo.dispose();
    });
    await view.load();
    expect(view.items.length, 24);
    expect(view.total, 1027);
    await view.selectAll();
    expect(view.selection.ids.length, 1027);
    view.toggle('trash-0');
    await view.load(start: 24);
    expect(view.selection.ids.length, 1026);
    expect(view.offset, 24);
    await view.restoreSelected();
    expect(repo.posts.map((r) => (r['trash_ids'] as List).length), [1000, 26]);
    expect(
      repo.posts.every(
        (r) => (r['trash_ids'] as List).every(
          (id) => (id as String).startsWith('trash-'),
        ),
      ),
      isTrue,
    );
    expect(repo.records.keys, ['trash-0']);
    expect(view.selection.ids, isEmpty);
    expect(await view.files.pending(), isEmpty);
    expect(view.offset, 0);
    expect(view.total, 1);
  });
  for (final after in [false, true]) {
    test(
      'unknown ${after ? 'committed' : 'unaccepted'} first batch stops subsequent POSTs and retains original intent',
      () async {
        final repo = TrashLibrary(count: 1001);
        final session = PackTrashSession(repo);
        addTearDown(() {
          session.dispose();
          repo.dispose();
        });
        await session.load();
        await session.selectAll();
        repo.loseBefore = !after;
        repo.loseAfter = after;
        await session.restoreSelected();
        expect(repo.posts.length, 1);
        expect(session.selection.ids.length, 1001);
        expect(session.pending.length, 1);
        final command = session.pending.single;
        expect((command.body['trash_ids'] as List).length, 1000);
        final task = await session.files.resolve(command, submit: false);
        expect(repo.posts.length, 1);
        if (after) {
          await session.accept(command, task!);
          expect(session.selection.ids.length, 1);
          await session.restoreSelected();
          expect(repo.posts.length, 2);
          expect(repo.records, isEmpty);
        } else {
          expect(task, isNull);
          expect(await session.files.canResend(command), isTrue);
          await session.restoreSelected();
          expect(repo.posts.length, 1);
        }
      },
    );
  }
  test(
    'partial results keep only failed IDs selected and preserve per-row errors',
    () async {
      final repo = TrashLibrary(count: 3);
      final session = PackTrashSession(repo);
      addTearDown(() {
        session.dispose();
        repo.dispose();
      });
      await session.load();
      await session.selectAll();
      repo.failing.add('trash-1');
      await session.restoreSelected();
      expect(session.selection.ids, {'trash-1'});
      expect(session.failures.keys, ['trash-1']);
      expect(session.items.single.pack.progress!.offsetRatio, .37);
      expect(session.items.single.pack.tags, {'保留'});
      repo.failing.clear();
      await session.restoreSelected();
      expect((repo.posts.last['trash_ids'] as List), ['trash-1']);
      expect(repo.records, isEmpty);
    },
  );
  test('new query rejects delayed pages and delayed all-selection without widening scope', () async {
    final repo = TrashLibrary();
    final view = PackTrashSession(repo);
    addTearDown(() {
      view.dispose();
      repo.dispose();
    });
    repo.pageGates['图包1'] = Completer<void>();
    final old = view.load(query: '图包1');
    await view.load(query: '图包2');
    repo.pageGates['图包1']!.complete();
    await old;
    expect(view.search, '图包2');
    expect(view.items.every((v) => v.pack.name.contains('图包2')), isTrue);
    repo.selectionGate = Completer<Set<String>>();
    final all = view.selectAll();
    await view.load(query: '图包0');
    repo.selectionGate!.complete({'wrong'});
    await all;
    expect(view.selection.ids, isEmpty);
    expect(view.items.single.pack.name, '图包0');
  });
  test('connection change ignores late accepted result while keeping the command for the original connection', () async {
    final repo = TrashLibrary(count: 3);
    final session = PackTrashSession(repo);
    addTearDown(() {
      session.dispose();
      repo.dispose();
    });
    await session.load();
    await session.selectAll();
    repo.fileStarted = Completer<void>();
    repo.fileRelease = Completer<void>();
    final work = session.restoreSelected();
    await repo.fileStarted!.future;
    repo.replaceConnection();
    repo.fileRelease!.complete();
    await work;
    expect(session.items, isEmpty);
    expect(session.lastResult, isNull);
    expect(session.error, contains('服务连接'));
    expect(await repo.journal.pending('trash-fixture'), hasLength(1));
  });
  test('hiding the view stops remaining batches and leaves accepted work queryable', () async {
    final repo = TrashLibrary(count: 1001);
    final session = PackTrashSession(repo);
    addTearDown(() {
      session.dispose();
      repo.dispose();
    });
    await session.load();
    await session.selectAll();
    repo.fileStarted = Completer<void>();
    repo.fileRelease = Completer<void>();
    final work = session.restoreSelected();
    await repo.fileStarted!.future;
    session.setActive(false);
    repo.fileRelease!.complete();
    await work;
    expect(repo.posts.length, 1);
    expect(session.selection.ids.length, 1001);
    expect(session.pending, hasLength(1));
    session.setActive(true);
    await session.load();
    expect(session.total, 1);
    expect(session.pending, hasLength(1));
  });
}
