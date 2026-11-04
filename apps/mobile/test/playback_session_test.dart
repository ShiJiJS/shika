import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:shika/ui/playback_session.dart';

/// Native commands are represented by delayed acknowledgements. The tests
/// observe audible handover and resource ownership, not widget internals.
class SimulatedPlayer extends VideoPlayerController {
  SimulatedPlayer(this.name) : super.asset(name) {
    value = VideoPlayerValue(
      duration: const Duration(seconds: 10),
      isInitialized: true,
    );
  }
  final String name;
  final events = <String>[];
  Future<void>? pauseGate;
  bool nativePlaying = false, released = false;
  @override
  Future<void> pause() async {
    await pauseGate;
    events.add('pause');
    nativePlaying = false;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> play() async {
    events.add('play');
    nativePlaying = true;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);
  @override
  Future<void> seekTo(Duration position) async =>
      value = value.copyWith(position: position);
  @override
  Future<void> dispose() async {
    released = true;
    nativePlaying = false;
    super.dispose();
  }
}

void main() {
  test(
    'late invalid initialization cannot pause or replace the current selection',
    () async {
      final session = PlaybackSession();
      final current = SimulatedPlayer('current'),
          obsolete = SimulatedPlayer('obsolete');
      await session.attach(current);
      await session.attach(obsolete);
      await session.select(current, valid: () => true);
      final pauses = current.events.where((e) => e == 'pause').length;
      await session.select(obsolete, valid: () => false);
      expect(current.nativePlaying, isTrue);
      expect(current.value.volume, 1);
      expect(current.events.where((e) => e == 'pause').length, pauses);
      expect(obsolete.nativePlaying, isFalse);
      await session.close();
    },
  );
  test('current initialization and a paused current page survive adjacent eviction', () async {
    final session = PlaybackSession();
    final current = SimulatedPlayer('current');
    final neighbors = List.generate(3, (i) => SimulatedPlayer('neighbor$i'));
    await session.attach(current, current: true);
    await session.attach(neighbors[0]);
    await session.attach(neighbors[1]);
    await session.silence(current);
    await session.attach(neighbors[2]);
    expect(current.released, isFalse);
    expect(neighbors[0].released, isTrue);
    expect(session.debugPlayers, hasLength(3));
    await session.close();
  });
  test('new audio waits for the old native pause acknowledgement', () async {
    final session = PlaybackSession();
    final first = SimulatedPlayer('a'), second = SimulatedPlayer('b');
    await session.attach(first);
    await session.attach(second);
    await session.select(first, valid: () => true);
    final pause = Completer<void>();
    first.pauseGate = pause.future;
    final handover = session.select(second, valid: () => true);
    await Future<void>.delayed(Duration.zero);
    expect(first.nativePlaying, isTrue);
    expect(second.nativePlaying, isFalse);
    pause.complete();
    await handover;
    expect(first.nativePlaying, isFalse);
    expect(first.value.volume, 0);
    expect(second.nativePlaying, isTrue);
    await session.close();
  });

  test(
    'superseding a delayed handover never starts the intermediate video',
    () async {
      final session = PlaybackSession();
      final first = SimulatedPlayer('a'),
          obsolete = SimulatedPlayer('b'),
          latest = SimulatedPlayer('c');
      for (final player in [first, obsolete, latest]) {
        await session.attach(player);
      }
      await session.select(first, valid: () => true);
      final pause = Completer<void>();
      first.pauseGate = pause.future;
      final old = session.select(obsolete, valid: () => true);
      await Future<void>.delayed(Duration.zero);
      final newest = session.select(latest, valid: () => true);
      pause.complete();
      await Future.wait([old, newest]);
      expect(obsolete.events, isNot(contains('play')));
      expect(latest.nativePlaying, isTrue);
      expect(first.nativePlaying, isFalse);
      await session.close();
    },
  );

  test('decoder cap protects the current video and closing rejects late preparation', () async {
    final session = PlaybackSession();
    final players = List.generate(5, (i) => SimulatedPlayer('$i'));
    for (final player in players.take(3)) {
      await session.attach(player);
    }
    await session.select(players.first, valid: () => true);
    await session.attach(players[3]);
    expect(players.first.released, isFalse);
    expect(players[1].released, isTrue);
    expect(session.debugPlayers, hasLength(3));
    await session.close();
    expect(await session.attach(players.last), isFalse);
    expect(players.every((p) => p.released), isTrue);
    expect(session.debugPlayers, isEmpty);
  });
}
