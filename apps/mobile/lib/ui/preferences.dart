import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class UiPreferences extends ChangeNotifier {
  factory UiPreferences({
    File? file,
    bool dark = false,
    bool preloadAdjacent = true,
  }) => UiPreferences._(file, dark, preloadAdjacent);
  UiPreferences._(this._file, this._dark, this._preloadAdjacent);
  final File? _file;
  bool _dark;
  bool get dark => _dark;
  bool _preloadAdjacent;
  bool get preloadAdjacent => _preloadAdjacent;

  static Future<UiPreferences> load({File? file}) async {
    file ??= File(
      '${(await getApplicationSupportDirectory()).path}/appearance.json',
    );
    var dark = false;
    var preload = true;
    try {
      if (await file.exists()) {
        final saved = jsonDecode(await file.readAsString());
        dark = saved is Map && saved['dark'] == true;
        preload = saved is! Map || saved['preloadAdjacent'] != false;
      }
    } on FormatException {
      // An incomplete preference file falls back to the default appearance.
    } on FileSystemException {
      // The app can still open; a later failed save is reported by the UI.
    }
    return UiPreferences(file: file, dark: dark, preloadAdjacent: preload);
  }

  Future<void> setDark(bool value) async {
    await _save(dark: value, preload: _preloadAdjacent);
    _dark = value;
    notifyListeners();
  }

  Future<void> setPreloadAdjacent(bool value) async {
    await _save(dark: _dark, preload: value);
    _preloadAdjacent = value;
    notifyListeners();
  }

  Future<void> _save({required bool dark, required bool preload}) async =>
      _file?.writeAsString(
        jsonEncode({'dark': dark, 'preloadAdjacent': preload}),
        flush: true,
      );
}
