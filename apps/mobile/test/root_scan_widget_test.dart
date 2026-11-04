import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/settings/scan_progress_card.dart';
import 'package:shika/library/models.dart';
import 'package:shika/ui/home.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/preferences.dart';

import 'support/root_scan_fixture.dart';
import 'support/scan_details_fixture.dart';

class RootScanLibrary extends ScanDetailsLibrary {
  RootScanLibrary() {
    libraryPreparation.value = LibraryPreparation.fromJson(scanFixture());
  }
  final _scanSnapshot = LibrarySnapshot(
    videos: const [],
    roots: scanRoots,
    tags: const [],
    query: VideoQuery(),
    round: const [],
  );
  @override
  LibrarySnapshot get snapshot => _scanSnapshot;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    'root_scan_progress',
    'scoped_scans',
    'image_packs',
    'fixed_video_sessions',
    'versioned_video_queue',
    'video_entry_anchors',
  ]);
  final commands = <String>[];
  bool reject = false;
  @override
  Future<void> requestScan() async {
    commands.add('all');
  }

  @override
  Future<void> requestRootScan(String id) async {
    commands.add(id);
    if (reject) throw const LibraryFailure('此目录的扫描请求未确认，请查看进度');
    final body = scanFixture();
    (body['roots'] as List)[1]['queued_task_ids'] = ['next-A'];
    libraryPreparation.value = LibraryPreparation.fromJson(body);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final path = Platform.environment['LF8_SCAN_FONT'];
    if (path == null) return;
    final bytes = ByteData.sublistView(await File(path).readAsBytes());
    await Future.wait([
      (FontLoader('Roboto')..addFont(Future.value(bytes))).load(),
      (FontLoader('PaperSerif')
            ..addFont(rootBundle.load('assets/fonts/PaperSerif.ttf'))
            ..addFont(Future.value(bytes)))
          .load(),
      (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load(),
    ]);
  });
  final boundary = GlobalKey();
  Future<void> host(
    WidgetTester t,
    Widget child, {
    double width = 390,
    double height = 844,
    double scale = 1,
    bool dark = false,
    bool reduced = true,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    t.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduced);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? Paper.darkTheme : Paper.theme,
          home: child,
        ),
      ),
    );
    if (reduced) {
      await t.pumpAndSettle();
    } else {
      await t.pump(const Duration(milliseconds: 500));
    }
    expect(t.takeException(), isNull);
  }

  Future<void> shot(WidgetTester t, String name) async {
    final path = Platform.environment['LF8_SCAN_SHOTS'];
    if (path == null) return;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final img = await render.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      img.dispose();
    });
  }

  Widget card(
    LibraryPreparation state, {
    List<MediaRoot> roots = scanRoots,
    bool precise = true,
    bool scoped = true,
  }) => Scaffold(
    appBar: AppBar(title: const Text('媒体目录')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ScanProgressCard(
        state: state,
        roots: roots,
        precise: precise,
        scoped: scoped,
        busy: false,
        onScanAll: () {},
        onScanRoot: (_) {},
      ),
    ),
  );

  testWidgets(
    'real settings entry, root queue and return keep independent facts',
    (t) async {
      final repo = RootScanLibrary(), preferences = UiPreferences();
      addTearDown(() {
        repo.dispose();
        preferences.dispose();
      });
      await host(t, LibraryHome(repository: repo, preferences: preferences));
      expect(find.byKey(const Key('library-scan-notice')), findsOneWidget);
      await t.tap(find.text('查看进度'));
      await t.pumpAndSettle();
      expect(find.text('图包目录'), findsOneWidget);
      expect(find.text('已核对 600 / 600 个视频'), findsOneWidget);
      expect(find.text('已核对 40 / 40 张图片'), findsOneWidget);
      expect(find.text('已核对 63 张图片 · 已发现 180 张'), findsOneWidget);
      await shot(t, 'settings-entry');
      final action = find.byKey(const Key('scan-root-action-A'));
      await t.ensureVisible(action);
      await t.pumpAndSettle();
      await t.tap(action);
      await t.pumpAndSettle();
      expect(repo.commands, ['A']);
      expect(find.text('下一次扫描已排队'), findsOneWidget);
      expect(find.text('已核对 40 / 40 张图片'), findsOneWidget);
      expect(find.text('已核对 63 张图片 · 已发现 180 张'), findsOneWidget);
      expect(t.widget<TextButton>(action).onPressed, isNull);
      await t.pump(const Duration(seconds: 6));
      await t.ensureVisible(find.byKey(const Key('scan-root-A')));
      await t.pumpAndSettle();
      await shot(t, 'root-a-queued');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('nav-settings')), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('library-scan-notice')), findsOneWidget);
      expect(find.byKey(const Key('nav-browse')), findsNothing);
      expect(repo.commands, ['A']);
    },
  );

  testWidgets(
    'submission failure stays on the progress page without an all scan',
    (t) async {
      final repo = RootScanLibrary()..reject = true,
          preferences = UiPreferences();
      addTearDown(() {
        repo.dispose();
        preferences.dispose();
      });
      await host(t, LibraryHome(repository: repo, preferences: preferences));
      await t.tap(find.text('查看进度'));
      await t.pumpAndSettle();
      final action = find.byKey(const Key('scan-root-action-A'));
      await t.ensureVisible(action);
      await t.pumpAndSettle();
      await t.tap(action);
      await t.pumpAndSettle();
      expect(find.text('此目录的扫描请求未确认，请查看进度'), findsOneWidget);
      expect(repo.commands, ['A']);
      expect(find.text('已核对 40 / 40 张图片'), findsOneWidget);
      expect(find.byKey(const Key('library-preparation')), findsOneWidget);
    },
  );

  testWidgets(
    'unscanned sources can open progress without being labelled offline',
    (t) async {
      final repo = RootScanLibrary(), preferences = UiPreferences();
      repo.libraryPreparation.value = LibraryPreparation.fromJson({
        'ready': false,
        'scanning': false,
        'status': 'idle',
        'roots': [
          for (final root in scanRoots)
            {
              'id': root.id,
              'available': false,
              'last_scan': null,
              'scan': null,
            },
        ],
      });
      addTearDown(() {
        repo.dispose();
        preferences.dispose();
      });
      await host(t, LibraryHome(repository: repo, preferences: preferences));
      expect(find.text('部分目录暂无扫描明细'), findsOneWidget);
      await t.tap(find.text('查看进度'));
      await t.pumpAndSettle();
      expect(find.text('暂无扫描进度记录'), findsNWidgets(3));
      expect(find.text('目录暂不可用'), findsNothing);
      expect(find.textContaining('0 / 0'), findsNothing);
      expect(repo.commands, isEmpty);
    },
  );

  testWidgets(
    'legacy image progress is labelled as aggregate, not guessed per root',
    (t) async {
      final body = scanFixture();
      for (final root in body['roots'] as List) {
        final scan = root['scan'] as Map;
        scan.remove('progress');
        if (root['kind'] == 'pack') {
          scan.addAll(<String, Object?>{
            'status': 'discovering',
            'discovered': 0,
            'processed': 11,
          });
        }
      }
      await host(
        t,
        card(LibraryPreparation.fromJson(body), precise: false, scoped: false),
      );
      expect(find.text('本轮共核对 103 张图片 · 处理 2 个图包'), findsOneWidget);
      expect(find.text('已处理 11 个图包'), findsNWidgets(2));
      expect(find.text('此服务未提供该目录的图片进度'), findsNWidgets(2));
      expect(find.textContaining('/ 0'), findsNothing);
      expect(find.text('扫描此目录'), findsNothing);
    },
  );

  testWidgets(
    'offline, unknown, queued and paused roots do not invent completion',
    (t) async {
      final body = scanFixture();
      (body['roots'] as List)[1]['scan'] = null;
      (body['roots'] as List)[1]['queued_task_ids'] = ['new-A'];
      final roots = [
        ...scanRoots,
        const MediaRoot(
          'disabled',
          '暂时停用',
          '/paused',
          kind: MediaKind.pack,
          enabled: false,
        ),
      ];
      await host(
        t,
        card(LibraryPreparation.fromJson(body).offline(), roots: roots),
      );
      expect(find.text('进度暂未同步，正在重试'), findsOneWidget);
      expect(find.text('排队中'), findsOneWidget);
      expect(find.text('已停用'), findsOneWidget);
      expect(find.textContaining('0 / 0'), findsNothing);
      expect(find.text('已核对 63 张图片 · 已发现 180 张'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        t.widget<OutlinedButton>(find.byKey(const Key('scan-all'))).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'root errors retain partial numbers while other roots remain readable',
    (t) async {
      final body = scanFixture();
      final entries = body['roots'] as List;
      final a = entries[1]['scan'] as Map, b = entries[2]['scan'] as Map;
      a['status'] = 'partial';
      a['page_errors'] = 1;
      b['status'] = 'unavailable';
      b['error'] = 'root_unavailable';
      body['scanning'] = false;
      body['status'] = body['phase'] = 'completed';
      body['media']['pack']['scanning'] = false;
      await host(t, card(LibraryPreparation.fromJson(body)));
      expect(find.text('1 张图片无法读取'), findsOneWidget);
      expect(find.text('目录无法访问，请检查挂载或连接。'), findsOneWidget);
      expect(find.text('已核对 40 / 40 张图片'), findsOneWidget);
      expect(find.text('已核对 63 张图片 · 已发现 180 张'), findsOneWidget);
      expect(find.text('已核对 600 / 600 个视频'), findsOneWidget);
      await shot(t, 'partial-and-offline');
    },
  );

  testWidgets(
    'thumbnail warnings keep completion and are separate from source failures',
    (t) async {
      final body = scanFixture(running: false);
      final entry = (body['roots'] as List)[1];
      entry['scan']['counts']['thumbnail_failed'] = 2;
      final state = LibraryPreparation.fromJson(body);
      expect(state.rootProgress('A').needsAttention, true);
      await host(t, card(state));
      final a = find.byKey(const Key('scan-root-A'));
      expect(
        find.descendant(of: a, matching: find.text('扫描完成')),
        findsOneWidget,
      );
      expect(find.text('2 个缩略图待补充（不影响入库）'), findsOneWidget);
      expect(find.textContaining('读取失败'), findsNothing);
      expect(find.text('已核对 40 / 40 张图片'), findsOneWidget);
    },
  );

  testWidgets(
    'legacy type-level failures are retained without assigning them to a root',
    (t) async {
      final body = scanFixture(running: false);
      body['counts'] = <String, Object?>{
        'failed': 2,
        'thumbnail_failed': 5,
        'deferred': 1,
      };
      body['failure_reasons'] = <String, Object?>{'probe_timeout': 2};
      body['media']['pack']['counts']['failed_pages'] = 3;
      await host(
        t,
        card(LibraryPreparation.fromJson(body), precise: false, scoped: false),
      );
      expect(find.text('本轮 2 个视频信息读取失败'), findsOneWidget);
      expect(find.text('读取媒体信息超时 2 个'), findsOneWidget);
      expect(find.text('本轮 5 个缩略图待补充（不影响入库）'), findsOneWidget);
      expect(find.text('本轮 3 张图片无法读取'), findsOneWidget);
      expect(find.text('有目录需要检查'), findsOneWidget);
      await shot(t, 'legacy-type-warnings');
    },
  );

  testWidgets(
    'empty sources and image-less packs never render a zero denominator',
    (t) async {
      final body = scanFixture(running: false);
      for (final root in body['roots'] as List) {
        root['scan']['progress']['discovered'] = 0;
        root['scan']['progress']['processed'] = 0;
        if (root['kind'] == 'pack') {
          root['scan']['progress']['packs_discovered'] = root['id'] == 'A'
              ? 0
              : 1;
          root['scan']['progress']['packs_processed'] = root['id'] == 'A'
              ? 0
              : 1;
        }
      }
      final b = (body['roots'] as List)[2];
      b['scan']['status'] = 'partial';
      b['scan']['unreadable_packs'] = 1;
      body['media']['video']['indexed'] = 0;
      body['media']['pack']['indexed'] = 0;
      await host(t, card(LibraryPreparation.fromJson(body)));
      expect(find.text('未发现视频'), findsOneWidget);
      expect(find.text('未发现图包'), findsOneWidget);
      expect(find.text('未发现可检查的图片'), findsOneWidget);
      expect(find.textContaining('0 / 0'), findsNothing);
      await shot(t, 'empty-and-image-less');
    },
  );

  testWidgets(
    'a covered source identifies its owner and offers no misleading rescan',
    (t) async {
      final body = scanFixture();
      (body['roots'] as List).add(<String, Object?>{
        'id': 'alias',
        'scan': <String, Object?>{'status': 'covered', 'owner_root_id': 'V'},
      });
      await host(
        t,
        card(
          LibraryPreparation.fromJson(body),
          roots: [
            ...scanRoots,
            const MediaRoot('alias', '视频子目录', '/media/video/child'),
          ],
        ),
      );
      expect(find.text('随“视频收藏”扫描'), findsOneWidget);
      expect(find.byKey(const Key('scan-root-action-alias')), findsNothing);
      expect(find.textContaining('0 / 0'), findsNothing);
    },
  );

  for (final sample in [
    (390.0, 844.0, 1.0, false),
    (390.0, 844.0, 1.0, true),
    (320.0, 844.0, 2.0, false),
    (844.0, 390.0, 1.0, false),
  ]) {
    testWidgets('source progress layout $sample', (t) async {
      final roots = [
        scanRoots[0],
        scanRoots[1],
        MediaRoot(
          'B',
          '图包 B · 很长的目录名称也需要自然换行保留当前读取状态',
          '/media/b',
          kind: MediaKind.pack,
        ),
      ];
      await host(
        t,
        card(LibraryPreparation.fromJson(scanFixture()), roots: roots),
        width: sample.$1,
        height: sample.$2,
        scale: sample.$3,
        dark: sample.$4,
        reduced: false,
      );
      await shot(
        t,
        '${sample.$1.toInt()}-${sample.$2.toInt()}-${sample.$3}-${sample.$4}-top',
      );
      await t.ensureVisible(find.byKey(const Key('scan-all')));
      await t.pump(const Duration(milliseconds: 500));
      await shot(
        t,
        '${sample.$1.toInt()}-${sample.$2.toInt()}-${sample.$3}-${sample.$4}-bottom',
      );
      expect(t.takeException(), isNull);
    });
  }
}
