import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/settings/default_settings_session.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/pack_reading.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'server_pack_reading_test.dart' show ReadingServer;

typedef Json = Map<String, dynamic>;

class DefaultsServer {
  final reading = ReadingServer();
  Json value = {'order': 'sequential', 'revision': 0};
  final receipts = <String, Json>{};
  bool loseReply = false, missing = false, badReply = false;
  Completer<void>? readStarted, releaseRead;
  int patches = 0, queries = 0;
  Future<void> start() async {
    await reading.start();
    final original = reading.fixture.handle;
    reading.fixture.handle = (r, body) async {
      final path = r.uri.path;
      if (path.endsWith('/info')) {
        return (
          status: 200,
          body: {
            'api_version': 1,
            'server_id': 'packs',
            'capabilities': [
              'image_packs',
              'pack_reading_sessions',
              'managed_playback_defaults',
            ],
          },
        );
      }
      if (path.endsWith('/playback-defaults')) {
        if (r.method == 'GET') {
          if (readStarted != null && !readStarted!.isCompleted) {
            readStarted!.complete();
            await releaseRead!.future;
          }
          return (status: 200, body: Map<String, dynamic>.from(value));
        }
        patches++;
        if (body['expected_revision'] != value['revision']) {
          return (
            status: 409,
            body: {
              'error': {
                'code': 'playback_defaults_changed',
                'message': '设置已更新',
              },
            },
          );
        }
        value = {'order': body['order'], 'revision': value['revision'] + 1};
        receipts[body['request_id']] = Map<String, dynamic>.from(value);
        if (loseReply) {
          loseReply = false;
          return (
            status: 503,
            body: {
              'error': {'code': 'lost', 'message': '回执丢失'},
            },
          );
        }
        return (
          status: 200,
          body: badReply
              ? {...value, 'revision': 99}
              : Map<String, dynamic>.from(value),
        );
      }
      if (path.contains('/playback-default-requests/')) {
        queries++;
        final result = receipts[path.split('/').last];
        if (missing || result == null) {
          return (
            status: 404,
            body: {
              'error': {'code': 'defaults_request_not_found', 'message': '未找到'},
            },
          );
        }
        return (status: 200, body: {'status': 'completed', 'result': result});
      }
      return original?.call(r, body);
    };
  }

  Future<void> close() async {
    if (releaseRead != null && !releaseRead!.isCompleted) {
      releaseRead!.complete();
    }
    await reading.fixture.server.close(force: true);
  }

  Future<void> connect(ServerLibraryRepository repo) =>
      repo.connect('http://127.0.0.1', reading.fixture.server.port, 'fixture');
}

void main() {
  late DefaultsServer server;
  late ServerLibraryRepository repo;
  late UiPreferences local;
  final sessions = <DefaultSettingsSession>[];
  setUp(() async {
    server = DefaultsServer();
    await server.start();
    repo = ServerLibraryRepository(MemoryCredentialStore());
    await server.connect(repo);
    local = UiPreferences(videoOrder: PlayOrder.random);
  });
  tearDown(() async {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    repo.dispose();
    local.dispose();
    await server.close();
  });
  DefaultSettingsSession session({bool video = true}) {
    final value = DefaultSettingsSession(repo, local, video: video);
    sessions.add(value);
    return value;
  }

  test('server default owns new entries; explicit migration preserves active playback and old-service preference', () async {
    final oldIdentity = repo.playbackIdentity, oldOrder = repo.snapshot.order;
    final s = session();
    await s.load();
    expect(s.order, PlayOrder.sequential);
    expect(s.migrationOffered, isTrue);
    expect(server.patches, 0);
    expect(
      await repo.defaultVideoOrder(PlayOrder.random),
      PlayOrder.sequential,
    );
    s.selectOrder(local.videoOrder!);
    expect(await s.save(), isTrue);
    expect(server.value, {'order': 'random', 'revision': 1});
    expect(s.migrationOffered, isFalse);
    expect(local.videoOrder, PlayOrder.random);
    expect(repo.playbackIdentity, oldIdentity);
    expect(repo.snapshot.order, oldOrder);
    expect(
      server.reading.fixture.writes.where((w) => w.path.endsWith('/rounds')),
      isEmpty,
    );
  });
  test('lost accepted reply and unknown receipt never resubmit; original valid receipt settles it', () async {
    final s = session();
    await s.load();
    server.loseReply = true;
    s.selectOrder(PlayOrder.random);
    expect(await s.save(), isFalse);
    expect(s.pending, isTrue);
    expect(await s.save(), isFalse);
    server.missing = true;
    expect(await s.save(query: true), isFalse);
    expect(s.pending, isTrue);
    expect(server.patches, 1);
    server.missing = false;
    expect(await s.save(query: true), isTrue);
    expect(server.queries, 2);
    expect(server.patches, 1);
  });
  test('concurrent default revision conflict requires explicit re-read before any new save', () async {
    final first = session(), second = session();
    await first.load();
    await second.load();
    first.selectOrder(PlayOrder.random);
    expect(await first.save(), isTrue);
    expect(await second.save(), isFalse);
    expect(second.pending, isFalse);
    expect(second.needsReload, isTrue);
    expect(await second.save(), isFalse);
    expect(server.patches, 2);
    await second.load();
    expect(second.order, PlayOrder.random);
    second.selectOrder(PlayOrder.sequential);
    expect(await second.save(), isTrue);
    expect(server.value['revision'], 2);
  });
  test('invalid success acknowledgement stays unknown until the original receipt is verified', () async {
    final s = session();
    await s.load();
    server.badReply = true;
    s.selectOrder(PlayOrder.random);
    expect(await s.save(), isFalse);
    expect(s.pending, isTrue);
    expect(await s.save(query: true), isTrue);
    expect(server.patches, 1);
  });
  test('connection switch rejects late settings and isolates migration choices by endpoint and server', () async {
    final s = session();
    await s.load();
    await s.keepServer();
    expect(s.migrationOffered, isFalse);
    final gateway = repo.createPlaybackDefaults();
    server.readStarted = Completer();
    server.releaseRead = Completer();
    final old = gateway.read();
    final cancelled = expectLater(
      old,
      throwsA(anyOf(isA<RequestCancelled>(), isA<ApiFailure>())),
    );
    await server.readStarted!.future;
    final other = DefaultsServer();
    await other.start();
    try {
      await other.connect(repo);
      server.releaseRead!.complete();
      await cancelled;
      expect(s.current, isFalse);
      expect(await s.save(), isFalse);
      final next = session();
      await next.load();
      expect(next.migrationOffered, isTrue);
      expect(other.patches, 0);
    } finally {
      gateway.dispose();
      await other.close();
    }
  });
  test('reader defaults use existing request protocol without opening a pack or changing playback', () async {
    final identity = repo.playbackIdentity;
    final s = session(video: false);
    await s.load();
    s.selectPreferences(
      s.preferences.copy(
        mode: ReaderMode.vertical,
        direction: ReaderDirection.rtl,
        gap: true,
      ),
    );
    server.reading.loseReply = true;
    expect(await s.save(), isFalse);
    expect(s.pending, isTrue);
    expect(await s.save(query: true), isTrue);
    expect(s.preferences.revision, 1);
    expect(repo.playbackIdentity, identity);
    final writes = server.reading.fixture.writes;
    expect(
      writes.where((w) => w.path.endsWith('/reading-defaults')),
      hasLength(1),
    );
    expect(
      writes.where(
        (w) =>
            w.path.contains('/pack-sessions') ||
            w.path.endsWith('/preferences'),
      ),
      isEmpty,
    );
  });
}
