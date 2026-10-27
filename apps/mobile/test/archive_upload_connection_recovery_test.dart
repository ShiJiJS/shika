import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/backup_document.dart';
import 'package:video_viewer/library/backup_work_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/library/server_backups.dart';

void main() {
  test('a real refused upload survives reopening and missing-original reads without any replay', () async {
    final directory = await Directory.systemTemp.createTemp('archive-refused-');
    final files = BackupFileStore(directory, owner: 'isolated:original-epoch');
    final document = await files.capture(
      Stream.value(utf8.encode('owned fixture\n')),
      maximumBytes: 1024,
    );
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final journal = MemoryBackupWorkStore();
    final status = ValueNotifier<String?>(null);
    ServerApi api = ServerApi(Uri.parse('http://127.0.0.1:$port'));
    ServerBackups makeClient() => ServerBackups(
      api: api,
      scope: files.owner,
      store: journal,
      status: status,
      onChanged: () {},
      onRestored: () async {},
    );
    var client = makeClient();
    addTearDown(() async {
      client.dispose();
      api.close();
      status.dispose();
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    await client.initialize();
    await expectLater(
      client.inspectDocument(document),
      throwsA(
        isA<ApiFailure>()
            .having((e) => e.code, 'code', 'network_unavailable')
            .having((e) => e.transportPhase, 'phase', ApiTransportPhase.opening)
            .having((e) => e.transportCause, 'cause', isA<SocketException>()),
      ),
    );
    final saved = journal.value!;
    final command = (jsonDecode(saved) as Map)['inspect'] as Map;
    final key = command['key'] as String;
    expect(command['file'], document.toJson());
    expect(command['task'], isNull);
    await document.delete();
    client.dispose();
    api.close();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final requests = <String>[];
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      request.response.statusCode = 404;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': {
            'code': 'backup_request_not_found',
            'message': '未找到原管理请求；没有补执行',
          },
        }),
      );
      await request.response.close();
    });
    api = ServerApi(Uri.parse('http://127.0.0.1:$port'));
    client = makeClient();
    await client.initialize();
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(
        client.resumeDocumentPreview(),
        throwsA(
          isA<LibraryFailure>().having(
            (e) => e.message,
            'original retained',
            allOf(contains('原记录已保留'), contains('没有重新提交')),
          ),
        ),
      );
      expect(journal.value, saved);
      expect(client.pendingReceipts.single['kind'], 'inspect');
      expect(client.pendingReceipts.single['key'], key);
    }
    expect(
      requests,
      List.filled(2, 'GET /api/v1/management-backups/requests/inspect/$key'),
    );
    debugPrint(
      'ARCHIVE_REFUSED_UPLOAD_VERIFIED:${jsonEncode({'original_key': key, 'file_sha256': document.sha256, 'phase': 'opening', 'cause': 'SocketException', 'original_reads': requests.length, 'posts_after_reopening': 0, 'journal_unchanged': true, 'local_file_removed': true})}',
    );
  });
}
