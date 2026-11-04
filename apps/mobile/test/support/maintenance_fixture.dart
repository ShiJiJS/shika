import 'dart:async';

import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';

import 'pack_purge_fixture.dart' show PurgeLibrary;

typedef TaskJson = Map<String, dynamic>;
TaskJson taskSummary(
  String id, {
  String kind = 'pack_restore',
  String state = 'completed',
}) {
  final family = kind == 'scan'
      ? 'scan'
      : kind.startsWith('pack_')
      ? 'pack'
      : kind.startsWith('backup_')
      ? 'backup'
      : 'video';
  return {
    'id': id,
    'kind': kind,
    'status': state == 'processing'
        ? 'running'
        : state == 'historical'
        ? 'interrupted'
        : ['failed', 'attention'].contains(state)
        ? 'failed'
        : 'completed',
    'phase': state,
    'family': family,
    'state': state,
    'historical': state == 'historical',
    'needs_attention': state == 'attention',
    'created_at': 1792886000.0,
    'finished_at': state == 'processing' ? null : 1792886100.0,
    'error': null,
    'total': 1,
    'processed': state == 'processing' ? 0 : 1,
    'succeeded': ['completed', 'historical'].contains(state) ? 1 : 0,
    'failed': ['failed', 'partial', 'attention'].contains(state) ? 1 : 0,
    'pages_total': kind == 'pack_permanent' ? 3 : null,
    'pages_deleted': kind == 'pack_permanent'
        ? state == 'completed'
              ? 3
              : 2
        : null,
    'pages_pending': kind == 'pack_permanent' && state == 'attention'
        ? 1
        : null,
    'pack_total': kind == 'scan' ? 27 : null,
    'pack_processed': kind == 'scan' ? 20 : null,
  };
}

class TasksLibrary extends PurgeLibrary {
  TasksLibrary() {
    rows = [
      for (var i = 0; i < 29; i++)
        MaintenanceTask(
          taskSummary(
            'task-$i',
            kind: i == 0
                ? 'scan'
                : i == 1
                ? 'backup_export'
                : i == 2
                ? 'permanent'
                : 'pack_restore',
            state: i == 0
                ? 'processing'
                : i == 2
                ? 'historical'
                : 'completed',
          ),
        ),
    ];
  }
  late List<MaintenanceTask> rows;
  List<MaintenanceReceipt> localReceipts = const [];
  final reads = <({int offset, String family, String state})>[];
  int queries = 0, downloads = 0, saved = 0;
  int memberCount = 1;
  bool failPending = false;
  Completer<void>? pageGate;
  @override
  ServiceCapabilities get capabilities =>
      ServiceCapabilities([...super.capabilities.values, 'maintenance_tasks']);
  @override
  MaintenanceTaskCatalog createMaintenanceTasks() => FakeTaskCatalog(this);
}

class FakeTaskCatalog implements MaintenanceTaskCatalog {
  FakeTaskCatalog(this.repo) : owner = repo.owner;
  final TasksLibrary repo;
  final Object owner;
  bool disposed = false;
  @override
  bool get isCurrent => !disposed && identical(owner, repo.owner);
  @override
  Future<CatalogPage<MaintenanceTask>> page({
    int offset = 0,
    int limit = 24,
    String family = 'all',
    String state = 'all',
  }) async {
    repo.reads.add((offset: offset, family: family, state: state));
    if (repo.pageGate != null) await repo.pageGate!.future;
    if (repo.failPage) throw const LibraryFailure('任务暂时无法读取');
    final values = repo.rows
        .where(
          (t) =>
              (family == 'all' || t.family == family) &&
              (state == 'all' ||
                  state == 'attention' &&
                      [
                        'attention',
                        'partial',
                        'interrupted',
                        'failed',
                      ].contains(t.state) ||
                  state == t.state),
        )
        .toList();
    return CatalogPage(
      items: values.skip(offset).take(limit),
      total: values.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<MaintenanceTask> task(String id) async =>
      repo.rows.firstWhere((t) => t.id == id);
  @override
  Future<List<MaintenanceReceipt>> pending() async {
    if (repo.failPending) throw const LibraryFailure('本机回执无法读取');
    return repo.localReceipts;
  }

  @override
  Future<MaintenanceTask?> reconcile(MaintenanceReceipt receipt) async {
    repo.queries++;
    if (receipt.taskId == null) return null;
    repo.localReceipts = repo.localReceipts
        .where((v) => v.id != receipt.id)
        .toList();
    return task(receipt.taskId!);
  }

  @override
  Future<CatalogPage<MaintenanceItem>> items(
    String id, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  }) async => CatalogPage(
    items: [
      for (
        var i = offset;
        !unfinished && i < repo.memberCount && i < offset + limit;
        i++
      )
        MaintenanceItem({
          'id': 'member-$i',
          'name': '海边散步图包 $i',
          'path': '/packs/海边散步/$i',
          'outcome': 'succeeded',
          'phase': 'committed',
          'error': null,
        }),
    ],
    total: unfinished ? 0 : repo.memberCount,
    offset: offset,
    limit: limit,
  );
  @override
  Future<String> downloadBackup(String id) async {
    repo.downloads++;
    return 'backup-$id';
  }

  @override
  Future<void> backupSaved(String id) async {
    repo.saved++;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
