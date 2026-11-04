import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/server_api.dart';

void main() {
  final old = 'a' * 32, fresh = 'b' * 32;
  late HttpServer server;
  late ServerApi api;
  var changed = 0, requests = 0;
  String? replyEpoch;
  var status = 200;
  final received = <String?>[];
  Completer<void>? entered, release;
  setUp(() async {
    changed = requests = 0;
    replyEpoch = old;
    status = 200;
    received.clear();
    entered = release = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ServerApi(
      Uri.parse('http://127.0.0.1:${server.port}'),
      token: 'isolated-token',
    );
    api.bindAuthority({
      'capabilities': ['management_authority'],
      'management_epoch': old,
    });
    api.onManagementChanged = () => changed++;
    server.listen((request) async {
      requests++;
      received.add(request.headers.value('X-Management-Epoch'));
      final captured = replyEpoch;
      if (request.uri.path.endsWith('/delayed')) {
        entered!.complete();
        await release!.future;
      }
      if (captured != null) {
        request.response.headers.set('X-Management-Epoch', captured);
      }
      request.response.statusCode = status;
      request.response.write(
        jsonEncode(
          status == 200
              ? {'id': 'original', 'old_payload': true}
              : {
                  'error': {
                    'code': status == 401
                        ? 'unauthorized'
                        : 'management_changed',
                    'message': '原请求未执行',
                  },
                },
        ),
      );
      try {
        await request.response.close();
      } on IOException {
        /* cancelled read */
      }
    });
  });
  tearDown(() async {
    if (release?.isCompleted == false) release!.complete();
    api.close();
    await server.close(force: true);
  });
  test(
    'captured headers cannot be replaced or rebound and legacy omits them',
    () async {
      await api.json('GET', '/read');
      expect(received, [old]);
      expect(
        () => api.bindAuthority({
          'capabilities': ['management_authority'],
          'management_epoch': fresh,
        }),
        throwsStateError,
      );
      await expectLater(
        api.request('POST', '/write', headers: {'x-management-epoch': fresh}),
        throwsArgumentError,
      );
      final legacy = ServerApi(api.endpoint, token: 'isolated-token');
      try {
        legacy.bindAuthority({'capabilities': []});
        await legacy.json('GET', '/read');
        expect(received.last, isNull);
      } finally {
        legacy.close();
      }
    },
  );
  test('malformed advertised authority cannot bind a connection', () {
    for (final value in [null, 'short', 'A' * 32]) {
      expect(
        () => api.bindAuthority({
          'capabilities': ['management_authority'],
          'management_epoch': value,
        }),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(requests, 0);
  });
  test('changed successful response is unknown, freezes writes, and never resubmits', () async {
    replyEpoch = fresh;
    await expectLater(
      api.json('POST', '/write', body: {'request_id': 'original'}),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.code, 'code', 'management_changed')
            .having((e) => e.status, 'status', isNull),
      ),
    );
    expect(changed, 1);
    expect(requests, 1);
    expect(api.managementEpoch, old);
    await expectLater(
      api.json('POST', '/write', body: {'request_id': 'original'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests, 1);
    final value = await api.json(
      'GET',
      '/api/v1/tasks/original',
      originalReceipt: true,
    );
    expect(value['id'], 'original');
    expect(received.last, old);
    expect(changed, 1);
  });
  test('a late old payload is rejected after another response observed the replacement', () async {
    entered = Completer();
    release = Completer();
    final delayed = api.json('GET', '/delayed');
    final assertion = expectLater(
      delayed,
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'management_changed'),
      ),
    );
    await entered!.future;
    replyEpoch = fresh;
    await expectLater(api.json('GET', '/read'), throwsA(isA<ApiFailure>()));
    release!.complete();
    await assertion;
    expect(changed, 1);
    expect(requests, 2);
  });
  test('original reads may cross epoch without adopting it or notifying a restore twice', () async {
    replyEpoch = fresh;
    expect(
      (await api.json(
        'GET',
        '/api/v1/backup-requests/restore/key',
        originalReceipt: true,
      ))['id'],
      'original',
    );
    expect(changed, 0);
    expect(api.managementEpoch, old);
    await expectLater(
      api.json('POST', '/api/v1/tasks/original', originalReceipt: true),
      throwsArgumentError,
    );
    await expectLater(
      api.json('GET', '/api/v1/videos', originalReceipt: true),
      throwsArgumentError,
    );
    expect(requests, 1);
  });
  test(
    'a real 409 rejection stays distinct from an unknown successful write',
    () async {
      replyEpoch = fresh;
      status = 409;
      await expectLater(
        api.json('POST', '/write'),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
      );
      expect(changed, 1);
      expect(requests, 1);
    },
  );
  test(
    'missing authority never publishes data or clears a receipt as rejected',
    () async {
      for (final invalid in <String?>[null, 'broken']) {
        replyEpoch = invalid;
        await expectLater(
          api.json('POST', '/write'),
          throwsA(
            isA<ApiFailure>()
                .having((e) => e.code, 'code', 'authority_unavailable')
                .having((e) => e.status, 'status', isNull),
          ),
        );
      }
      expect(changed, 0);
      replyEpoch = old;
      expect((await api.json('GET', '/read'))['id'], 'original');
    },
  );
  test(
    '401 remains credential expiry even without an authority header',
    () async {
      replyEpoch = null;
      status = 401;
      await expectLater(
        api.json('GET', '/read'),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
      );
      expect(changed, 0);
    },
  );
}
