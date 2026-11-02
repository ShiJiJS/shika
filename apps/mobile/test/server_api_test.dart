import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_api.dart';

void main() {
  late HttpServer server;
  late ServerApi api;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ServerApi(
      Uri.parse('http://127.0.0.1:${server.port}'),
      token: 'isolated-session',
    );
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
  });

  void respond(Future<void> Function(HttpRequest) handler) {
    server.listen((request) async {
      try {
        await handler(request);
      } on IOException {
        // Expected when the caller cancels a real response mid-transfer.
      }
    });
  }

  test(
    'real HTTP sends header authentication, preserves AND query and JSON body',
    () async {
      final received = Completer<Map<String, Object?>>();
      respond((request) async {
        received.complete({
          'authenticated':
              request.headers.value('authorization') ==
              'Bearer isolated-session',
          'tags': request.uri.queryParametersAll['tag_ids'],
          'body': jsonDecode(await utf8.decoder.bind(request).join()),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'id': 'accepted', 'items': []}));
        await request.response.close();
      });
      final result = await api.json(
        'POST',
        '/api/v1/query',
        query: {
          'tag_ids': ['one', 'two'],
        },
        body: {'request_id': 'test-request'},
      );
      expect(result['id'], 'accepted');
      final actual = await received.future;
      expect(actual['authenticated'], isTrue);
      expect(actual['tags'], ['one', 'two']);
      expect(actual['body'], {'request_id': 'test-request'});
    },
  );

  test(
    'HTTP errors expose safe structured messages and credential expiry',
    () async {
      respond((request) async {
        request.response.statusCode = 401;
        request.response.write(
          jsonEncode({
            'error': {'code': 'unauthorized', 'message': '请重新连接'},
          }),
        );
        await request.response.close();
      });
      await expectLater(
        api.json('GET', '/api/v1/info'),
        throwsA(
          isA<ApiFailure>()
              .having((error) => error.status, 'status', 401)
              .having((error) => error.code, 'code', 'unauthorized')
              .having((error) => error.message, 'message', '请重新连接'),
        ),
      );
    },
  );

  test('a truncated GET retries once on a new connection', () async {
    var requests = 0;
    final sockets = <Socket>[];
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    raw.listen((socket) {
      sockets.add(socket);
      requests++;
      final first = requests == 1;
      var sent = false;
      socket.listen((_) async {
        if (sent) return;
        sent = true;
        final body = first ? '{' : '{"fresh":true}';
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: ${first ? 32 : body.length}\r\nConnection: close\r\n\r\n$body',
        );
        await socket.flush();
        socket.destroy();
      }, onError: (Object _) {});
    });
    api.close();
    api = ServerApi(Uri.parse('http://127.0.0.1:${raw.port}'));
    try {
      expect(await api.json('GET', '/read'), {'fresh': true});
      expect(requests, 2);
    } finally {
      for (final socket in sockets) {
        socket.destroy();
      }
      await raw.close();
    }
  });

  test(
    'a lost write response is not automatically replayed by transport',
    () async {
      var requests = 0;
      respond((request) async {
        requests++;
        (await request.response.detachSocket(writeHeaders: false)).destroy();
      });
      await expectLater(
        api.json('POST', '/write', body: {'request_id': 'isolated'}),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'code',
            'network_unavailable',
          ),
        ),
      );
      expect(requests, 1);
    },
  );

  test('deadline ends a stalled real response', () async {
    final release = Completer<void>();
    respond((request) async {
      request.response.write('{');
      await request.response.flush();
      await release.future;
      await request.response.close();
    });
    try {
      await expectLater(
        api.request('GET', '/slow', timeout: const Duration(milliseconds: 150)),
        throwsA(
          isA<ApiFailure>().having((error) => error.code, 'code', 'timeout'),
        ),
      );
    } finally {
      release.complete();
    }
  });

  test('a refused connection retains its cause and phase without exposing it in the message', () async {
    final unavailable = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = unavailable.port;
    await unavailable.close();
    api.close();
    api = ServerApi(Uri.parse('http://127.0.0.1:$port'));
    await expectLater(
      api.json('POST', '/write', body: {'request_id': 'original'}),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.code, 'code', 'network_unavailable')
            .having((e) => e.transportPhase, 'phase', ApiTransportPhase.opening)
            .having((e) => e.transportCause, 'cause', isA<SocketException>())
            .having((e) => e.message, 'safe message', '暂时无法连接服务，请检查地址和网络后重试'),
      ),
    );
  });

  test(
    'scope cancellation ends obsolete work after response headers',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      respond((request) async {
        request.response.write('{');
        await request.response.flush();
        started.complete();
        await release.future;
        await request.response.close();
      });
      final scope = RequestScope();
      final result = api.request('GET', '/obsolete', scope: scope);
      final assertion = expectLater(result, throwsA(isA<RequestCancelled>()));
      try {
        await started.future;
        scope.cancel();
        await assertion;
      } finally {
        release.complete();
      }
    },
  );

  test(
    'response size is bounded and a subsequent request still works',
    () async {
      respond((request) async {
        request.response.write(
          request.uri.path == '/large' ? 'x' * 65536 : '{}',
        );
        await request.response.close();
      });
      await expectLater(
        api.request('GET', '/large', maximumBytes: 16),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.code,
            'code',
            'response_too_large',
          ),
        ),
      );
      expect(await api.json('GET', '/small'), isEmpty);
    },
  );

  test(
    'redirects and media URLs cannot forward authentication to another origin',
    () async {
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var otherRequests = 0;
      other.listen((request) {
        otherRequests++;
        request.response.close();
      });
      respond((request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${other.port}/target',
        );
        await request.response.close();
      });
      try {
        await expectLater(
          api.json('GET', '/redirect'),
          throwsA(
            isA<ApiFailure>().having((error) => error.status, 'status', 302),
          ),
        );
        expect(
          () => api.resolve('http://127.0.0.1:${other.port}/media'),
          throwsA(isA<ApiFailure>()),
        );
        expect(otherRequests, 0);
      } finally {
        await other.close(force: true);
      }
    },
  );

  test(
    'credential record stores a revocable session without a passphrase field',
    () async {
      final credentials = ConnectionCredentials(
        endpoint: api.endpoint,
        token: 'isolated-session',
        serverId: 'isolated-server',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      final store = MemoryCredentialStore();
      await store.save(credentials);
      expect((await store.read())?.serverId, 'isolated-server');
      final record = jsonDecode(credentials.encode()) as Map;
      expect(record.keys.toSet(), {
        'endpoint',
        'token',
        'serverId',
        'expiresAt',
      });
      expect(
        ConnectionCredentials.decode(credentials.encode())?.endpoint,
        api.endpoint,
      );
      expect(ConnectionCredentials.decode('{bad'), isNull);
      await store.clear();
      expect(await store.read(), isNull);
    },
  );
}
