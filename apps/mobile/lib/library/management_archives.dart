import 'backup_document.dart';
import 'models.dart';

Never _bad() => throw const LibraryFailure('服务端备份预览信息不完整，请重新校验原文件');
int _count(Object? value, {int maximum = 9007199254740991}) {
  if (value is! int || value < 0 || value > maximum) _bad();
  return value;
}

String _text(Object? value, {int maximum = 8192}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      value.contains('\u0000')) {
    _bad();
  }
  return value;
}

class ArchiveRoot {
  ArchiveRoot.fromJson(Map<String, dynamic> raw)
    : id = _text(raw['id'], maximum: 128),
      name = _text(raw['name']),
      path = _text(raw['original_path']),
      kind = switch (raw['kind'] ?? 'video') {
        'video' => MediaKind.video,
        'pack' => MediaKind.pack,
        _ => _bad(),
      },
      enabled = raw['enabled'] as bool? ?? true,
      suggestedPath = raw['suggested_path'] == null
          ? null
          : _text(raw['suggested_path']) {
    if (!path.startsWith('/') ||
        suggestedPath != null && !suggestedPath!.startsWith('/')) {
      _bad();
    }
  }
  final String id, name, path;
  final MediaKind kind;
  final bool enabled;
  final String? suggestedPath;
}

class ArchiveRootPage {
  ArchiveRootPage({
    required this.items,
    required this.total,
    required this.offset,
  });
  final List<ArchiveRoot> items;
  final int total, offset;
}

class ArchivePreview {
  ArchivePreview({
    required this.taskId,
    required this.protocol,
    required this.fileVersion,
    required this.fileSha256,
    required this.bytes,
    required this.rootsTotal,
    required Map<String, int> counts,
    this.legacyRoots,
  }) : counts = Map.unmodifiable(counts) {
    _text(taskId, maximum: 128);
    if (![1, 2].contains(protocol) ||
        ![1, 2].contains(fileVersion) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fileSha256) ||
        bytes <= 0 ||
        bytes > maximumBackupFileBytes ||
        rootsTotal < 0 ||
        rootsTotal > 256) {
      _bad();
    }
  }
  final String taskId, fileSha256;
  final int protocol, fileVersion, bytes, rootsTotal;
  final Map<String, int> counts;
  final List<ArchiveRoot>? legacyRoots;

  factory ArchivePreview.fromTask(
    Map<String, dynamic> task, {
    required int protocol,
    required String digest,
  }) {
    final raw = Map<String, dynamic>.from(task['result'] as Map);
    final counts = Map<String, dynamic>.from(raw['counts'] as Map)
        .map((k, v) => MapEntry(k, _count(v)));
    final roots = protocol == 1
        ? (raw['roots'] as List)
              .map(
                (v) =>
                    ArchiveRoot.fromJson(Map<String, dynamic>.from(v as Map)),
              )
              .toList()
        : null;
    if (task['status'] != 'completed' ||
        task['kind'] != 'backup_inspect${protocol == 2 ? '_v2' : ''}' ||
        raw['file_sha256'] != digest) {
      _bad();
    }
    return ArchivePreview(
      taskId: _text(task['id'], maximum: 128),
      protocol: protocol,
      fileVersion: _count(raw['version'], maximum: 2),
      fileSha256: digest,
      bytes: _count(raw['bytes'], maximum: maximumBackupFileBytes),
      rootsTotal: protocol == 2
          ? _count(raw['roots_count'], maximum: 256)
          : roots!.length,
      counts: counts,
      legacyRoots: roots == null ? null : List.unmodifiable(roots),
    );
  }
}

class ArchiveExport {
  const ArchiveExport(this.taskId, this.document);
  final String taskId;
  final BackupDocument document;
}

class ArchiveRestorePoint {
  ArchiveRestorePoint.fromJson(Map<String, dynamic> raw, {required this.owner})
    : restoreId = _text(raw['restore_id'], maximum: 128),
      snapshotId = _text(raw['snapshot_id'], maximum: 128),
      kind = _text(raw['kind'], maximum: 32),
      createdAt = raw['created_at'] is num
          ? (raw['created_at'] as num).toDouble()
          : -1,
      bytes = _count(raw['bytes'], maximum: maximumBackupFileBytes),
      fileSha256 = _text(raw['file_sha256'], maximum: 64) {
    if (!['backup_snapshot', 'backup_snapshot_v2'].contains(kind) ||
        !createdAt.isFinite ||
        createdAt < 0 ||
        bytes == 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fileSha256)) {
      _bad();
    }
  }
  final String owner, restoreId, snapshotId, kind, fileSha256;
  final double createdAt;
  final int bytes;
}

/// UI consumes server-validated scalar previews and root pages, never file JSON.
abstract interface class ManagementArchiveRepository {
  bool get archiveBackupsAvailable;
  int get archiveMaximumBytes;
  bool get archivePreviewPending;
  Future<ArchivePreview> resumeArchivePreview();
  Future<ArchiveRestorePoint?> latestArchiveRestorePoint();
  Future<ArchivePreview> inspectArchiveRestorePoint(ArchiveRestorePoint point);
  Future<BackupFileStore> archiveFileStore();
  Future<ArchiveExport> exportArchive();
  Future<void> archiveSaved(String identity);
  Future<ArchivePreview> inspectArchive(BackupDocument document);
  Future<ArchiveRootPage> archiveRoots(
    ArchivePreview preview, {
    int offset = 0,
    int limit = 24,
  });
  Future<void> restoreArchive(
    ArchivePreview preview,
    Map<String, String?> mappings,
  );
}
