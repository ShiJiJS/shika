import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A small receipt journal, scoped to one endpoint and server identity.
/// It contains no media bytes or service passphrase.
abstract interface class FileCommandStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryFileCommandStore implements FileCommandStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

class SecureFileCommandStore implements FileCommandStore {
  SecureFileCommandStore({this.key = 'video_viewer.file_commands.v1'});
  final String key;
  static const storage = FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
}
