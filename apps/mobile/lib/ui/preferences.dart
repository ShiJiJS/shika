import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class UiPreferences extends ChangeNotifier {
  factory UiPreferences({File? file, bool dark = false}) =>
      UiPreferences._(file, dark);
  UiPreferences._(this._file, this._dark);
  final File? _file;
  bool _dark;
  bool get dark => _dark;

  static Future<UiPreferences> load({File? file}) async {
    file ??= File(
      '${(await getApplicationSupportDirectory()).path}/appearance.json',
    );
    var dark = false;
    try {
      if (await file.exists()) {
        final saved = jsonDecode(await file.readAsString());
        dark = saved is Map && saved['dark'] == true;
      }
    } on FormatException {
      // An incomplete preference file falls back to the default appearance.
    } on FileSystemException {
      // The app can still open; a later failed save is reported by the UI.
    }
    return UiPreferences(file: file, dark: dark);
  }

  Future<void> setDark(bool value) async {
    await _file?.writeAsString(jsonEncode({'dark': value}), flush: true);
    _dark = value;
    notifyListeners();
  }
}
