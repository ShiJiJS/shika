import 'models.dart';
import 'pack_models.dart';

Never _bad() => throw const LibraryFailure('永久删除清单不完整，请重新核对');
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : _bad();
String _text(Object? value, [int max = 4096]) =>
    value is String && value.isNotEmpty && value.length <= max ? value : _bad();
int _count(Object? value) => value is int && value >= 0 ? value : _bad();
bool _flag(Object? value) => value is bool ? value : _bad();
String _hash(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
    ? value
    : _bad();
double _time(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : _bad();

class PackPurgeMember {
  PackPurgeMember(Map<String, dynamic> raw)
    : trashId = _text(raw['trash_id'], 128),
      packId = _text(raw['pack_id'], 128),
      name = _text(raw['name']),
      path = _text(raw['path']),
      digest = raw['digest'] == null ? null : _hash(raw['digest']),
      error = raw['error'] == null ? null : _text(raw['error']),
      imageCount = _count(raw['image_count']),
      imageBytes = _count(raw['image_bytes']),
      retainedEntries = _count(raw['retained_entries']);
  final String trashId, packId, name, path;
  final String? digest, error;
  final int imageCount, imageBytes, retainedEntries;
}

/// A server-clock-bound, exact review. It never performs deletion.
class PackPurgePlan {
  PackPurgePlan(Map<String, dynamic> raw)
    : id = _text(raw['id'], 128),
      status = _text(raw['status'], 32),
      digest = raw['digest'] == null ? null : _hash(raw['digest']),
      operationId = raw['operation_id'] == null
          ? null
          : _text(raw['operation_id'], 128),
      error = raw['error'] == null ? null : _text(raw['error']),
      historical = _flag(raw['historical']),
      ready = _flag(raw['ready']),
      serverTime = _time(raw['server_time']),
      expiresAt = _time(raw['expires_at']),
      receivedAt = DateTime.now(),
      members = List.unmodifiable(
        (raw['items'] as List).map((v) => PackPurgeMember(_map(v))),
      ) {
    if (raw['kind'] != 'pack_purge_preview' ||
        ![
          'queued',
          'running',
          'completed',
          'failed',
          'interrupted',
        ].contains(status) ||
        members.isEmpty ||
        members.length > 1000 ||
        members.map((v) => v.trashId).toSet().length != members.length ||
        members.map((v) => v.packId).toSet().length != members.length) {
      _bad();
    }
    if (status == 'completed') {
      final result = _map(raw['result']);
      if (_count(result['total']) != members.length ||
          _count(result['processed']) != members.length ||
          _count(result['succeeded']) !=
              members.where((m) => m.error == null).length ||
          _count(result['failed']) !=
              members.where((m) => m.error != null).length ||
          _count(result['image_count']) != imageCount ||
          _count(result['image_bytes']) != imageBytes) {
        _bad();
      }
    }
    final valid =
        status == 'completed' &&
        digest != null &&
        !historical &&
        operationId == null &&
        serverTime <= expiresAt;
    if (ready != valid ||
        (ready &&
            members.any(
              (m) => m.error != null || m.digest == null || m.imageCount == 0,
            ))) {
      _bad();
    }
  }
  final String id, status;
  final String? digest, operationId, error;
  final bool historical, ready;
  final double serverTime, expiresAt;
  final DateTime receivedAt;
  final List<PackPurgeMember> members;
  int get imageCount => members.fold(0, (n, m) => n + m.imageCount);
  int get imageBytes => members.fold(0, (n, m) => n + m.imageBytes);
  Duration get remaining =>
      Duration(milliseconds: ((expiresAt - serverTime) * 1000).floor()) -
      DateTime.now().difference(receivedAt);
  bool get canConfirm => ready && remaining > Duration.zero;
  void bind(Iterable<String> ids) {
    final expected = ids.toSet();
    if (expected.length != members.length ||
        !members.every((m) => expected.contains(m.trashId))) {
      _bad();
    }
  }
}

class PackPurgeImage {
  PackPurgeImage(Map<String, dynamic> raw, PackPurgeMember member)
    : id = _text(raw['id'], 128),
      path = _text(raw['path']),
      relativePath = _text(raw['relative_path']),
      size = _count(raw['size']),
      sha256 = _hash(raw['sha256']) {
    if (!_relative(relativePath) ||
        path != '${member.path}/$relativePath' ||
        raw['signature'] is! List ||
        (raw['signature'] as List).length != 5 ||
        !(raw['signature'] as List).every(
          (v) =>
              (v is int && v >= 0) ||
              (v is String && RegExp(r'^[0-9]{1,30}$').hasMatch(v)),
        ) ||
        (raw['signature'] as List)[2] != size) {
      _bad();
    }
  }
  final String id, path, relativePath, sha256;
  final int size;
}

bool _relative(String path) =>
    !path.startsWith('/') &&
    !path.contains('\\') &&
    !path.split('/').any((p) => p.isEmpty || p == '.' || p == '..');

class PackPurgeStep {
  PackPurgeStep(Map<String, dynamic> raw)
    : id = _text(raw['id'], 128),
      packId = _text(raw['pack_id'], 128),
      packName = _text(raw['pack_name']),
      kind = _text(raw['kind'], 32),
      relativePath = _text(raw['relative_path']),
      phase = _text(raw['phase'], 64),
      outcome = _text(raw['outcome'], 64),
      error = raw['error'] == null ? null : _text(raw['error']) {
    if (!['image', 'directory'].contains(kind) ||
        !['pending', 'succeeded', 'failed', 'retained'].contains(outcome) ||
        ![
          'prepared',
          'claiming',
          'claimed',
          'verified',
          'purging',
          'committed',
          'rolled_back',
          'removing',
          'retained',
          'needs_attention',
        ].contains(phase) ||
        (kind == 'image' && outcome == 'retained') ||
        !(kind == 'directory' && relativePath == '.' ||
            _relative(relativePath))) {
      _bad();
    }
  }
  final String id, packId, packName, kind, relativePath, phase, outcome;
  final String? error;
}

abstract interface class PackPurgeGateway {
  bool get isCurrent;
  Future<PackPurgePlan> prepare(String requestId, List<String> trashIds);
  Future<PackPurgePlan?> receipt(String requestId);
  Future<PackPurgePlan> plan(String id);
  Future<CatalogPage<PackPurgeImage>> images(
    PackPurgePlan plan,
    PackPurgeMember member, {
    int offset = 0,
    int limit = 100,
  });
  Future<CatalogPage<PackPurgeStep>> steps(
    String operationId, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  });
  void dispose();
}

/// Original evidence is bound to one task/graph. No command or settlement
/// methods are available to a history page.
abstract interface class PurgeHistoryDetails {
  bool get isCurrent;
  Future<PurgeHistoryReview> review({int offset = 0, int limit = 24});
  Future<CatalogPage<PackPurgeImage>> images(
    PackPurgeMember member, {
    int offset = 0,
    int limit = 100,
  });
  Future<CatalogPage<PackPurgeStep>> steps({
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
    String kind = 'all',
  });
  void dispose();
}

class PurgeHistoryReview {
  PurgeHistoryReview(Map<String, dynamic> raw, this.members)
    : planId = _text(raw['plan_id'], 128),
      operationId = raw['operation_id'] == null
          ? null
          : _text(raw['operation_id'], 128),
      status = _text(raw['status'], 32),
      digest = raw['digest'] == null ? null : _hash(raw['digest']),
      expiresAt = _time(raw['expires_at']),
      imageCount = _count(raw['image_count']),
      imageBytes = _count(raw['image_bytes']),
      retainedEntries = _count(raw['retained_entries']) {
    if (raw['historical'] != true ||
        raw['ready'] != false ||
        ![
          'queued',
          'running',
          'completed',
          'failed',
          'interrupted',
        ].contains(status) ||
        members.items.map((m) => m.packId).toSet().length !=
            members.items.length ||
        members.items.fold(0, (int n, m) => n + m.imageCount) > imageCount ||
        members.items.fold(0, (int n, m) => n + m.imageBytes) > imageBytes ||
        members.items.fold(0, (int n, m) => n + m.retainedEntries) >
            retainedEntries) {
      _bad();
    }
  }
  final String planId, status;
  final String? operationId, digest;
  final double expiresAt;
  final int imageCount, imageBytes, retainedEntries;
  final CatalogPage<PackPurgeMember> members;
}
