import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import 'models.dart';
import 'request_scope.dart';

const maximumBackupFileBytes = 256 * 1024 * 1024;

void _active(RequestScope? scope) {
  if (scope?.cancelled == true) throw const RequestCancelled();
}

class _DigestResult implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}

/// A verified private file, never the external picker URI or file contents.
class BackupDocument {
  BackupDocument._(this.store, this.id, this.bytes, this.sha256);
  final BackupFileStore store;
  final String id, sha256;
  final int bytes;
  String get path => '${store.directory.path}/$id.vvbackup';
  Map<String, Object> toJson() => {
    'owner': store.owner,
    'id': id,
    'bytes': bytes,
    'sha256': sha256,
  };

  Future<void> _regular() async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const LibraryFailure('本机备份暂存文件不可读取，请重新选择或下载原文件');
    }
    if (await File(path).length() != bytes) {
      throw const LibraryFailure('本机备份文件已变化，请重新选择或下载原文件');
    }
  }

  /// Hash while reading as well as before admission; callers can abort a write
  /// if its supposedly immutable private source changes during transfer.
  Stream<List<int>> verifiedRead({RequestScope? scope}) async* {
    _active(scope);
    await _regular();
    final result = _DigestResult();
    final digest = crypto.sha256.startChunkedConversion(result);
    var count = 0;
    try {
      await for (final chunk in File(path).openRead()) {
        _active(scope);
        count += chunk.length;
        if (count > bytes) throw const LibraryFailure('本机备份文件已变化');
        digest.add(chunk);
        yield chunk;
      }
    } finally {
      digest.close();
    }
    _active(scope);
    await _regular();
    if (count != bytes || result.value.toString() != sha256) {
      throw const LibraryFailure('本机备份文件已变化，请重新选择或下载原文件');
    }
  }

  Future<void> verify({RequestScope? scope}) async {
    await for (final _ in verifiedRead(scope: scope)) {}
  }

  Future<void> delete() async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.file) {
      await File(path).delete();
    }
  }
}

/// Files are scoped to the service and captured management generation. Journals
/// retain descriptors if the OS removes a file; an old command must not replay.
class BackupFileStore {
  BackupFileStore(this.directory, {required this.owner});
  final Directory directory;
  final String owner;

  BackupDocument restore(Map<String, dynamic> value) {
    final id = value['id'], bytes = value['bytes'], hash = value['sha256'];
    if (value['owner'] != owner ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        bytes is! int ||
        bytes <= 0 ||
        bytes > maximumBackupFileBytes ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const LibraryFailure('备份文件记录与当前连接不符，原记录已保留');
    }
    return BackupDocument._(this, id, bytes, hash);
  }

  Future<BackupDocument> capture(
    Stream<List<int>> incoming, {
    required int maximumBytes,
    int? expectedBytes,
    String? expectedSha256,
    RequestScope? scope,
  }) async {
    if (maximumBytes <= 0 ||
        maximumBytes > maximumBackupFileBytes ||
        expectedBytes != null &&
            (expectedBytes <= 0 || expectedBytes > maximumBytes) ||
        expectedSha256 != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256)) {
      throw const LibraryFailure('备份文件大小或摘要不完整，请查询原任务');
    }
    _active(scope);
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      await directory.create(recursive: true);
    } else if (type != FileSystemEntityType.directory) {
      throw const LibraryFailure('本机备份暂存目录不可用');
    }
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final partial = File('${directory.path}/$id.part');
    final complete = File('${directory.path}/$id.vvbackup');
    RandomAccessFile? output;
    final iterator = StreamIterator(incoming);
    void cancel() => unawaited(iterator.cancel());
    final result = _DigestResult();
    final digest = crypto.sha256.startChunkedConversion(result);
    var bytes = 0, published = false, digestClosed = false;
    scope?.add(cancel);
    try {
      _active(scope);
      await partial.create(exclusive: true);
      output = await partial.open(mode: FileMode.writeOnly);
      while (await iterator.moveNext()) {
        _active(scope);
        final chunk = iterator.current;
        bytes += chunk.length;
        if (bytes > maximumBytes ||
            expectedBytes != null && bytes > expectedBytes) {
          throw const LibraryFailure('备份文件超过允许的大小或与原任务不符');
        }
        digest.add(chunk);
        await output.writeFrom(chunk);
      }
      digest.close();
      digestClosed = true;
      _active(scope);
      if (bytes <= 0 ||
          expectedBytes != null && bytes != expectedBytes ||
          expectedSha256 != null && result.value.toString() != expectedSha256) {
        throw const LibraryFailure('备份文件大小或完整性核对失败，请重新下载原文件');
      }
      await output.flush();
      await output.close();
      output = null;
      _active(scope);
      await partial.rename(complete.path);
      _active(scope);
      final document = BackupDocument._(
        this,
        id,
        bytes,
        result.value.toString(),
      );
      published = true;
      return document;
    } finally {
      scope?.remove(cancel);
      if (!digestClosed) digest.close();
      await iterator.cancel();
      await output?.close();
      if (!published) {
        if (await partial.exists()) await partial.delete();
        if (await complete.exists()) await complete.delete();
      }
    }
  }
}
