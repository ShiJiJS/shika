import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../library/server_api.dart' show ApiFailure;
import '../../ui/preferences.dart';

/// Reads and edits defaults, never the active viewing session or a pack override.
class DefaultSettingsSession extends ChangeNotifier {
  DefaultSettingsSession(this.repository, this.local, {required this.video}) {
    if (video) {
      playback = repository.createPlaybackDefaults();
    } else {
      reader = repository.createPackReader();
    }
    repository.addListener(ownerChanged);
  }
  final LibraryRepository repository;
  final UiPreferences local;
  final bool video;
  PlaybackDefaultsGateway? playback;
  PackReader? reader;
  PlaybackDefaults? savedPlayback;
  ReaderPreferences? savedReader;
  PlayOrder order = PlayOrder.random;
  ReaderPreferences preferences = const ReaderPreferences();
  WritePlaybackDefaults? _playbackCommand;
  WriteReaderDefaults? _readerCommand;
  bool busy = false, disposed = false, needsReload = false;
  String error = '';
  bool get current => video ? playback!.isCurrent : reader!.isCurrent;
  bool get ready => video ? savedPlayback != null : savedReader != null;
  bool get pending => _playbackCommand != null || _readerCommand != null;
  bool get blocked => busy || pending || needsReload || !current || !ready;
  bool get migrationOffered =>
      video &&
      local.videoOrder != null &&
      !local.defaultMigrationDone(playback!.scope);
  String get nonce =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  void changed() {
    if (!disposed) notifyListeners();
  }

  void ownerChanged() {
    if (!current) {
      error = '连接或管理数据已变化，请关闭后重新打开设置';
      changed();
    }
  }

  Future<void> load() async {
    if (busy || !current) return;
    busy = true;
    error = '';
    changed();
    try {
      if (video) {
        final value = await playback!.read();
        if (disposed || !current) return;
        savedPlayback = value;
        order = value.order;
      } else {
        final value = await reader!.defaults();
        if (disposed || !current) return;
        savedReader = value;
        preferences = value;
      }
      // An explicit read adopts authoritative current state. It never replays
      // an unknown write or reports that write as successful.
      _playbackCommand = null;
      _readerCommand = null;
      needsReload = false;
    } catch (e) {
      if (!disposed) error = e.toString();
    } finally {
      busy = false;
      changed();
    }
  }

  void selectOrder(PlayOrder value) {
    if (blocked) return;
    order = value;
    changed();
  }

  void selectPreferences(ReaderPreferences value) {
    if (blocked) return;
    preferences = value;
    changed();
  }

  Future<void> keepServer() async {
    if (blocked || !migrationOffered) return;
    busy = true;
    changed();
    try {
      await local.markDefaultMigration(playback!.scope);
      if (!disposed && current) order = savedPlayback!.order;
    } catch (e) {
      if (!disposed) error = '未能保存本机迁移选择：$e';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<bool> save({bool query = false}) async {
    if (busy ||
        !ready ||
        !current ||
        (query ? !pending : pending || needsReload)) {
      return false;
    }
    busy = true;
    error = '';
    if (!query) {
      if (video) {
        _playbackCommand = WritePlaybackDefaults(
          nonce,
          PlaybackDefaults(order, savedPlayback!.revision),
        );
      } else {
        _readerCommand = WriteReaderDefaults(nonce, preferences);
      }
    }
    changed();
    try {
      if (video) {
        final command = _playbackCommand!;
        final value = query
            ? await playback!.receipt(command)
            : await playback!.submit(command);
        if (disposed || !current) return false;
        if (value == null) {
          error = '暂未找到原设置请求。可以稍后继续查询，或读取服务端当前设置；不会自动重发。';
          return false;
        }
        savedPlayback = value;
        order = value.order;
      } else {
        final command = _readerCommand!;
        final value = query
            ? await reader!.receipt(command)
            : await reader!.submit(command);
        if (disposed || !current) return false;
        if (value == null) {
          error = '暂未找到原设置请求。可以稍后继续查询，或读取服务端当前设置；不会自动重发。';
          return false;
        }
        savedReader = value;
        preferences = value;
      }
      _playbackCommand = null;
      _readerCommand = null;
      if (video && migrationOffered) {
        try {
          await local.markDefaultMigration(playback!.scope);
        } catch (e) {
          error = '服务端设置已保存，但本机迁移标记未保存：$e';
          needsReload = true;
          return false;
        }
      }
      return !disposed && current;
    } catch (e) {
      if (!disposed) {
        final rejected =
            e is ApiFailure &&
            e.status != null &&
            e.status! >= 400 &&
            e.status! < 500 &&
            e.status != 408 &&
            e.status != 429;
        if (!query && rejected) {
          _playbackCommand = null;
          _readerCommand = null;
          needsReload = true;
        }
        error = pending ? '保存结果待核对：$e' : '$e';
      }
      return false;
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    disposed = true;
    repository.removeListener(ownerChanged);
    playback?.dispose();
    reader?.dispose();
    super.dispose();
  }
}
