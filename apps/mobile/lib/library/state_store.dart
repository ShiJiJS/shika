import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract interface class StateStore {
  Future<String?> read();
  Future<void> write(String text);
  Future<void> saveRecovery(String text);
}

class MemoryStateStore implements StateStore {
  String? value, recovery;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async {
    value = text;
  }

  @override
  Future<void> saveRecovery(String text) async {
    recovery = text;
  }
}

class FileStateStore implements StateStore {
  FileStateStore(this.directory);
  final Directory directory;
  static Future<FileStateStore> create() async =>
      FileStateStore(await getApplicationSupportDirectory());
  File get _file => File('${directory.path}/demo-library.json');
  File get _previous => File('${_file.path}.previous');
  @override
  Future<String?> read() async {
    if (await _file.exists()) return _file.readAsString();
    if (await _previous.exists()) return _previous.readAsString();
    return null;
  }

  @override
  Future<void> write(String text) async {
    await directory.create(recursive: true);
    final temporary = File('${_file.path}.pending');
    await temporary.writeAsString(text, flush: true);
    if (await _file.exists()) {
      if (await _previous.exists()) await _previous.delete();
      await _file.rename(_previous.path);
    }
    try {
      await temporary.rename(_file.path);
    } catch (_) {
      if (!await _file.exists() && await _previous.exists()) {
        await _previous.rename(_file.path);
      }
      rethrow;
    }
  }

  @override
  Future<void> saveRecovery(String text) async {
    await directory.create(recursive: true);
    await File('${directory.path}/demo-before-restore.json')
        .writeAsString(text, flush: true);
  }
}
