import 'models.dart';
import 'pack_models.dart';
import 'pack_files.dart';

Never _bad() => throw const LibraryFailure('操作任务数据不完整，请重新读取');
String _text(Object? value, [int max = 128]) =>
    value is String && value.isNotEmpty && value.length <= max ? value : _bad();
int? _count(Object? value) => value == null
    ? null
    : value is int && value >= 0
    ? value
    : _bad();
bool _flag(Object? value) => value is bool ? value : _bad();
double _time(Object? value) =>
    value is num && value.isFinite && value >= 0 && value <= 8640000000000
    ? value.toDouble()
    : _bad();

class MaintenanceTask {
  MaintenanceTask(Map<String, dynamic> raw)
    : id = _text(raw['id']),
      kind = _text(raw['kind']),
      status = _text(raw['status']),
      phase = _text(raw['phase']),
      family = _text(raw['family']),
      state = _text(raw['state']),
      historical = _flag(raw['historical']),
      needsAttention = _flag(raw['needs_attention']),
      createdAt = _time(raw['created_at']),
      finishedAt = raw['finished_at'] == null
          ? null
          : _time(raw['finished_at']),
      error = raw['error'] == null ? null : _text(raw['error'], 4096),
      total = _count(raw['total']),
      processed = _count(raw['processed']),
      succeeded = _count(raw['succeeded']),
      failed = _count(raw['failed']),
      stopped = _count(raw['stopped']),
      remaining = _count(raw['remaining']),
      rootIssues = _count(raw['root_issues']),
      pagesTotal = _count(raw['pages_total']),
      pagesDeleted = _count(raw['pages_deleted']),
      pagesPending = _count(raw['pages_pending']),
      packTotal = _count(raw['pack_total']),
      packProcessed = _count(raw['pack_processed']) {
    if (!['scan', 'video', 'pack', 'backup', 'other'].contains(family) ||
        ![
          'historical',
          'processing',
          'attention',
          'partial',
          'completed',
          'failed',
          'interrupted',
        ].contains(state) ||
        historical != (state == 'historical') ||
        (needsAttention && !historical && state != 'attention') ||
        (state == 'completed' &&
            (status != 'completed' ||
                (failed ?? 0) > 0 ||
                (rootIssues ?? 0) > 0)) ||
        (kind == 'pack_permanent' &&
            state == 'completed' &&
            (pagesDeleted == null ||
                pagesTotal == null ||
                pagesDeleted != pagesTotal)) ||
        (state == 'processing' && !['queued', 'running'].contains(status)) ||
        (total != null && processed != null && processed! > total!) ||
        (kind == 'pack_restore_plan' &&
            (stopped == null ||
                remaining == null ||
                total == null ||
                processed == null ||
                succeeded == null ||
                failed == null ||
                processed != succeeded! + failed! ||
                processed! + stopped! + remaining! != total)) ||
        (pagesTotal != null &&
            (pagesDeleted ?? 0) + (pagesPending ?? 0) > pagesTotal!) ||
        (packTotal != null &&
            packProcessed != null &&
            packProcessed! > packTotal!)) {
      _bad();
    }
  }
  final String id, kind, status, phase, family, state;
  final bool historical, needsAttention;
  final double createdAt;
  final double? finishedAt;
  final String? error;
  final int? total,
      processed,
      succeeded,
      failed,
      stopped,
      remaining,
      rootIssues,
      pagesTotal,
      pagesDeleted,
      pagesPending,
      packTotal,
      packProcessed;
  String get title =>
      const {
        'scan': '同步外部变更',
        'trash': '视频移入回收站',
        'restore': '恢复视频',
        'permanent': '永久删除视频',
        'undo': '撤销视频移除',
        'pack_trash': '图包移入回收站',
        'pack_restore': '恢复图包',
        'pack_undo': '撤销图包移除',
        'pack_permanent': '永久删除图包图片',
        'pack_purge_preview': '核对图片删除清单',
        'pack_restore_plan': '批量恢复图包',
        'backup_export': '导出管理备份',
        'backup_inspect': '校验管理备份',
        'backup_restore': '恢复管理数据',
      }[kind] ??
      '其它操作';
  String get stateLabel => const {
    'historical': '历史记录',
    'processing': '处理中',
    'attention': '结果待核对',
    'partial': '部分完成',
    'completed': '已完成',
    'failed': '未完成',
    'interrupted': '已中断，待核对',
  }[state]!;
  String get progressLabel {
    if (kind == 'pack_permanent' && pagesTotal != null) {
      return pagesDeleted == null
          ? '删除结果待核对'
          : '已确认删除 $pagesDeleted/$pagesTotal 张${(pagesPending ?? 0) > 0 ? ' · $pagesPending 张待核对' : ''}';
    }
    final unit = family == 'pack'
        ? '个图包'
        : ['video', 'scan'].contains(family)
        ? '个视频'
        : '项';
    final lines = <String>[];
    if (total != null && processed != null) {
      lines.add('${family == 'scan' ? '视频核对' : '已处理'} $processed/$total $unit');
    }
    if (family == 'scan' && packTotal != null && packProcessed != null) {
      lines.add('图包核对 $packProcessed/$packTotal 个');
    }
    if ((rootIssues ?? 0) > 0) lines.add('$rootIssues 个目录未完成核对');
    if (succeeded != null || failed != null) {
      lines.add(
        [
          if (succeeded != null) '完成 $succeeded',
          if (failed != null)
            '${kind == 'pack_restore_plan' ? '失败' : '未完成'} $failed',
        ].join(' · '),
      );
    }
    if (kind == 'pack_restore_plan') {
      if ((stopped ?? 0) > 0) lines.add('已停止 $stopped 个尚未开始的图包');
      if ((remaining ?? 0) > 0) lines.add('还有 $remaining 个等待后续批次');
    }
    return lines.join('\n');
  }
}

