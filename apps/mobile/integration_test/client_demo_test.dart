import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/ui/home.dart';
import 'package:video_viewer/ui/sheets.dart';

class TestBackupFiles implements BackupFiles {
  TestBackupFiles(this.file);
  final File file;
  @override
  Future<bool> save(String text) async {
    await file.writeAsString(text, flush: true);
    return true;
  }

  @override
  Future<String?> open() async => file.readAsString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late DemoLibraryRepository repo;
  late Directory directory;
  late FileStateStore store;
  late TestBackupFiles files;

  Future<void> until(
    WidgetTester t,
    bool Function() condition, {
    String reason = 'UI state',
  }) async {
    final timeout = DateTime.now().add(const Duration(seconds: 25));
    while (!condition()) {
      if (DateTime.now().isAfter(timeout)) {
        fail('Timed out waiting for $reason');
      }
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pump(const Duration(milliseconds: 120));
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    // Aligning an already visible in-video control can scroll the PageView.
    if (finder.hitTestable().evaluate().isEmpty) await t.ensureVisible(finder);
    await t.tap(finder);
    await t.pump(const Duration(milliseconds: 300));
    await until(
      t,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      reason: 'operation completion',
    );
  }

  Future<void> nav(WidgetTester t, String name) =>
      tap(t, find.byKey(Key('nav-$name')));
  Future<void> textTap(WidgetTester t, String text) async {
    if (text == '演示场景') {
      await t.scrollUntilVisible(
        find.text(text),
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await until(t, () => find.text(text).evaluate().isNotEmpty, reason: text);
    await tap(t, find.text(text).last);
  }

  Future<void> start(
    WidgetTester t, {
    DemoScenario scenario = DemoScenario.normal,
  }) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    directory = await Directory.systemTemp.createTemp('video-viewer-client-');
    store = FileStateStore(directory);
    files = TestBackupFiles(File('${directory.path}/export.json'));
    repo = DemoLibraryRepository(store, scenario: scenario);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 300));
      repo.dispose();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    await repo.initialize();
    await t.pumpWidget(VideoViewerApp(repository: repo, backupFiles: files));
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> playerReady(WidgetTester t) => until(
    t,
    () =>
        t.widget<PageView>(find.byKey(const Key('video-stage'))).physics
            is! NeverScrollableScrollPhysics &&
        find.byType(VideoPlayer).evaluate().isNotEmpty &&
        t
            .widget<VideoPlayer>(find.byType(VideoPlayer).first)
            .controller
            .value
            .isInitialized,
    reason: 'decoded video',
  );
  Future<void> more(WidgetTester t, String action) async {
    await tap(t, find.byTooltip('更多'));
    await textTap(t, action);
  }

  testWidgets(
    'real video playback, swipe/backtrack, speed, seek and landscape return',
    (t) async {
      await start(t);
      await playerReady(t);
      final first = repo.current!.id;
      var controller = t
          .widget<VideoPlayer>(find.byType(VideoPlayer).first)
          .controller;
      expect(
        controller.value.size.height,
        greaterThan(controller.value.size.width),
      );
      await until(
        t,
        () => controller.value.position.inMilliseconds > 250,
        reason: 'playback advancing',
      );
      await tap(t, find.byKey(const Key('video-stage')));
      expect(controller.value.isPlaying, isFalse);
      await t.drag(
        find.byKey(const Key('video-gesture-surface')).last,
        const Offset(70, 0),
      );
      await t.pump(const Duration(milliseconds: 200));
      await t.drag(
        find.byKey(const Key('video-progress-touch')),
        const Offset(90, 0),
      );
      await t.pump(const Duration(milliseconds: 250));
      expect(controller.value.position.inMilliseconds, greaterThan(500));
      await tap(t, find.byTooltip('播放速度'));
      await textTap(t, '2.0×');
      expect(controller.value.playbackSpeed, 2.0);
      expect(repo.snapshot.position, 0);
      final seen = {first};
      for (var i = 0; i < 2; i++) {
        await t.fling(
          find.byKey(const Key('video-stage')),
          const Offset(0, -210),
          1200,
        );
        await until(
          t,
          () => repo.current != null && !seen.contains(repo.current!.id),
          reason: 'next video',
        );
        seen.add(repo.current!.id);
        await playerReady(t);
        expect(
          repo.snapshot.position,
          i + 1,
          reason:
              'One fling advances one page: ${repo.snapshot.round}, seen=$seen',
        );
      }
      expect(repo.current!.portrait, isFalse);
      final landscapeId = repo.current!.id;
      await t.fling(
        find.byKey(const Key('video-stage')),
        const Offset(0, 210),
        1200,
      );
      await until(
        t,
        () => repo.current!.id != landscapeId,
        reason: 'previous video',
      );
      expect(seen.contains(repo.current!.id), isTrue);
      await playerReady(t);
      await t.fling(
        find.byKey(const Key('video-stage')),
        const Offset(0, -210),
        1200,
      );
      await until(t, () => repo.current!.id == landscapeId);
      await playerReady(t);
      await textTap(t, '横屏');
      await until(
        t,
        () => t.view.physicalSize.width > t.view.physicalSize.height,
        reason: 'Android landscape orientation',
      );
      expect(find.byKey(const Key('fullscreen-exit')), findsOneWidget);
      await tap(t, find.byKey(const Key('fullscreen-exit')));
      await until(
        t,
        () => t.view.physicalSize.height > t.view.physicalSize.width,
        reason: 'portrait return',
      );
      expect(repo.current!.id, landscapeId);
      expect(find.byType(VideoPlayer), findsOneWidget);
      await finish(t);
    },
  );

  testWidgets(
    'batch tags, AND filtering, folder scope and reopening the same demo store',
    (t) async {
      await start(t);
      await nav(t, 'library');
      await textTap(t, '多选');
      await tap(t, find.byKey(const Key('tile-v1')));
      await tap(t, find.byKey(const Key('tile-v2')));
      await textTap(t, '打标签');
      await textTap(t, '散步');
      await textTap(t, '完成');
      await until(
        t,
        () => find.byType(TagEditor).evaluate().isEmpty,
        reason: 'tags saved',
      );
      expect(
        repo.snapshot.videos
            .where((v) => {'v1', 'v2'}.contains(v.id))
            .every((v) => v.tags.containsAll({'花卉', '散步'})),
        isTrue,
      );
      await nav(t, 'tags');
      await textTap(t, '新建标签');
      await t.enterText(find.byKey(const Key('tag-name')), '自然');
      await textTap(t, '保存');
      await until(t, () => find.text('标签名称不能为空或重复').evaluate().isNotEmpty);
      expect(find.text('自然'), findsWidgets);
      await t.enterText(find.byKey(const Key('tag-name')), '练习标签');
      await textTap(t, '保存');
      await until(
        t,
        () => find.byKey(const Key('tag-name')).evaluate().isEmpty,
      );
      await textTap(t, '自然');
      await tap(t, find.byTooltip('筛选视频'));
      await textTap(t, '花卉');
      await textTap(t, '应用筛选');
      await until(t, () => find.text('3 个视频').evaluate().isNotEmpty);
      await tap(t, find.byTooltip('选择文件夹'));
      for (final name in ['视频收藏', '收集', '花草', '竖版']) {
        await textTap(t, name);
      }
      await textTap(t, '使用此目录');
      await until(t, () => find.text('1 个视频').evaluate().isNotEmpty);
      expect(repo.query().single.id, 'v1');
      final scope = repo.snapshot.query.toJson();
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 300));
      repo.dispose();
      repo = DemoLibraryRepository(store);
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo, backupFiles: files));
      await t.pump(const Duration(milliseconds: 500));
      await nav(t, 'library');
      expect(find.text('1 个视频'), findsOneWidget);
      expect(repo.snapshot.query.toJson(), scope);
      await nav(t, 'tags');
      expect(find.text('练习标签'), findsOneWidget);
      await finish(t);
    },
  );

  testWidgets(
    'quick review, exact undo, backup file round-trip and confirmed permanent delete',
    (t) async {
      await start(t);
      await nav(t, 'library');
      await textTap(t, '快速整理');
      await textTap(t, '筛选');
      await textTap(t, '自然');
      await textTap(t, '全部方向');
      await textTap(t, '竖版');
      await textTap(t, '应用筛选');
      await until(t, () => repo.query().length == 2);
      final original = repo.current!;
      await textTap(t, '打标签');
      await textTap(t, '庭院');
      await textTap(t, '完成');
      await until(t, () => find.byType(TagEditor).evaluate().isEmpty);
      expect(repo.current!.tags.contains('庭院'), isTrue);
      await tap(t, find.byKey(const Key('quick-delete')));
      expect(repo.current!.id, isNot(original.id));
      await textTap(t, '撤销');
      expect(repo.current!.id, original.id);
      expect(repo.current!.path, original.path);
      await more(t, '返回日常浏览');
      expect(find.byKey(const Key('review-actions')), findsNothing);
      await nav(t, 'settings');
      await textTap(t, '备份与恢复');
      await textTap(t, '导出备份');
      expect(await files.file.exists(), isTrue);
      final backup = jsonDecode(await files.file.readAsString()) as Map;
      expect(backup['data'].containsKey('connection'), isFalse);
      await tap(t, find.byTooltip('返回设置'));
      await textTap(t, '标签');
      await textTap(t, '新建标签');
      await t.enterText(find.byKey(const Key('tag-name')), '恢复前临时');
      await textTap(t, '保存');
      await until(
        t,
        () => find.byKey(const Key('tag-name')).evaluate().isEmpty,
      );
      await nav(t, 'settings');
      await textTap(t, '备份与恢复');
      await textTap(t, '选择备份文件');
      await textTap(t, '恢复管理数据');
      expect(find.text('请确认替换现有管理数据'), findsOneWidget);
      await tap(t, find.byType(CheckboxListTile));
      await textTap(t, '恢复管理数据');
      await until(t, () => find.text('管理数据已恢复').evaluate().isNotEmpty);
      expect(repo.snapshot.tags.contains('恢复前临时'), isFalse);
      await tap(t, find.byTooltip('返回设置'));
      await textTap(t, '回收站');
      await tap(t, find.byType(CheckboxListTile).first);
      await textTap(t, '永久删除');
      await textTap(t, '取消');
      expect(repo.snapshot.videos.any((v) => v.id == 'v8'), isTrue);
      await textTap(t, '永久删除');
      await tap(t, find.widgetWithText(TextButton, '永久删除').last);
      await until(t, () => find.text('回收站是空的').evaluate().isNotEmpty);
      await finish(t);
    },
  );

  testWidgets(
    'operation failure retains current video; unavailable directory keeps missing records',
    (t) async {
      await start(t, scenario: DemoScenario.writeFailure);
      final id = repo.current!.id;
      await more(t, '进入快速整理');
      await tap(t, find.byKey(const Key('quick-delete')));
      expect(find.byKey(const Key('operation-error')), findsOneWidget);
      expect(repo.current!.id, id);
      expect(find.text('已移入回收站'), findsNothing);
      await nav(t, 'settings');
      await textTap(t, '演示场景');
      await textTap(t, '媒体目录不可用');
      await nav(t, 'settings');
      await textTap(t, '媒体目录');
      expect(find.textContaining('目录暂不可用'), findsOneWidget);
      expect(find.text('缺失视频'), findsOneWidget);
      expect(repo.snapshot.videos.length, 8);
      await textTap(t, '刷新媒体目录');
      expect(find.byKey(const Key('operation-error')), findsOneWidget);
      await textTap(t, '刷新媒体目录');
      expect(repo.snapshot.roots.every((r) => r.available), isTrue);
      await tap(t, find.byTooltip('返回设置'));
      await textTap(t, '演示场景');
      await textTap(t, '外部改名、移动与找回');
      await nav(t, 'settings');
      await textTap(t, '媒体目录');
      await textTap(t, '刷新媒体目录');
      expect(find.text('缺失视频'), findsNothing);
      expect(
        repo.snapshot.videos.firstWhere((v) => v.id == 'v1').path,
        '/videos/外部移动/花间微风_改名.mp4',
      );
      expect(repo.snapshot.videos.firstWhere((v) => v.id == 'v1').tags, {
        '自然',
        '花卉',
      });
      await finish(t);
    },
  );
  testWidgets(
    'connection errors, remembered connection and empty-library recovery',
    (t) async {
      await start(t);
      await nav(t, 'settings');
      await textTap(t, '服务连接');
      await t.enterText(find.byType(TextField).at(2), 'wrong');
      await tap(t, find.widgetWithText(FilledButton, '连接'));
      expect(find.text('访问口令不正确'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), 'unreachable');
      await t.enterText(find.byType(TextField).at(2), 'demo');
      await tap(t, find.widgetWithText(FilledButton, '连接'));
      expect(find.text('暂时无法连接服务，请检查地址和网络'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), 'demo-nas');
      await tap(t, find.widgetWithText(FilledButton, '连接'));
      await until(
        t,
        () => find.byKey(const Key('video-stage')).evaluate().isNotEmpty,
      );
      final reopened = DemoLibraryRepository(store);
      await reopened.initialize();
      expect(reopened.snapshot.address, 'demo-nas');
      expect(reopened.snapshot.connected, isTrue);
      reopened.dispose();
      await nav(t, 'settings');
      await textTap(t, '演示场景');
      await textTap(t, '空视频库');
      expect(find.text('视频库还是空的'), findsOneWidget);
      await nav(t, 'library');
      expect(find.text('0 个视频'), findsOneWidget);
      await nav(t, 'settings');
      await textTap(t, '演示场景');
      await textTap(t, '正常 / 复位');
      await playerReady(t);
      expect(repo.query().length, 6);
      await finish(t);
    },
  );
}
