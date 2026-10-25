import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/preferences.dart';
import 'package:video_viewer/library/models.dart';

void main() {
  test('default migration decisions survive reopening and stay separate per service', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vv-default-migration-',
    );
    final file = File('${directory.path}/appearance.json');
    try {
      final preferences = UiPreferences(
        file: file,
        videoOrder: PlayOrder.sequential,
      );
      await Future.wait([
        preferences.markDefaultMigration('["http://one:8760","instance-a"]'),
        preferences.setDark(true),
      ]);
      final reopened = await UiPreferences.load(file: file);
      expect(
        reopened.defaultMigrationDone('["http://one:8760","instance-a"]'),
        isTrue,
      );
      expect(
        reopened.defaultMigrationDone('["http://two:8760","instance-a"]'),
        isFalse,
      );
      expect(
        reopened.defaultMigrationDone('["http://one:8760","instance-b"]'),
        isFalse,
      );
      expect(reopened.dark, isTrue);
      expect(reopened.videoOrder, PlayOrder.sequential);
      preferences.dispose();
      reopened.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });
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
        expect(preferences.videoOrder, isNull);
        await preferences.ensureVideoOrder(PlayOrder.sequential);
        await preferences.setPreloadAdjacent(false);
        await preferences.setDark(false);
        preferences.dispose();
        final reopened = await UiPreferences.load(file: file);
        expect(reopened.dark, isFalse);
        expect(reopened.preloadAdjacent, isFalse);
        expect(reopened.videoOrder, PlayOrder.sequential);
        reopened.dispose();
      } finally {
        if (await file.exists()) await file.delete();
        await directory.delete();
      }
    },
  );

  test('overlapping preference writes retain each other and initial adoption never replaces a chosen default', () async {
    final directory = await Directory.systemTemp.createTemp('vv-defaults-');
    try {
      final file = File('${directory.path}/appearance.json');
      final preferences = UiPreferences(file: file);
      await Future.wait([
        preferences.setVideoOrder(PlayOrder.sequential),
        preferences.setDark(true),
        preferences.setPreloadAdjacent(false),
        preferences.ensureVideoOrder(PlayOrder.random),
      ]);
      final reopened = await UiPreferences.load(file: file);
      expect(reopened.videoOrder, PlayOrder.sequential);
      expect(reopened.dark, isTrue);
      expect(reopened.preloadAdjacent, isFalse);
      preferences.dispose();
      reopened.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('failed preference writes retain the previous values and do not break a later change', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vv-default-failure-',
    );
    final blocked = await Directory('${directory.path}/appearance.json')
        .create();
    final file = File(blocked.path);
    final preferences = UiPreferences(file: file);
    try {
      await expectLater(
        preferences.setVideoOrder(PlayOrder.sequential),
        throwsA(isA<FileSystemException>()),
      );
      expect(preferences.videoOrder, isNull);
      expect(preferences.dark, isFalse);
      await blocked.delete();
      await preferences.setDark(true);
      await preferences.setVideoOrder(PlayOrder.sequential);
      final reopened = await UiPreferences.load(file: file);
      expect(reopened.dark, isTrue);
      expect(reopened.videoOrder, PlayOrder.sequential);
      reopened.dispose();
    } finally {
      preferences.dispose();
      await directory.delete(recursive: true);
    }
  });
}
