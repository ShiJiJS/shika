import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/settings/maintenance_tasks_page.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/maintenance_fixture.dart';
import 'support/purge_history_fixture.dart';

class HistoryLibrary extends TasksLibrary {
  HistoryLibrary() {
    rows = [MaintenanceTask(historyTaskJson())];
    memberCount = 27;
  }
  final readers = <FakePurgeHistory>[];
  bool supported = true;
  @override
  MaintenanceTaskCatalog createMaintenanceTasks() => HistoryCatalog(this);
  void invalidate() {
    for (final reader in readers) {
      reader.active = false;
    }
    notifyListeners();
  }
}

class HistoryCatalog extends FakeTaskCatalog
    implements HistoricalPurgeCatalog, GraphTaskCatalog {
  HistoryCatalog(HistoryLibrary super.repo);
  @override
  bool get supportsPurgeHistory => (repo as HistoryLibrary).supported;
  @override
  MaintenanceTaskCatalog forTask(MaintenanceTask task) => this;
  @override
  PurgeHistoryDetails purgeHistory(MaintenanceTask task) {
    final reader = FakePurgeHistory(repo, task);
    (repo as HistoryLibrary).readers.add(reader);
    return reader;
  }
}

void main() {
  late HistoryLibrary repo;
  setUp(() async {
    repo = HistoryLibrary();
    await repo.initialize();
  });
  tearDown(() => repo.dispose());
  Future<void> host(WidgetTester t, {double scale = 1}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(360, 740);
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      t.view.resetDevicePixelRatio();
      t.view.resetPhysicalSize();
      t.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        home: Scaffold(
          body: SafeArea(child: MaintenanceTasksPage(repository: repo)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder target, {double delta = 400}) async {
    if (target.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        target,
        delta,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 80,
      );
    }
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  Future<void> detail(WidgetTester t) async =>
      tap(t, find.byKey(Key('maintenance-task-${repo.rows.single.id}')));

  testWidgets(
    'historical task opens paged original plan/files with no execution affordance at large text',
    (t) async {
      await host(t, scale: 2);
      await detail(t);
      await tap(t, find.byKey(const Key('task-history-purge-review')));
      expect(find.text('历史明细'), findsOneWidget);
      await tap(t, find.byKey(const Key('purge-history-next')));
      expect(repo.readers.single.requests, contains('review:24'));
      expect(find.text('原图包 26'), findsOneWidget);
      await tap(t, find.byKey(const Key('purge-history-previous')));
      await tap(
        t,
        find.byKey(const Key('purge-history-pack-trash-0')),
        delta: -400,
      );
      expect(find.text('原图片清单'), findsOneWidget);
      await tap(t, find.byKey(const Key('purge-history-next')));
      expect(repo.readers.single.requests, contains('images:trash-0:100'));
      await t.scrollUntilVisible(
        find.text('127 · 0127.png'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('127 · 0127.png'), findsOneWidget);
      expect(find.text('确认永久删除'), findsNothing);
      expect(find.text('重试原任务'), findsNothing);
      await tap(t, find.byTooltip('返回历史清单'));
      expect(repo.readers.single.disposed, isFalse);
      await tap(t, find.byTooltip('返回任务详情'));
      expect(repo.readers.single.disposed, isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'historical result error, all pages and directory filter stay read-only',
    (t) async {
      await host(t);
      await detail(t);
      await tap(t, find.byKey(const Key('task-history-image-results')));
      expect(find.text('当时没有读取或删除权限'), findsOneWidget);
      expect(find.text('原图包 0 · 0101.png'), findsOneWidget);
      await tap(t, find.byKey(const Key('purge-history-outcome-false')));
      await tap(t, find.byKey(const Key('purge-history-next')));
      expect(repo.readers.single.requests, contains('steps:24:false:all'));
      await tap(t, find.byKey(const Key('purge-history-kind')), delta: -400);
      await tap(t, find.text('只看目录').last);
      expect(repo.readers.single.requests.last, 'steps:0:false:directory');
      await t.scrollUntilVisible(
        find.byKey(const Key('purge-history-total')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('共 27 项'), findsOneWidget);
      expect(find.text('重试原任务'), findsNothing);
      expect(find.text('确认永久删除'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'failed next page retains original members and position for explicit retry',
    (t) async {
      await host(t);
      await detail(t);
      await tap(t, find.byKey(const Key('task-history-purge-review')));
      final reader = repo.readers.single;
      reader.fail = true;
      await tap(t, find.byKey(const Key('purge-history-next')));
      expect(reader.requests.last, 'review:24');
      await t.scrollUntilVisible(
        find.byKey(const Key('purge-history-error')),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('原清单暂时无法读取'), findsOneWidget);
      expect(find.text('原图包 23'), findsOneWidget);
      expect(find.text('原图包 24'), findsNothing);
      expect(
        t
            .widget<TextButton>(find.byKey(const Key('purge-history-previous')))
            .onPressed,
        isNull,
      );
      reader.fail = false;
      await tap(t, find.byTooltip('查询原历史记录'));
      expect(reader.requests.last, 'review:0');
      expect(find.text('原清单暂时无法读取'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('a late history page cannot replace an invalidated connection', (
    t,
  ) async {
    await host(t);
    await detail(t);
    await tap(t, find.byKey(const Key('task-history-purge-review')));
    final reader = repo.readers.single;
    reader.gate = Completer();
    await t.tap(find.byTooltip('查询原历史记录'));
    await t.pump();
    repo.invalidate();
    await t.pump();
    reader.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('服务连接或管理数据已变化，请返回后重新打开原任务'), findsOneWidget);
    expect(find.byKey(const Key('purge-history-pack-trash-0')), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'preview history uses the same original plan reader and legacy service remains explicit',
    (t) async {
      repo.rows = [
        MaintenanceTask(historyTaskJson(kind: 'pack_purge_preview')),
      ];
      await host(t);
      await detail(t);
      await tap(t, find.byKey(const Key('task-history-purge-review')));
      expect(find.byKey(const Key('purge-history-results')), findsNothing);
      await tap(t, find.byTooltip('返回任务详情'));
      await tap(t, find.byTooltip('返回操作任务'));
      repo.supported = false;
      await detail(t);
      expect(find.byKey(const Key('task-history-purge-review')), findsNothing);
      await t.scrollUntilVisible(
        find.text('当前服务尚未提供这份历史图片明细，请升级服务后重新打开。'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('当前服务尚未提供这份历史图片明细，请升级服务后重新打开。'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
