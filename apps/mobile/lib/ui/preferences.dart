import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../library/models.dart';

class UiPreferences extends ChangeNotifier {
  factory UiPreferences({
    File? file,
    bool dark = false,
    bool preloadAdjacent = true,
    PlayOrder? videoOrder,
    Set<String> migratedDefaults = const {},
    bool onboardingComplete = false,
  }) => UiPreferences._(
    file,
    dark,
    preloadAdjacent,
    videoOrder,
    migratedDefaults,
    onboardingComplete,
  );
  UiPreferences._(
    this._file,
    this._dark,
    this._preloadAdjacent,
    this._videoOrder,
    Set<String> migratedDefaults,
    this._onboardingComplete,
  ) : _migratedDefaults = Set.of(migratedDefaults);
  final File? _file;
  bool _dark;
  bool get dark => _dark;
  bool _onboardingComplete;
  bool get onboardingComplete => _onboardingComplete;
  bool _preloadAdjacent;
  bool get preloadAdjacent => _preloadAdjacent;
  PlayOrder? _videoOrder;
  PlayOrder? get videoOrder => _videoOrder;
  Set<String> _migratedDefaults;
  bool defaultMigrationDone(String scope) => _migratedDefaults.contains(scope);
  Future<void> _changes = Future.value();

  static Future<UiPreferences> load({File? file}) async {
    file ??= File(
      '${(await getApplicationSupportDirectory()).path}/appearance.json',
    );
    var dark = false;
    var preload = true;
    PlayOrder? order;
    Set<String> migrated = {};
    var onboardingComplete = false;
    try {
      if (await file.exists()) {
        final saved = jsonDecode(await file.readAsString());
        dark = saved is Map && saved['dark'] == true;
        preload = saved is! Map || saved['preloadAdjacent'] != false;
        if (saved is Map) {
          onboardingComplete = saved['onboardingComplete'] == true;
          migrated = (saved['defaultMigrations'] is List
              ? (saved['defaultMigrations'] as List).whereType<String>().toSet()
              : <String>{});
          order = PlayOrder.values
              .where((value) => value.name == saved['videoOrder'])
              .firstOrNull;
        }
      }
    } on FormatException {
      // An incomplete preference file falls back to the default appearance.
    } on FileSystemException {
      // The app can still open; a later failed save is reported by the UI.
    }
    return UiPreferences(
      file: file,
      dark: dark,
      preloadAdjacent: preload,
      videoOrder: order,
      migratedDefaults: migrated,
      onboardingComplete: onboardingComplete,
    );
  }

  Future<void> setDark(bool value) => _update(dark: value);
  Future<void> completeOnboarding() => _update(onboarding: true);

  Future<void> setPreloadAdjacent(bool value) => _update(preload: value);
  Future<void> setVideoOrder(PlayOrder value) => _update(videoOrder: value);
  Future<void> ensureVideoOrder(PlayOrder value) =>
      _update(videoOrder: value, onlyIfMissing: true);
  Future<void> markDefaultMigration(String scope) => _update(migration: scope);

  Future<void> _update({
    bool? dark,
    bool? preload,
    PlayOrder? videoOrder,
    bool onlyIfMissing = false,
    String? migration,
    bool? onboarding,
  }) {
    final work = _changes.then((_) async {
      final nextDark = dark ?? _dark, nextPreload = preload ?? _preloadAdjacent;
      final nextOrder = onlyIfMissing
          ? _videoOrder ?? videoOrder
          : videoOrder ?? _videoOrder;
      final nextMigrations = {..._migratedDefaults, ?migration};
      final nextOnboarding = onboarding ?? _onboardingComplete;
      if (nextDark == _dark &&
          nextPreload == _preloadAdjacent &&
          nextOrder == _videoOrder &&
          setEquals(nextMigrations, _migratedDefaults) &&
          nextOnboarding == _onboardingComplete) {
        return;
      }
      await _file?.writeAsString(
        jsonEncode({
          'dark': nextDark,
          'preloadAdjacent': nextPreload,
          if (nextOrder != null) 'videoOrder': nextOrder.name,
          'defaultMigrations': nextMigrations.toList()..sort(),
          'onboardingComplete': nextOnboarding,
        }),
        flush: true,
      );
      _dark = nextDark;
      _preloadAdjacent = nextPreload;
      _videoOrder = nextOrder;
      _migratedDefaults = nextMigrations;
      _onboardingComplete = nextOnboarding;
      notifyListeners();
    });
    _changes = work.catchError((Object _) {});
    return work;
  }
}
