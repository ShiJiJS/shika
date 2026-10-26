import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/settings/archive_backup_page.dart';
import 'package:video_viewer/library/backup_document.dart';
import 'package:video_viewer/library/backup_file_picker.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/management_archives.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/request_scope.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/paper_management.dart';

import 'support/reveal_action.dart';

class _Files implements BackupArchiveFiles {
  _Files(this.document);
  final BackupDocument document;
  bool saved = false;
  int saveCalls = 0;
  @override
  Future<BackupDocument?> pick(
    BackupFileStore store, {
    required int maximumBytes,
    RequestScope? scope,
  }) async => document;
  @override
  Future<bool> save(BackupDocument document, {RequestScope? scope}) async {
    saveCalls++;
    return saved;
  }
}

class _Repository extends DemoLibraryRepository
    implements ManagementArchiveRepository {
  _Repository(this.document)
    : super(MemoryStateStore(), scenario: DemoScenario.empty);
  final BackupDocument document;
  int exports = 0, saved = 0, restores = 0, queries = 0;
  bool pending = false, fail = false, legacy = false, failRoots = false;
  int rootTotal = 27;
  Map<String, String?>? mappings;
  @override
  bool get archiveBackupsAvailable => true;
  ArchiveRestorePoint? point;
  int snapshotInspections = 0;
  @override
  Future<ArchiveRestorePoint?> latestArchiveRestorePoint() async => point;
  @override
  Future<ArchivePreview> inspectArchiveRestorePoint(
    ArchiveRestorePoint point,
  ) async {
    snapshotInspections++;
    return resumeArchivePreview();
  }

  @override
  int get archiveMaximumBytes => 64 * 1024 * 1024;
  @override
  bool get archivePreviewPending => true;
  @override
  bool get backupRestorePending => pending;
  @override
  Future<BackupFileStore> archiveFileStore() async => document.store;
  @override
  Future<ArchiveExport> exportArchive() async {
    exports++;
    return ArchiveExport('original', document);
  }

  @override
  Future<void> archiveSaved(String identity) async {
    saved++;
  }

  @override
  Future<ArchivePreview> inspectArchive(BackupDocument document) =>
      resumeArchivePreview();
  @override
  Future<ArchivePreview> resumeArchivePreview() async => ArchivePreview(
    taskId: 'preview-original',
    protocol: legacy ? 1 : 2,
    fileVersion: 2,
    fileSha256: document.sha256,
    bytes: document.bytes,
    rootsTotal: rootTotal,
    counts: {
      'videos': 42,
      'tags': 2,
      'packs': 27,
      'pack_pages': 99,
      'pack_tag_definitions': 3,
      'pack_progress': 4,
    },
  );
  @override
  Future<ArchiveRootPage> archiveRoots(
    ArchivePreview preview, {
    int offset = 0,
    int limit = 24,
  }) async => failRoots
      ? throw const LibraryFailure('目录分页暂时无法读取')
      : ArchiveRootPage(
          total: rootTotal,
          offset: offset,
          items: [
            for (var n = offset; n < (offset + limit).clamp(0, rootTotal); n++)
              ArchiveRoot.fromJson({
                'id': '$n',
                'name': '媒体目录$n',
                'original_path': '/原媒体/较长的图包目录名称/$n',
                'kind': n.isEven ? 'video' : 'pack',
                'suggested_path': '/当前/$n',
              }),
          ],
        );
  @override
  Future<void> restoreArchive(
    ArchivePreview preview,
    Map<String, String?> value,
  ) async {
    restores++;
    mappings = value;
    if (fail) throw const LibraryFailure('目录映射冲突，请修改后再恢复');
  }

  @override
  Future<void> reconcileBackupRestore() async {
    queries++;
    pending = false;
    notifyListeners();
  }
}

