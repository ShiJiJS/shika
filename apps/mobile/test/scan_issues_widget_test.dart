import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/settings/scan_issues_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/request_scope.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/home.dart';
import 'package:shika/ui/preferences.dart';

import 'root_scan_widget_test.dart' show RootScanLibrary;
import 'support/root_scan_fixture.dart';

ScanReport report() => ScanReport({
  'id': 'round-1',
  'kind': 'scan',
  'status': 'completed',
  'result': {
    'root_scans': [
      {'id': 'A', 'status': 'partial', 'page_errors': 1},
      {
        'id': 'V',
        'status': 'partial',
        'counts': {'failed': 1},
      },
    ],
    'issues': [
      {'root_id': 'V', 'name': 'broken.mp4', 'code': 'probe_timeout'},
    ],
    'packs': {
      'issues': [
        {'root_id': 'A', 'name': '花园/001.jpg', 'code': 'image_probe_failed'},
        {'root_id': 'B', 'name': '另一个目录.jpg', 'code': 'permission_denied'},
      ],
    },
  },
});

class IssuesLibrary extends RootScanLibrary {
  Object owner = Object();
  RequestScope? request;
  Future<ScanReport> Function()? read;
  final reads = <String>[];
  @override
  Object get connectionIdentity => owner;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    'pack_reading_sessions',
  ]);
  @override
  Future<ScanReport> loadScanReport(String id, {RequestScope? cancel}) {
    reads.add(id);
    request = cancel;
    return read?.call() ?? Future.value(report());
  }
}

void main() {
  test('scan report separates video, packs and independent roots', () {
    final value = report();
    expect(value.root('A')!.pageErrors, 1);
    expect(value.issues(scanRoots[0]).single.name, 'broken.mp4');
    expect(value.issues(scanRoots[1]).single.name, '花园/001.jpg');
    expect(value.issues(scanRoots[2]).single.code, 'permission_denied');
  });

  Future<IssuesLibrary> host(
    WidgetTester t, {
    bool video = false,
    String? taskId = 'round-1',
    double scale = 1,
  }) async {
    final repo = IssuesLibrary();
    addTearDown(repo.dispose);
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ScanIssuesPage(
          repository: repo,
          root: scanRoots[video ? 0 : 1],
          initial: repo.libraryPreparation.value.rootProgress(
            video ? 'V' : 'A',
          ),
          taskId: taskId,
        ),
      ),
    );
    await t.pumpAndSettle();
    return repo;
  }

  for (final video in [false, true]) {
    testWidgets('file and reason visible for video=$video at large text', (
      t,
    ) async {
      final repo = await host(t, video: video, scale: 2);
      expect(repo.reads, ['round-1']);
      final name = find.text(video ? 'broken.mp4' : '花园/001.jpg');
      await t.ensureVisible(name);
      expect(name.hitTestable(), findsOneWidget);
      expect(find.text('另一个目录.jpg'), findsNothing);
      expect(
        find.textContaining(video ? '读取视频信息超时' : '图片无法解码'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'old record shows unavailable detail instead of invented success',
    (t) async {
      final repo = await host(t, taskId: null);
      expect(repo.reads, isEmpty);
      expect(find.textContaining('旧扫描记录没有任务明细'), findsOneWidget);
      expect(find.text('这次扫描没有记录到问题。'), findsNothing);
    },
  );

  testWidgets('retry and connection change cannot publish an old report', (
    t,
  ) async {
    final repo = await host(t);
    repo.read = () => Future.error(const LibraryFailure('连接超时，请重试'));
    await t.tap(find.byKey(const Key('scan-report-refresh')));
    await t.pumpAndSettle();
    expect(find.text('连接超时，请重试'), findsOneWidget);
    final late = Completer<ScanReport>();
    repo.read = () => late.future;
    await t.tap(find.byKey(const Key('scan-report-refresh')));
    await t.pump();
    repo.owner = Object();
    repo.notifyListeners();
    expect(repo.request!.cancelled, isTrue);
    late.complete(report());
    await t.pumpAndSettle();
    expect(find.textContaining('服务连接已变化'), findsOneWidget);
    expect(find.text('花园/001.jpg'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('abnormal status without file samples is not reported healthy', (
    t,
  ) async {
    final repo = await host(t);
    repo.read = () async => ScanReport({
      'id': 'round-1',
      'kind': 'scan',
      'status': 'completed',
      'result': {
        'roots': [
          {'id': 'A', 'status': 'partial'},
        ],
      },
    });
    await t.tap(find.byKey(const Key('scan-report-refresh')));
    await t.pumpAndSettle();
    expect(find.textContaining('服务端未提供具体文件的错误明细'), findsOneWidget);
    expect(find.text('这次扫描没有记录到问题。'), findsNothing);
  });

  testWidgets(
    'settings group media preferences and open scan details read-only',
    (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repo = IssuesLibrary(), preferences = UiPreferences();
      addTearDown(repo.dispose);
      addTearDown(preferences.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: LibraryHome(repository: repo, preferences: preferences),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('nav-settings')));
      await t.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byKey(const Key('settings-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(find.text('图包阅读偏好'), 250, scrollable: scroll);
      expect(
        t.getTopLeft(find.text('视频偏好')).dy,
        lessThan(t.getTopLeft(find.text('图包偏好')).dy),
      );
      expect(find.text('默认阅读方式 · 每个图包单独记忆'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('扫描进度与问题'),
        -250,
        scrollable: scroll,
      );
      await t.tap(find.text('扫描进度与问题'));
      await t.pumpAndSettle();
      final details = find.byKey(const Key('scan-root-details-A'));
      await t.ensureVisible(details);
      await t.tap(details);
      await t.pumpAndSettle();
      expect(repo.reads, ['round-1']);
      expect(repo.commands, isEmpty);
      expect(find.text('花园/001.jpg'), findsOneWidget);
    },
  );
}
