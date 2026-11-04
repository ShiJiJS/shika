import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/backup_document.dart';
import 'package:shika/library/backup_file_picker.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/request_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('isolated/backup_files');
  const picker = NativeBackupArchiveFiles(channel: channel);
  late Directory directory;
  late BackupFileStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-file-contract-');
    store = BackupFileStore(directory, owner: 'origin:epoch');
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
  void handler(Future<Object?> Function(MethodCall) action) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, action);
  test(
    'picker exchanges only limits, paths, ownership and scalar descriptors',
    () async {
      final document = await store.capture(
        Stream.value([1, 2, 3]),
        maximumBytes: 100,
      );
      final calls = <MethodCall>[];
      handler((call) async {
        calls.add(call);
        return call.method == 'pick' ? document.toJson() : false;
      });
      final selected = await picker.pick(store, maximumBytes: 64 * 1024 * 1024);
      expect(selected!.sha256, document.sha256);
      expect(await picker.save(selected), isFalse);
      expect(await File(document.path).readAsBytes(), [1, 2, 3]);
      expect(calls.map((v) => v.method), ['pick', 'save']);
      for (final call in calls) {
        expect(
          (call.arguments as Map).values.any(
            (v) => v is Uint8List || v is List<int>,
          ),
          isFalse,
        );
      }
      expect((calls[1].arguments as Map)['bytes'], 3);
    },
  );
  test('cancelling a late picker handoff cleans its owned file and sends the same identity', () async {
    final document = await store.capture(
      Stream.value([1, 2, 3]),
      maximumBytes: 100,
    );
    final started = Completer<void>(),
        cancelled = Completer<void>(),
        reply = Completer<Object?>();
    String? identity;
    handler((call) async {
      if (call.method == 'pick') {
        identity = (call.arguments as Map)['id'];
        started.complete();
        return reply.future;
      }
      expect((call.arguments as Map)['id'], identity);
      cancelled.complete();
      return null;
    });
    final scope = RequestScope();
    final work = picker.pick(store, maximumBytes: 100, scope: scope);
    final assertion = expectLater(work, throwsA(isA<RequestCancelled>()));
    await started.future;
    scope.cancel();
    await cancelled.future;
    reply.complete(document.toJson());
    await assertion;
    expect(await File(document.path).exists(), isFalse);
  });
  test('changed native file, wrong owner and too-large descriptor never return a selected file', () async {
    final document = await store.capture(
      Stream.value([1, 2, 3]),
      maximumBytes: 100,
    );
    handler((_) async => document.toJson());
    await expectLater(
      picker.pick(store, maximumBytes: 2),
      throwsA(isA<LibraryFailure>()),
    );
    expect(await File(document.path).exists(), isFalse);
    handler((_) async => {...document.toJson(), 'owner': 'another-origin'});
    await expectLater(
      picker.pick(store, maximumBytes: 100),
      throwsA(isA<LibraryFailure>()),
    );
  });
  test(
    'native failure is translated without exposing platform diagnostics',
    () async {
      handler(
        (_) async => throw PlatformException(
          code: 'BACKUP_FILE_IO',
          message: '/private/path/provider stack',
        ),
      );
      await expectLater(
        picker.pick(store, maximumBytes: 100),
        throwsA(
          isA<LibraryFailure>().having(
            (e) => e.message.contains('/private/path'),
            'safe message',
            isFalse,
          ),
        ),
      );
    },
  );
}