void main() {
  late Directory directory;
  late BackupDocument document;
  late _Repository repository;
  late _Files files;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archive-widget-');
    document = await BackupFileStore(
      directory,
      owner: 'isolated',
    ).capture(Stream.value([1, 2, 3]), maximumBytes: 100);
    repository = _Repository(document);
    files = _Files(document);
  });
  tearDown(() async {
    repository.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> show(
    WidgetTester t, {
    double width = 390,
    double height = 844,
    double scale = 1,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('备份与恢复')),
          body: ArchiveBackupPage(
            repository: repository,
            archives: repository,
            files: files,
            onOpenTasks: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> visible(WidgetTester t, Finder target) =>
      revealAction(t, target);

  for (final profile in [
    (390.0, 844.0, 1.0),
    (360.0, 740.0, 2.0),
    (844.0, 390.0, 1.0),
    (844.0, 390.0, 2.0),
  ]) {
    testWidgets(
      'short archive preview keeps its focused draft and cancels without restore $profile',
      (t) async {
        repository.rootTotal = 2;
        await show(t, width: profile.$1, height: profile.$2, scale: profile.$3);
        final open = find.byKey(const Key('archive-resume-preview'));
        await visible(t, open);
        await t.tap(open);
        await t.pumpAndSettle();
        expect(find.byType(SheetFrame), findsOneWidget);
        final field = find.byKey(const Key('archive-mapping-0'));
        await visible(t, field);
        await t.enterText(field, '/保留/输入');
        await t.showKeyboard(field);
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpAndSettle();
        expect(MediaQuery.viewInsetsOf(t.element(field)).bottom, 280);
        expect(
          t
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(t.widget<TextField>(field).controller!.text, '/保留/输入');
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        final submit = find.byKey(const Key('archive-restore-submit'));
        await visible(t, submit);
        expect(t.widget<FilledButton>(submit).onPressed, isNull);
        await visible(t, find.byKey(const Key('archive-restore-close')));
        await t.tap(find.byKey(const Key('archive-restore-close')));
        await t.pumpAndSettle();
        expect(repository.restores, 0);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('root page failure keeps the previous page and edited mapping', (
    t,
  ) async {
    await show(t);
    await visible(t, find.byKey(const Key('archive-resume-preview')));
    await t.tap(find.byKey(const Key('archive-resume-preview')));
    await t.pumpAndSettle();
    final first = find.byKey(const Key('archive-mapping-0'));
    await visible(t, first);
    await t.enterText(first, '/仍保留/本页');
    FocusManager.instance.primaryFocus?.unfocus();
    repository.failRoots = true;
    await visible(t, find.text('下一页'));
    await t.tap(find.text('下一页'));
    await t.pumpAndSettle();
    expect(find.text('目录分页暂时无法读取'), findsOneWidget);
    expect(find.text('媒体目录 · 已载入 24/27'), findsOneWidget);
    await visible(t, first);
    expect(t.widget<TextField>(first).controller!.text, '/仍保留/本页');
    expect(repository.restores, 0);
  });
  testWidgets(
    'restore point enters the mapping preview with confirmation off',
    (t) async {
      repository.point = ArchiveRestorePoint.fromJson({
        'restore_id': 'original-restore',
        'snapshot_id': 'original-snapshot',
        'kind': 'backup_snapshot_v2',
        'created_at': 1.25,
        'bytes': document.bytes,
        'file_sha256': document.sha256,
      }, owner: document.store.owner);
      await show(t, width: 360, scale: 2);
      await visible(t, find.byKey(const Key('archive-restore-point')));
      await t.tap(find.byKey(const Key('archive-restore-point')));
      await t.pumpAndSettle();
      expect(repository.snapshotInspections, 1);
      expect(repository.restores, 0);
      await visible(t, find.byKey(const Key('archive-confirm')));
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('archive-confirm')))
            .value,
        isFalse,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'saving cancellation retains original export and reports no success',
    (t) async {
      await show(t);
      await t.tap(find.byKey(const Key('archive-export')));
      await t.pumpAndSettle();
      expect(files.saveCalls, 1);
      expect(repository.saved, 0);
      expect(find.text('保存已取消，原导出任务已保留'), findsOneWidget);
      expect(find.text('已导出管理数据备份'), findsNothing);
      files.saved = true;
      await t.tap(find.byKey(const Key('archive-export')));
      await t.pumpAndSettle();
      expect(repository.saved, 1);
      expect(find.text('已导出管理数据备份'), findsOneWidget);
    },
  );
  for (final size in [(390.0, 1.0), (360.0, 2.0)]) {
    testWidgets(
      'root pagination keeps drafts and confirmation starts off ${size.$1}/${size.$2}',
      (t) async {
        await show(t, width: size.$1, scale: size.$2);
        await visible(t, find.byKey(const Key('archive-resume-preview')));
        await t.tap(find.byKey(const Key('archive-resume-preview')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('archive-counts')), findsOneWidget);
        await visible(t, find.byKey(const Key('archive-mapping-0')));
        await t.enterText(
          find.byKey(const Key('archive-mapping-0')),
          '/编辑后/保留',
        );
        t.testTextInput.hide();
        await t.pumpAndSettle();
        await visible(t, find.byKey(const Key('archive-confirm')));
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('archive-confirm')),
              )
              .value,
          isFalse,
        );
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('archive-confirm')),
              )
              .onChanged,
          isNull,
        );
        await visible(t, find.text('下一页'));
        await t.tap(find.text('下一页'));
        await t.pumpAndSettle();
        await visible(t, find.byKey(const Key('archive-mapping-26')));
        await t.enterText(find.byKey(const Key('archive-mapping-26')), '');
        t.testTextInput.hide();
        await t.pumpAndSettle();
        await visible(t, find.byKey(const Key('archive-confirm')));
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('archive-confirm')),
              )
              .value,
          isFalse,
        );
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const Key('archive-restore-submit')),
              )
              .onPressed,
          isNull,
        );
        await t.tap(find.byKey(const Key('archive-confirm')));
        await t.pumpAndSettle();
        await visible(t, find.byKey(const Key('archive-restore-submit')));
        await t.tap(find.byKey(const Key('archive-restore-submit')));
        await t.pumpAndSettle();
        expect(repository.restores, 1);
        expect(repository.mappings!.length, 27);
        expect(repository.mappings!['0'], '/编辑后/保留');
        expect(repository.mappings!['26'], isNull);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'mapping error keeps entered paths and checked confirmation on its original page',
    (t) async {
      repository.fail = true;
      await show(t);
      await visible(t, find.byKey(const Key('archive-resume-preview')));
      await t.tap(find.byKey(const Key('archive-resume-preview')));
      await t.pumpAndSettle();
      await visible(t, find.text('下一页'));
      await t.tap(find.text('下一页'));
      await t.pumpAndSettle();
      await visible(t, find.byKey(const Key('archive-mapping-24')));
      await t.enterText(find.byKey(const Key('archive-mapping-24')), '/修改/不丢失');
      t.testTextInput.hide();
      await t.pumpAndSettle();
      await visible(t, find.byKey(const Key('archive-confirm')));
      await t.tap(find.byKey(const Key('archive-confirm')));
      await t.pumpAndSettle();
      await visible(t, find.byKey(const Key('archive-restore-submit')));
      await t.tap(find.byKey(const Key('archive-restore-submit')));
      await t.pumpAndSettle();
      expect(repository.restores, 1);
      await visible(t, find.byKey(const Key('archive-mapping-24')));
      expect(
        t
            .widget<TextField>(find.byKey(const Key('archive-mapping-24')))
            .controller!
            .text,
        '/修改/不丢失',
      );
      await visible(t, find.byKey(const Key('archive-restore-error')));
      expect(find.text('目录映射冲突，请修改后再恢复'), findsOneWidget);
    },
  );
  testWidgets(
    'pending restore queries the original instead of opening import or export',
    (t) async {
      repository.pending = true;
      await show(t);
      expect(
        t.widget<PaperActionRow>(find.byKey(const Key('archive-export'))).onTap,
        isNull,
      );
      expect(
        t.widget<PaperActionRow>(find.byKey(const Key('archive-pick'))).onTap,
        isNull,
      );
      await visible(t, find.byKey(const Key('archive-query-restore')));
      await t.tap(find.byKey(const Key('archive-query-restore')));
      await t.pumpAndSettle();
      expect(repository.queries, 1);
      expect(repository.restores, 0);
      expect(repository.exports, 0);
    },
  );
}
