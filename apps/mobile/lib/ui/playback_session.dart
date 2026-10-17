import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Owns a bounded set of native decoders and serializes audible handover.
/// A late initialization can never resume a page that has lost selection.
class PlaybackSession {
  final Set<VideoPlayerController> _players = {};
  VideoPlayerController? _selected;
  // The visible decoder stays protected while initializing or temporarily paused.
  VideoPlayerController? _current;
  Future<void> _work = Future.value();
  int _revision = 0;
  bool _closed = false;

  bool contains(VideoPlayerController player) => _players.contains(player);
  @visibleForTesting
  List<VideoPlayerController> get debugPlayers => List.unmodifiable(_players);

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _work.then((_) => action());
    _work = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<bool> attach(VideoPlayerController player, {bool current = false}) {
    if (current) _current = player;
    return _enqueue(() async {
      if (_closed) {
        await player.dispose();
        return false;
      }
      if (_players.length >= 3) {
        final victim = _players.firstWhere(
          (item) => item != _selected && item != _current,
        );
        _players.remove(victim);
        await victim.dispose();
      }
      _players.add(player);
      return true;
    });
  }

  Future<void> select(
    VideoPlayerController player, {
    required bool Function() valid,
    bool play = true,
    bool rewind = false,
  }) {
    if (_closed ||
        !_players.contains(player) ||
        !player.value.isInitialized ||
        !valid()) {
      return Future.value();
    }
    _selected = player;
    _current = player;
    final revision = ++_revision;
    bool current() =>
        !_closed &&
        revision == _revision &&
        _selected == player &&
        _players.contains(player) &&
        valid();
    return _enqueue(() async {
      if (!current()) return;
      for (final other in _players.where((item) => item != player).toList()) {
        if (!current()) return;
        if (other.value.isInitialized) {
          await other.pause();
          await other.setVolume(0);
        }
      }
      if (!current() || !player.value.isInitialized) return;
      await player.setVolume(1);
      if (rewind && current()) await player.seekTo(Duration.zero);
      if (play && current()) await player.play();
      if (!current()) {
        await player.pause();
        await player.setVolume(0);
      }
    });
  }

  Future<void> silence(VideoPlayerController? player) {
    if (player == null) return Future.value();
    if (_selected == player) {
      _selected = null;
      _revision++;
    }
    return _enqueue(() async {
      if (_players.contains(player) && player.value.isInitialized) {
        await player.pause();
        await player.setVolume(0);
      }
    });
  }

  Future<void> release(VideoPlayerController? player) {
    if (player == null) return Future.value();
    if (_current == player) _current = null;
    if (_selected == player) {
      _selected = null;
      _revision++;
    }
    return _enqueue(() async {
      if (_players.remove(player)) await player.dispose();
    });
  }

  Future<void> close() {
    _closed = true;
    _selected = null;
    _current = null;
    _revision++;
    return _enqueue(() async {
      final players = _players.toList();
      _players.clear();
      for (final player in players) {
        await player.dispose();
      }
    });
  }
}
