import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/preferences.dart';

void main() {
  test(
    'preloading and appearance survive reopening without resetting each other',
    () async {
      final directory = await Directory.systemTemp.createTemp('vv-appearance-');
      final file = File('${directory.path}/appearance.json');
      try {
        await file.writeAsString('{"dark":true}');
        final preferences = await UiPreferences.load(file: file);
        expect(preferences.dark, isTrue);
        expect(preferences.preloadAdjacent, isTrue);
        await preferences.setPreloadAdjacent(false);
        await preferences.setDark(false);
        preferences.dispose();
        final reopened = await UiPreferences.load(file: file);
        expect(reopened.dark, isFalse);
        expect(reopened.preloadAdjacent, isFalse);
        reopened.dispose();
      } finally {
        if (await file.exists()) await file.delete();
        await directory.delete();
      }
    },
  );
}
