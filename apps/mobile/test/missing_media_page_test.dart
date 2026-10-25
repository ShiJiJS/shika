import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/settings/missing_media_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/maintenance_fixture.dart';

class MissingLibrary extends TasksLibrary {
  final missing = <String>{for (var i = 0; i < 27; i++) 'p$i'};
  final pendingCleanup = <MissingCleanupReceipt>[];
  int cleanupPosts = 0, cleanupQueries = 0, removes = 0;
  bool lose = false;
  final offsets = <int>[];
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    'pack_missing_cleanup',
  ]);
  @override
  PackMissingCatalog createPackMissing() => MissingCatalog(this);
  MaintenanceTask summary() => MaintenanceTask({
    ...taskSummary('cleanup', kind: 'pack_forget_missing'),
    'total': 27,
    'processed': 27,
    'succeeded': 27,
    'failed': 0,
    'skipped': 0,
  });
}

class MissingCatalog implements PackMissingCatalog {
  MissingCatalog(this.repo) : owner = repo.owner;
  final MissingLibrary repo;
  final Object owner;
  bool disposed = false;
  @override
  bool get isCurrent => !disposed && identical(owner, repo.owner);
  @override
  Future<CatalogPage<LibraryPack>> page({
    int offset = 0,
    int limit = 24,
  }) async {
    repo.offsets.add(offset);
    return CatalogPage(
      items: repo.missing
          .skip(offset)
          .take(limit)
          .map(
            (id) => LibraryPack(
              id: id,
              rootId: 'root',
              path: '/packs/$id',
              name: '缺失图包$id',
              pageCount: 3,
              readableCount: 0,
              contentVersion: 1,
              status: 'missing',
              createdAt: 1,
              tagNames: {'tag': '原标签'},
            ),
          ),
      total: repo.missing.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<List<MissingCleanupReceipt>> pending() async =>
      List.of(repo.pendingCleanup);
  @override
  Future<MaintenanceTask> submit(String requestId) async {
    repo.cleanupPosts++;
    if (repo.lose) {
      repo.pendingCleanup.add(MissingCleanupReceipt(requestId));
      throw const LibraryFailure('回执丢失');
    }
    repo.missing.clear();
    final task = repo.summary();
    repo.rows = [task];
    return task;
  }

  @override
  Future<MaintenanceTask?> query(String requestId) async {
    repo.cleanupQueries++;
    repo.pendingCleanup.clear();
    repo.missing.clear();
    final task = repo.summary();
    repo.rows = [task];
    return task;
  }

  @override
  Future<void> removeLocalReceipt(String requestId) async {
    repo.removes++;
    repo.pendingCleanup.removeWhere((r) => r.requestId == requestId);
  }

  @override
  void cancelPages() {}
  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  late MissingLibrary repo;
  setUp(() async {
    repo = MissingLibrary();
    await repo.initialize();
  });
  tearDown(() => repo.dispose());
  Future<void> tap(WidgetTester t, Finder target) async {
    for (final direction in [1, -1]) {
      for (var i = 0; target.evaluate().isEmpty && i < 60; i++) {
        await t.drag(
          find.byType(Scrollable).hitTestable().last,
          Offset(0, -240.0 * direction),
        );
        await t.pumpAndSettle();
      }
      if (target.evaluate().isNotEmpty) break;
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

  Future<void> host(WidgetTester t, double width, double scale) async {
    t.view.physicalSize = Size(width, 740);
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
        home: MissingMediaPage(repository: repo),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, find.byKey(const Key('missing-kind-pack')));
  }

  for (final (width, scale) in [(390.0, 1.0), (360.0, 2.0)]) {
    testWidgets(
      'typed missing pagination, cancel and original cleanup lookup $width/$scale',
      (t) async {
        await host(t, width, scale);
        expect(find.text('缺失图包p0'), findsOneWidget);
        await tap(t, find.text('下一页'));
        expect(repo.offsets.last, 24);
        expect(find.text('缺失图包p0'), findsNothing);
        await tap(t, find.byKey(const Key('clear-missing-kind')));
        await tap(t, find.text('取消'));
        expect(repo.cleanupPosts, 0);
        repo.lose = true;
        await tap(t, find.byKey(const Key('clear-missing-kind')));
        await tap(t, find.byKey(const Key('missing-confirm')));
        expect(repo.cleanupPosts, 1);
        expect(repo.pendingCleanup, hasLength(1));
        await tap(t, find.text('查询原清理请求'));
        expect(repo.cleanupPosts, 1);
        expect(repo.cleanupQueries, 1);
        expect(repo.pendingCleanup, isEmpty);
        expect(find.byKey(const Key('missing-cleanup-task')), findsOneWidget);
        expect(find.text('共 0 个缺失图包'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'removing the local pending entry is explicit and never submits cleanup',
    (t) async {
      repo.pendingCleanup.add(const MissingCleanupReceipt('unknown'));
      await host(t, 390, 1);
      await tap(t, find.text('移除本机入口'));
      await tap(t, find.byKey(const Key('missing-confirm')));
      expect(repo.removes, 1);
      expect(repo.cleanupPosts, 0);
      expect(repo.missing, hasLength(27));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}
