import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small command receipts only. Backup files remain outside secure storage.
abstract interface class BackupWorkStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryBackupWorkStore implements BackupWorkStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class SecureBackupWorkStore implements BackupWorkStore {
  SecureBackupWorkStore({this.key = 'video_viewer.backup_work.v1'});
  final String key;
  static const _storage = FlutterSecureStorage();
  Future<void> _writes = Future.value();
  @override
  Future<String?> read() async {
    await _writes;
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String value) {
    final result = _writes.then((_) => _storage.write(key: key, value: value));
    _writes = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }
}
