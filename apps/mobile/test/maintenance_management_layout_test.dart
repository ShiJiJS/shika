import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/settings/maintenance_tasks_page.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/maintenance_fixture.dart';
import 'support/reveal_action.dart';

void main() {
  for (final p in [
    (390.0, 844.0, 1.0),
    (360.0, 740.0, 2.0),
    (844.0, 390.0, 1.0),
    (844.0, 390.0, 2.0),
  ]) {
    testWidgets(
      'task body scrolls, page errors retain results and history stays read only $p',
      (t) async {
        final repo = TasksLibrary();
        await repo.initialize();
        t.view.physicalSize = Size(p.$1, p.$2);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = p.$3;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(body: MaintenanceTasksPage(repository: repo)),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        Future<void> tap(Finder f) async {
          await revealAction(t, f);
          await t.tap(f);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }

        await revealAction(
          t,
          find.byKey(const Key('maintenance-task-task-23')),
        );
        expect(
          find.text('请求超时不代表操作失败。查询已有任务结果，不重复提交删除或恢复。').hitTestable(),
          findsNothing,
        );
        await tap(find.byKey(const Key('tasks-next')));
        expect(repo.reads.last.offset, 24);
        final kept = find.byKey(const Key('maintenance-task-task-24'));
        await revealAction(t, kept);
        expect(kept, findsOneWidget);
        repo.failPage = true;
        await tap(find.byKey(const Key('tasks-refresh')));
        expect(find.text('任务暂时无法读取'), findsOneWidget);
        expect(repo.reads.last.offset, 24);
        await revealAction(t, kept);
        expect(kept, findsOneWidget);
        repo.failPage = false;
        await tap(find.byKey(const Key('tasks-refresh')));
        await tap(find.byKey(const Key('task-filter-historical')));
        await tap(find.byKey(const Key('maintenance-task-task-2')));
        expect(find.text('历史记录'), findsOneWidget);
        expect(find.textContaining('不重新执行原删除或恢复'), findsOneWidget);
        expect(find.text('重试原任务'), findsNothing);
        await tap(find.byTooltip('查询原结果'));
        expect(repo.queries, 0);
        await tap(find.byTooltip('返回操作任务'));
        expect(t.takeException(), isNull);
      },
    );
  }
}
