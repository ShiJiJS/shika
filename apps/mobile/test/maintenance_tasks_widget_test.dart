import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/settings/maintenance_tasks_page.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';

import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'support/maintenance_fixture.dart';

void main() {
  late TasksLibrary repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = TasksLibrary();
    await repo.initialize();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> host(
    WidgetTester t,
    double width,
    double scale, {
    Future<bool> Function(String)? save,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 740);
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
          body: SafeArea(
            child: MaintenanceTasksPage(repository: repo, saveBackup: save),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder target) async {
    if (target.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        target,
        400,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 60,
      );
    }
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await Scrollable.ensureVisible(t.element(target), alignment: .5);
    await t.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await t.tap(target);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  testWidgets('unreadable local receipts do not become an empty task list', (
    t,
  ) async {
    repo.rows = [];
    repo.failPending = true;
    await host(t, 390, 1);
    expect(find.text('本机回执无法读取'), findsOneWidget);
    expect(find.text('暂无操作任务'), findsNothing);
    expect(find.text('服务端共 0 条任务记录'), findsOneWidget);
  });

  for (final sample in [(390.0, 1.0), (360.0, 2.0)]) {
    testWidgets(
      'task pagination and historical read-only detail ${sample.$1}/${sample.$2}',
      (t) async {
        await host(t, sample.$1, sample.$2);
        await tap(t, find.byKey(const Key('tasks-next')));
        expect(repo.reads.last.offset, 24);
        await tap(t, find.byKey(const Key('task-filter-historical')));
        await tap(t, find.byKey(const Key('maintenance-task-task-2')));
        expect(find.text('历史记录'), findsOneWidget);
        expect(find.textContaining('不重新执行原删除或恢复'), findsOneWidget);
        expect(find.text('重试原任务'), findsNothing);
        await tap(t, find.byTooltip('查询原结果'));
        expect(repo.queries, 0);
        await tap(t, find.byTooltip('返回操作任务'));
      },
    );
    testWidgets(
      'unknown pending request and independent metadata error ${sample.$1}/${sample.$2}',
      (t) async {
        repo.localReceipts = [
          const MaintenanceReceipt(
            id: 'pack:unknown',
            requestId: 'unknown',
            title: '恢复图包',
            source: MaintenanceReceiptSource.pack,
            kind: 'restore',
          ),
        ];
        repo.failPage = true;
        await host(t, sample.$1, sample.$2);
        expect(find.text('暂无操作任务'), findsNothing);
        expect(find.text('任务暂时无法读取'), findsOneWidget);
        await tap(t, find.byKey(const Key('task-receipt-pack:unknown')));
        expect(repo.queries, 1);
        expect(repo.localReceipts.length, 1);
        expect(find.textContaining('未找到原请求，未重新提交'), findsOneWidget);
      },
    );
    testWidgets(
      'original backup download cancel/save and stale connection ${sample.$1}/${sample.$2}',
      (t) async {
        var accept = false;
        final saved = <String>[];
        await host(
          t,
          sample.$1,
          sample.$2,
          save: (text) async {
            saved.add(text);
            return accept;
          },
        );
        await tap(t, find.byKey(const Key('maintenance-task-task-1')));
        await tap(t, find.byKey(const Key('task-download-backup')));
        expect(repo.downloads, 1);
        expect(repo.saved, 0);
        accept = true;
        await tap(t, find.byKey(const Key('task-download-backup')));
        expect(saved, ['backup-task-1', 'backup-task-1']);
        expect(repo.saved, 1);
        repo.replaceConnection();
        await t.pumpAndSettle();
        expect(find.textContaining('服务连接或管理数据已变化'), findsOneWidget);
        expect(find.byKey(const Key('task-download-backup')), findsNothing);
      },
    );
  }
  testWidgets(
    'task members paginate through real viewport instead of a cached prefix',
    (t) async {
      repo.memberCount = 27;
      final raw = taskSummary('members')
        ..addAll({'total': 27, 'processed': 27, 'succeeded': 27});
      repo.rows = [MaintenanceTask(raw)];
      await host(t, 360, 2);
      await tap(t, find.byKey(const Key('maintenance-task-members')));
      await tap(t, find.text('全部'));
      await tap(t, find.byKey(const Key('task-items-next')));
      expect(find.text('海边散步图包 24'), findsOneWidget);
      expect(find.text('海边散步图包 26'), findsOneWidget);
      expect(find.text('共 27 项'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'approved settings exposes the task entry with other preferences retained',
    (t) async {
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await t.pumpAndSettle();
      await tap(t, find.byKey(const Key('nav-settings')));
      await tap(t, find.text('操作任务'));
      expect(find.byKey(const Key('task-family')), findsOneWidget);
      await tap(t, find.byTooltip('返回设置'));
      await t.scrollUntilVisible(
        find.text('准备相邻视频'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('准备相邻视频'), findsOneWidget);
      expect(find.text('备份与恢复'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
}
