import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_file_action.dart';
import 'package:video_viewer/features/packs/pack_trash_page.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/pack_purge_fixture.dart';

import 'support/reveal_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PurgeLibrary repo;
  setUp(() async {
    repo = PurgeLibrary(count: 2);
    await repo.initialize();
  });
  setUpAll(() async {
    final path = Platform.environment['LF6_CJK_FONT'];
    if (path != null) {
      final font = ByteData.sublistView(await File(path).readAsBytes());
      final body = FontLoader('Roboto')..addFont(Future.value(font));
      final title = FontLoader('PaperSerif')
        ..addFont(rootBundle.load('assets/fonts/PaperSerif.ttf'))
        ..addFont(Future.value(font));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([body.load(), title.load(), icons.load()]);
    }
  });
  final boundary = GlobalKey();
  Future<void> host(WidgetTester t, double width, double scale) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      t.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: SafeArea(
              child: PackTrashPage(repository: repo, active: true),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder target) async {
    await revealAction(t, target);
    await t.tap(target);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> shot(WidgetTester t, String name) async {
    final directory = Platform.environment['LF6_WIDGET_SHOTS'];
    if (directory == null) return;
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final sample in [(390.0, 1.0), (360.0, 2.0)]) {
    testWidgets(
      'review, cancel, exact images and explicit deletion ${sample.$1}/${sample.$2}',
      (t) async {
        await host(t, sample.$1, sample.$2);
        await tap(t, find.byKey(const Key('pack-trash-item-trash-0')));
        await tap(t, find.byKey(const Key('pack-trash-permanent')));
        final submit = find.byKey(const Key('pack-purge-submit'));
        expect(t.widget<FilledButton>(submit).onPressed, isNull);
        expect(repo.physicalPosts, isEmpty);
        await shot(t, 'purge-review-${sample.$1.toInt()}-${sample.$2.toInt()}');
        await tap(t, find.text('查看图包和图片清单'));
        await tap(t, find.text('海边散步图包 trash-0'));
        expect(find.text('0.jpg'), findsOneWidget);
        expect(find.text('2.jpg'), findsOneWidget);
        await tap(t, find.byTooltip('关闭面板').last);
        await tap(t, find.byTooltip('关闭面板').last);
        await tap(t, find.text('取消').last);
        expect(repo.physicalPosts, isEmpty);
        await tap(t, find.byKey(const Key('pack-trash-permanent')));
        expect(t.widget<FilledButton>(submit).onPressed, isNull);
        await tap(t, find.byKey(const Key('pack-purge-confirmation')));
        expect(t.widget<FilledButton>(submit).onPressed, isNotNull);
        await tap(t, submit);
        expect(repo.physicalPosts.length, 1);
        expect(
          find.byKey(const Key('pack-purge-result-count')),
          findsOneWidget,
        );
        expect(find.text('已确认删除 3/3 张'), findsOneWidget);
        await shot(t, 'purge-result-${sample.$1.toInt()}-${sample.$2.toInt()}');
        await tap(t, find.text('关闭').last);
        expect(find.byKey(const Key('pack-trash-item-trash-0')), findsNothing);
        expect(
          find.byKey(const Key('pack-trash-item-trash-1')),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'lost accepted deletion reopens read-only; original request executes once',
    (t) async {
      repo.loseAfter = true;
      await host(t, 390, 1);
      await tap(t, find.byKey(const Key('pack-trash-item-trash-0')));
      await tap(t, find.byKey(const Key('pack-trash-permanent')));
      await tap(t, find.byKey(const Key('pack-purge-confirmation')));
      await tap(t, find.byKey(const Key('pack-purge-submit')));
      expect(find.text('查询原结果'), findsOneWidget);
      expect(repo.physicalPosts.length, 1);
      await tap(t, find.text('稍后处理'));
      await tap(t, find.byKey(const Key('pack-trash-pending')));
      expect(repo.physicalPosts.length, 1);
      expect(find.text('已确认删除 3/3 张'), findsOneWidget);
    },
  );
  testWidgets(
    'expired review cannot submit and stale missing pending check never auto-POSTs',
    (t) async {
      repo.expired = true;
      await host(t, 390, 1);
      await tap(t, find.byKey(const Key('pack-trash-item-trash-0')));
      await tap(t, find.byKey(const Key('pack-trash-permanent')));
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('pack-purge-submit')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('清单已过期'), findsOneWidget);
      await tap(t, find.text('取消').last);
      final command = PackFileCommand.permanent(
        'missing',
        planId: 'plan',
        digest: purgeHash,
        trashIds: ['trash-0'],
        imageCount: 3,
      );
      final context = t.element(find.byType(PackTrashPage));
      final pending = showPackFileAction(
        context,
        files: repo.createPackFiles(),
        command: command,
        title: '查询原请求',
        confirm: false,
        readOnly: true,
      );
      await t.pumpAndSettle();
      expect(repo.physicalPosts, isEmpty);
      expect(find.textContaining('未找到原请求'), findsOneWidget);
      await tap(t, find.text('稍后处理'));
      await pending;
    },
  );
  testWidgets(
    'partially purged row describes only remaining recoverable images',
    (t) async {
      final original = repo.records['trash-0']!;
      repo.records['trash-0'] = PackTrashItem(
        id: original.id,
        operationId: original.operationId,
        originalPath: original.originalPath,
        deletedAt: original.deletedAt,
        pageCount: 3,
        pack: original.pack,
        purgedPages: 2,
        permanentOperationId: 'old-purge',
      );
      await host(t, 360, 2);
      expect(find.text('已有 2 张永久删除，恢复仅限剩余 3 张'), findsOneWidget);
      expect(find.text('查看原永久删除结果'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