class MaintenanceItem {
  MaintenanceItem(Map<String, dynamic> raw)
    : id = _text(raw['id']),
      name = _text(raw['name'], 4096),
      path = raw['path'] is String && (raw['path'] as String).length <= 4096
          ? raw['path'] as String
          : _bad(),
      outcome = _text(raw['outcome']),
      phase = _text(raw['phase']),
      error = raw['error'] == null ? null : _text(raw['error'], 4096);
  final String id, name, path, outcome, phase;
  final String? error;
  String get label => outcome == 'succeeded'
      ? '已完成'
      : outcome == 'stopped'
      ? '已停止，未执行恢复'
      : outcome == 'pending'
      ? '等待处理'
      : '未完成，请核对原结果';
}

enum MaintenanceReceiptSource { pack, video, backup, restorePlan }

/// A scoped local intent; the gateway binds it to an issued object and request.
class MaintenanceReceipt {
  const MaintenanceReceipt({
    required this.id,
    required this.requestId,
    required this.title,
    required this.source,
    required this.kind,
    this.taskId,
    this.packCommand,
    this.restoreCommand,
  });
  final String id, requestId, title, kind;
  final MaintenanceReceiptSource source;
  final String? taskId;
  final PackFileCommand? packCommand;
  final RestorePlanCommand? restoreCommand;
  String get family =>
      source == MaintenanceReceiptSource.restorePlan ? 'pack' : source.name;
}

abstract interface class MaintenanceTaskCatalog {
  bool get isCurrent;
  Future<CatalogPage<MaintenanceTask>> page({
    int offset = 0,
    int limit = 24,
    String family = 'all',
    String state = 'all',
  });
  Future<MaintenanceTask> task(String id);
  Future<CatalogPage<MaintenanceItem>> items(
    String id, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  });
  Future<List<MaintenanceReceipt>> pending();

  /// GET original receipts only. No retry or new work is submitted by querying.
  Future<MaintenanceTask?> reconcile(MaintenanceReceipt receipt);
  Future<String> downloadBackup(String id);
  Future<void> backupSaved(String id);
  void dispose();
}
