import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'backup_work_store.dart';
import 'models.dart';
import 'server_api.dart';

typedef _Json = Map<String, dynamic>;
_Json _map(Object? value) => Map<String, dynamic>.from(value as Map);
String _nonce() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

/// Owns the transport and durable receipts of one server's backup workflow.
/// Reopening or querying an uncertain restore never submits it again.
class ServerBackups {
  ServerBackups({
    required this.api,
    required this.scope,
    required this.store,
    required this.status,
    required this.onChanged,
    required this.onRestored,
  });
  final ServerApi api;
  final String scope;
  final BackupWorkStore store;
  final ValueNotifier<String?> status;
  final VoidCallback onChanged;
  final Future<void> Function() onRestored;
  final RequestScope _lifetime = RequestScope();
  _Json _state = {};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  String? _previewDigest;
  BackupPreview? _preview;
  bool get restorePending => _state['restore'] != null;
  void _check() {
    if (_disposed) throw const RequestCancelled();
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _writes.then((_) {
      _check();
      return action();
    });
    _writes = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  Future<void> initialize() => _serial(() async {
    final text = await store.read();
    _check();
    if (text != null) {
      try {
        final saved = _map(jsonDecode(text));
        if (saved['scope'] == scope) _state = saved;
      } catch (_) {
        /* Ignore invalid local receipts. */
      }
    }
    status.value = restorePending ? '恢复结果待确认，请查询原任务' : null;
    onChanged();
  });
  Future<void> _save(_Json next) async {
    _check();
    await store.write(jsonEncode({'scope': scope, ...next}));
    _check();
    _state = next;
    onChanged();
  }

  Future<void> _remove(String kind) => _save({..._state}..remove(kind));
  void _canStart() {
    if (restorePending) throw const LibraryFailure('恢复结果尚未确认，请先查询结果');
  }

  Future<_Json> _json(String method, String path, {Object? body}) =>
      api.json(method, path, body: body, scope: _lifetime);

  Future<_Json> _poll(String id, String kind) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    final phases = {
      'queued': '任务排队中',
      'snapshot_written': '已保存恢复前快照',
      'reconciling_files': '正在核对媒体位置',
      'replacing_management': '正在恢复管理数据',
    };
    while (true) {
      _check();
      final task = await _json('GET', '/api/v1/tasks/$id');
      _check();
      status.value =
          phases[task['phase']] ??
          switch (kind) {
            'export' => '正在导出备份',
            'inspect' => '正在校验备份',
            _ => '正在恢复管理数据',
          };
      if (['completed', 'failed'].contains(task['status'])) return task;
      if (DateTime.now().isAfter(deadline)) {
        throw const LibraryFailure('服务仍在处理备份任务，可稍后查询结果');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  LibraryFailure _failed(_Json task) => LibraryFailure(
    const {
          'backup_version_unsupported': '备份类型或数据库版本不兼容',
          'backup_checksum_mismatch': '备份完整性校验失败，文件可能已损坏',
          'invalid_backup': '备份内容不完整或已损坏',
          'backup_source_unavailable': '服务端未收到完整导入文件，请重新选择文件',
          'backup_artifact_changed': '备份文件在校验后发生变化，请重新选择文件',
          'invalid_mapping': '媒体目录映射不正确，请重新核对',
        }[task['error']] ??
        '备份任务未完成，原管理数据保留，请重试',
  );

  Future<String> export() => _serial(() async {
    _canStart();
    var command = _map(_state['export'] ?? {'key': _nonce()});
    await _save({..._state, 'export': command});
    if (command['task'] == null) {
      final accepted = await _json(
        'POST',
        '/api/v1/backups',
        body: {'request_id': command['key']},
      );
      command = {...command, 'task': accepted['id']};
      await _save({..._state, 'export': command});
    }
    final task = await _poll(command['task'], 'export');
    if (task['status'] != 'completed') {
      await _remove('export');
      throw _failed(task);
    }
    try {
      final response = await api.request(
        'GET',
        '/api/v1/backups/${command['task']}/download',
        maximumBytes: 32 * 1024 * 1024,
        timeout: const Duration(minutes: 2),
        scope: _lifetime,
      );
      _check();
      if (sha256.convert(response.bytes).toString() !=
          _map(task['result'])['file_sha256']) {
        throw const LibraryFailure('下载备份的完整性校验失败，请重新下载');
      }
      final text = utf8.decode(response.bytes);
      await _remove('export');
      status.value = '备份内容已下载';
      return text;
    } on ApiFailure catch (error) {
      if ([404, 409].contains(error.status)) await _remove('export');
      rethrow;
    } on FormatException {
      throw const LibraryFailure('服务返回的备份不是有效的 UTF-8 文件');
    }
  });

  Future<BackupPreview> inspect(String text) => _serial(() => _inspect(text));
  Future<BackupPreview> _inspect(String text) async {
    _canStart();
    final raw = utf8.encode(text);
    if (raw.length > 32 * 1024 * 1024) {
      throw const LibraryFailure('备份超过客户端 32 MiB 大小限制');
    }
    _Json envelope;
    try {
      envelope = _map(jsonDecode(text));
    } catch (_) {
      throw const LibraryFailure('备份不是有效的 JSON 文件');
    }
    if (envelope['format'] != 'video-viewer-management' ||
        envelope['version'] != 1) {
      throw const LibraryFailure('备份格式或版本不兼容，请选择服务端导出的备份');
    }
    final digest = sha256.convert(raw).toString();
    if (_previewDigest == digest && _preview != null) return _preview!;
    var command = _state['inspect'] == null
        ? <String, dynamic>{}
        : _map(_state['inspect']);
    if (command['digest'] != digest) {
      command = {'digest': digest, 'key': _nonce()};
    }
    await _save({..._state, 'inspect': command});
    if (command['task'] == null) {
      final accepted = await api.request(
        'POST',
        '/api/v1/backup-imports',
        timeout: const Duration(minutes: 2),
        body: raw,
        headers: {'Idempotency-Key': command['key']},
        scope: _lifetime,
      );
      command = {
        ...command,
        'task': _map(jsonDecode(utf8.decode(accepted.bytes)))['id'],
      };
      await _save({..._state, 'inspect': command});
    }
    final task = await _poll(command['task'], 'inspect');
    if (task['status'] != 'completed') {
      await _remove('inspect');
      throw _failed(task);
    }
    final result = _map(task['result']);
    if (result['file_sha256'] != digest) {
      await _remove('inspect');
      throw const LibraryFailure('服务端校验结果与所选文件不一致，请重新选择');
    }
    final roots = (result['roots'] as List).map(_map).toList();
    _previewDigest = digest;
    _preview = BackupPreview(
      LibrarySnapshot(
        videos: [],
        roots: roots.map(
          (r) => MediaRoot(r['id'], r['name'], r['original_path']),
        ),
        tags: [],
        query: VideoQuery(),
        round: [],
      ),
      importId: command['task'],
      suggestedMappings: {for (final r in roots) r['id']: r['suggested_path']},
      counts: _map(result['counts'])
          .map((key, value) => MapEntry(key, (value as num).toInt())),
    );
    status.value = '校验通过，请核对媒体目录映射';
    return _preview!;
  }

  Future<void> restore(String text, Map<String, String> mappings) =>
      _serial(() async {
        _canStart();
        final preview = await _inspect(text);
        final entries = mappings.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final command = {
          'key': _nonce(),
          'body': {
            'preview_id': preview.importId,
            'confirmed': true,
            'root_mapping': {
              for (final e in entries)
                e.key: e.value.trim().isEmpty ? null : e.value.trim(),
            },
          },
        };
        await _save({..._state, 'restore': command});
        status.value = '正在提交已确认的恢复';
        try {
          final accepted = await _json(
            'POST',
            '/api/v1/backup-restores',
            body: {'request_id': command['key'], ..._map(command['body'])},
          );
          await _save({
            ..._state,
            'restore': {...command, 'task': accepted['id']},
          });
        } on ApiFailure catch (error) {
          if (error.status != null &&
              error.status! >= 400 &&
              error.status! < 500 &&
              ![408, 429].contains(error.status)) {
            await _remove('restore');
          }
          rethrow;
        }
        await _reconcile();
      });

  Future<void> reconcile() => _serial(_reconcile);
  Future<void> _reconcile() async {
    if (!restorePending) return;
    var command = _map(_state['restore']);
    if (command['task'] == null) {
      try {
        final found = await _json(
          'GET',
          '/api/v1/backup-requests/restore/${command['key']}',
        );
        command = {...command, 'task': found['id']};
        await _save({..._state, 'restore': command});
      } on ApiFailure catch (error) {
        if (error.status == 404) {
          await _save({});
          _preview = null;
          _previewDigest = null;
          throw const LibraryFailure('未找到已受理的恢复，请重新选择文件并确认；没有补执行恢复');
        }
        rethrow;
      }
    }
    final task = await _poll(command['task'], 'restore');
    if (task['status'] != 'completed') {
      await _remove('restore');
      throw _failed(task);
    }
    _check();
    await onRestored();
    _check();
    await _save({});
    _preview = null;
    _previewDigest = null;
    status.value = '管理数据已恢复';
  }

  void dispose() {
    _disposed = true;
    _lifetime.cancel();
  }
}
