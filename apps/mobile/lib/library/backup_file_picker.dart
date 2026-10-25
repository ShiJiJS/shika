import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_document.dart';
import 'models.dart';
import 'request_scope.dart';

abstract interface class BackupArchiveFiles {
  Future<BackupDocument?> pick(
    BackupFileStore store, {
    required int maximumBytes,
    RequestScope? scope,
  });
  Future<bool> save(BackupDocument document, {RequestScope? scope});
}

/// Android SAF copies in 64KiB windows on a worker, enforcing the file limit
/// during import. Saving passes a private path instead of a platform byte array.
class NativeBackupArchiveFiles implements BackupArchiveFiles {
  const NativeBackupArchiveFiles({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('video_viewer/backup_files');
  final MethodChannel _channel;

  static Future<BackupFileStore> storeFor(String owner) async {
    if (owner.isEmpty) throw const LibraryFailure('请先确认当前连接');
    final base = await getApplicationSupportDirectory();
    final partition = sha256.convert(utf8.encode(owner));
    return BackupFileStore(
      Directory('${base.path}/management-archives/$partition'),
      owner: owner,
    );
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object> arguments,
    RequestScope? scope,
  ) async {
    if (scope?.cancelled == true) throw const RequestCancelled();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    void cancel() => unawaited(
      _channel
          .invokeMethod<void>('cancel', {'id': id})
          .then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
    );
    scope?.add(cancel);
    try {
      if (scope?.cancelled == true) throw const RequestCancelled();
      return await _channel.invokeMethod<Object?>(method, {
        'id': id,
        ...arguments,
      });
    } on PlatformException catch (error) {
      if (scope?.cancelled == true) throw const RequestCancelled();
      throw LibraryFailure(switch (error.code) {
        'BACKUP_BUSY' => '请先关闭当前系统文件选择器',
        'BACKUP_FILE_INVALID' => '本机备份文件信息不完整，请重新选择或下载原文件',
        _ => '系统文件操作未能完成，原备份任务已保留',
      });
    } on MissingPluginException {
      throw const LibraryFailure('当前设备未提供管理文件流，请在 Android App 中操作');
    } finally {
      scope?.remove(cancel);
    }
  }

  @override
  Future<BackupDocument?> pick(
    BackupFileStore store, {
    required int maximumBytes,
    RequestScope? scope,
  }) async {
    if (maximumBytes <= 0 || maximumBytes > maximumBackupFileBytes) {
      throw const LibraryFailure('服务未提供有效的备份文件上限');
    }
    final raw = await _invoke('pick', {
      'directory': store.directory.path,
      'owner': store.owner,
      'maximumBytes': maximumBytes,
    }, scope);
    BackupDocument? document;
    try {
      if (raw != null) {
        document = store.restore(Map<String, dynamic>.from(raw as Map));
        if (document.bytes > maximumBytes) {
          throw const LibraryFailure('所选备份超过服务允许大小');
        }
      }
      if (scope?.cancelled == true) throw const RequestCancelled();
      await document?.verify(scope: scope);
      return document;
    } catch (_) {
      await document?.delete();
      rethrow;
    }
  }

  @override
  Future<bool> save(BackupDocument document, {RequestScope? scope}) async {
    await document.verify(scope: scope);
    final saved = await _invoke('save', {
      'path': document.path,
      'bytes': document.bytes,
      'sha256': document.sha256,
      'name': 'video-viewer-backup.vvbackup',
    }, scope);
    if (scope?.cancelled == true) throw const RequestCancelled();
    return saved == true;
  }
}
