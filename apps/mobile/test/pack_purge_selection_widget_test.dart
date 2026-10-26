import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_trash_page.dart';
import 'package:video_viewer/features/packs/pack_purge_selection_page.dart';
import 'package:video_viewer/features/settings/maintenance_tasks_page.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/pack_purge_fixture.dart';
import 'support/maintenance_fixture.dart';

import 'support/reveal_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final path = Platform.environment['LF6_CJK_FONT'];
    if (path == null) return;
    final bytes = ByteData.sublistView(await File(path).readAsBytes());
    final body = FontLoader('Roboto')..addFont(Future.value(bytes));
    final title = FontLoader('PaperSerif')
      ..addFont(rootBundle.load('assets/fonts/PaperSerif.ttf'))
      ..addFont(Future.value(bytes));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([body.load(), title.load(), icons.load()]);
  });
  final boundary = GlobalKey();
  Future<void> host(
    WidgetTester t,
    Widget child, {
    double width = 390,
    double scale = 1,
  }) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      t.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: Paper.theme,
          home: Scaffold(body: SafeArea(child: child)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await revealAction(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> shot(WidgetTester t, String name) async {
    final directory = Platform.environment['LF7_SELECTION_SHOTS'];
    if (directory == null) return;
    // Capture the stable page after its transient result notice has expired.
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final sample in [(390.0, 1.0), (360.0, 2.0)]) {
    testWidgets(
      '1027 choice survives leaving; only explicit 1000 delete and next 27 need fresh review ${sample.$1}/${sample.$2}',
      (t) async {
        final repo = PurgeLibrary(count: 1027);
        addTearDown(repo.dispose);
        await repo.initialize();
        await host(
          t,
          PackTrashPage(repository: repo, active: true),
          width: sample.$1,
          scale: sample.$2,
        );
        await tap(t, find.byKey(const Key('pack-trash-select-all')));
        await tap(t, find.byKey(const Key('pack-trash-permanent')));
        expect(repo.preparations.single, hasLength(1000));
        await tap(t, find.text('取消').last);
        expect(repo.physicalPosts, isEmpty);
        await tap(t, find.byKey(const Key('pack-trash-saved-purge')));
        expect(find.text('1027 个未提交'), findsOneWidget);
        await shot(t, 'saved-${sample.$1.toInt()}-${sample.$2.toInt()}');
        await tap(t, find.byKey(const Key('purge-selection-next')));
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('pack-purge-submit')))
              .onPressed,
          isNull,
        );
        await tap(t, find.byKey(const Key('pack-purge-confirmation')));
        await tap(t, find.byKey(const Key('pack-purge-submit')));
        expect(repo.physicalPosts, hasLength(1));
        expect(find.text('27 个未提交'), findsOneWidget);
        await shot(t, 'remaining-${sample.$1.toInt()}-${sample.$2.toInt()}');
        final draft = (await PackPurgeSelections(
          repo.createPackFiles(),
        ).list()).single;
        expect(draft.batches.single.command.targets, hasLength(1000));
        final remaining = draft.remaining;
        await tap(t, find.byKey(const Key('purge-selection-next')));
        expect(repo.preparations.last, remaining);
        expect(find.text('27 个图包 · 81 张图片'), findsOneWidget);
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('pack-purge-submit')))
              .onPressed,
          isNull,
        );
        await shot(t, 'next-review-${sample.$1.toInt()}-${sample.$2.toInt()}');
        await tap(t, find.text('取消').last);
        expect(repo.physicalPosts, hasLength(1));
        expect(remaining.every(repo.records.containsKey), isTrue);
        await tap(t, find.byTooltip('返回回收站'));
        await tap(t, find.byKey(const Key('pack-trash-saved-purge')));
        expect(find.text('27 个未提交'), findsOneWidget);
        expect(repo.physicalPosts, hasLength(1));
      },
    );
  }
  testWidgets(
    'task entry opens unsubmitted choice without querying or deleting; historical only shows in historical filter',
    (t) async {
      final repo = TasksLibrary();
      addTearDown(repo.dispose);
      await repo.initialize();
      final saved = await PackPurgeSelections(repo.createPackFiles())
          .save(['trash-0', 'trash-1']);
      repo.localReceipts = [
        MaintenanceReceipt(
          id: 'saved',
          requestId: saved.id,
          title: '图包删除选择 · 2 个未提交',
          source: MaintenanceReceiptSource.purgeSelection,
          kind: 'purge_selection',
          purgeSelectionId: saved.id,
        ),
      ];
      await host(t, MaintenanceTasksPage(repository: repo));
      await tap(t, find.byKey(const Key('task-receipt-saved')));
      expect(find.text('2 个未提交'), findsOneWidget);
      expect(repo.queries, 0);
      expect(repo.preparations, isEmpty);
      expect(repo.physicalPosts, isEmpty);
      await tap(t, find.byTooltip('返回回收站'));
      await repo.journal.historicalPurgeSelections('trash-fixture');
      repo.localReceipts = [
        MaintenanceReceipt(
          id: 'saved',
          requestId: saved.id,
          title: '图包删除选择 · 2 个未提交',
          source: MaintenanceReceiptSource.purgeSelection,
          kind: 'purge_selection',
          purgeSelectionId: saved.id,
          historical: true,
        ),
      ];
      await tap(t, find.byKey(const Key('task-filter-attention')));
      expect(find.byKey(const Key('task-receipt-saved')), findsNothing);
      await tap(t, find.byKey(const Key('task-filter-historical')));
      await tap(t, find.byKey(const Key('task-receipt-saved')));
      expect(find.byKey(const Key('purge-selection-next')), findsNothing);
      expect(find.textContaining('历史选择：管理数据已恢复'), findsOneWidget);
      expect(repo.physicalPosts, isEmpty);
    },
  );
  testWidgets(
    'discard removes choice after confirmation while unknown file command survives',
    (t) async {
      final repo = PurgeLibrary()..loseAfter = true;
      addTearDown(repo.dispose);
      await repo.initialize();
      final files = repo.createPackFiles(),
          choices = PackPurgeSelections(repo.createPackFiles());
      final saved = await choices.save(['trash-0', 'trash-1']);
      // An accepted command loses its response, independently of this page.
      await repo.createPackPurge().prepare('prepare', ['trash-0', 'trash-1']);
      final command = PackFileCommand.permanent(
        'unknown',
        planId: 'plan',
        digest: purgeHash,
        trashIds: saved.ids,
        imageCount: 6,
        selectionId: saved.id,
      );
      try {
        await files.send(command);
      } catch (_) {
        /* recorded unknown response */
      }
      expect((await files.pending()).single.requestId, 'unknown');
      await host(
        t,
        PackPurgeSelectionPage(repository: repo, selectionId: saved.id),
      );
      await tap(t, find.byKey(const Key('purge-selection-discard')));
      await tap(t, find.text('取消').last);
      expect(await choices.list(), hasLength(1));
      await tap(t, find.byKey(const Key('purge-selection-discard')));
      await tap(t, find.byKey(const Key('purge-selection-discard-confirm')));
      expect(await choices.list(), isEmpty);
      expect((await files.pending()).single.requestId, 'unknown');
      expect(repo.physicalPosts, hasLength(1));
    },
  );
}
