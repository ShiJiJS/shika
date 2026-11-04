import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/settings/maintenance_task_session.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';

import 'support/maintenance_fixture.dart';

void main() {
  test('catalog pagination/filter and local-read failure retain valid server records', () async {
    final repo = TasksLibrary();
    final s = MaintenanceTaskSession(repo);
    addTearDown(s.dispose);
    await s.load();
    expect(s.total, 29);
    expect(s.items.length, 24);
    await s.load(start: 24);
    expect(s.items.length, 5);
    expect(s.canNext, isFalse);
    repo.failPending = true;
    await s.load(kind: 'pack', start: 0);
    expect(s.items.length, 24);
    expect(s.pendingError, contains('回执'));
    expect(s.error, isEmpty);
    final before = s.items;
    repo.failPage = true;
    await s.load();
    expect(s.items, before);
    expect(s.error, contains('无法读取'));
    expect(s.hasLoaded, isTrue);
  });
  test(
    'unknown request remains pending without mutation or invented task id',
    () async {
      final repo = TasksLibrary()
        ..localReceipts = [
          const MaintenanceReceipt(
            id: 'unknown',
            requestId: 'r',
            title: '恢复图包',
            source: MaintenanceReceiptSource.pack,
            kind: 'restore',
          ),
        ];
      final s = MaintenanceTaskSession(repo);
      addTearDown(s.dispose);
      await s.load();
      expect(await s.query(s.pending.single), isNull);
      expect(s.message, contains('未重新提交'));
      expect(repo.localReceipts.length, 1);
      expect(repo.queries, 1);
    },
  );
  test(
    'connection replacement discards late task and local receipt reads',
    () async {
      final repo = TasksLibrary()..pageGate = Completer<void>();
      final s = MaintenanceTaskSession(repo);
      addTearDown(s.dispose);
      final work = s.load();
      repo.replaceConnection();
      repo.pageGate!.complete();
      await work;
      expect(s.items, isEmpty);
      expect(s.pending, isEmpty);
      expect(s.live, isFalse);
      expect(s.error, contains('重新打开'));
      expect(s.loading, isFalse);
    },
  );
  test('partial pages and historical labels cannot be presented as successful deletion', () {
    final partial = MaintenanceTask(
      taskSummary('partial', kind: 'pack_permanent', state: 'partial'),
    );
    expect(partial.progressLabel, contains('2/3'));
    expect(partial.stateLabel, '部分完成');
    final bad = taskSummary('bad', kind: 'pack_permanent')
      ..['pages_deleted'] = 2;
    expect(() => MaintenanceTask(bad), throwsA(isA<LibraryFailure>()));
    final old = MaintenanceTask(
      taskSummary('history', kind: 'restore', state: 'historical'),
    );
    expect(old.historical, isTrue);
    expect(old.stateLabel, '历史记录');
  });
}
