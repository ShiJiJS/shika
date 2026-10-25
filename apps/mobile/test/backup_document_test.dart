import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/backup_document.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/request_scope.dart';

void main() {
  late Directory directory;
  late BackupFileStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-document-');
    store = BackupFileStore(
      Directory('${directory.path}/owned'),
      owner: 'service:epoch-A',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'actual over-32MiB file is chunked, hashed and reopened from a descriptor',
    () async {
      var chunks = 0;
      Stream<List<int>> source() async* {
        final buffer = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 83);
        for (var i = 0; i < 528; i++) {
          chunks++;
          yield buffer;
        }
        yield [1, 2, 3];
      }

      final document = await store.capture(
        source(),
        maximumBytes: 64 * 1024 * 1024,
      );
      expect(chunks, 528);
      expect(document.bytes, 33 * 1024 * 1024 + 3);
      expect(await File(document.path).length(), document.bytes);
      expect(
        (await sha256.bind(File(document.path).openRead()).first).toString(),
        document.sha256,
      );
      final reopened = store.restore(document.toJson());
      await reopened.verify();
      expect(reopened.path, document.path);
      expect(await store.directory.list().length, 1);
    },
  );

  test('size, declared length and digest mismatch publish no file', () async {
    for (final configuration in [
      {'maximumBytes': 2},
      {'maximumBytes': 10, 'expectedBytes': 4},
      {'maximumBytes': 10, 'expectedSha256': 'a' * 64},
    ]) {
      await expectLater(
        store.capture(
          Stream.value([1, 2, 3]),
          maximumBytes: configuration['maximumBytes'] as int,
          expectedBytes: configuration['expectedBytes'] as int?,
          expectedSha256: configuration['expectedSha256'] as String?,
        ),
        throwsA(isA<LibraryFailure>()),
      );
      expect(await store.directory.list().length, 0);
    }
  });

  test(
    'cancellation interrupts a stalled input and removes the partial file',
    () async {
      final received = Completer<void>();
      final incoming = StreamController<List<int>>();
      final scope = RequestScope();
      incoming.onListen = () {
        incoming.add([1, 2, 3]);
        received.complete();
      };
      final work = store.capture(
        incoming.stream,
        maximumBytes: 1024,
        scope: scope,
      );
      final assertion = expectLater(work, throwsA(isA<RequestCancelled>()));
      await received.future;
      scope.cancel();
      await assertion;
      expect(await store.directory.list().length, 0);
      await incoming.close();
    },
  );

  test(
    'changed, missing and symlinked private files cannot become uploads',
    () async {
      final document = await store.capture(
        Stream.value([1, 2, 3]),
        maximumBytes: 100,
      );
      await File(document.path).writeAsBytes([3, 2, 1]);
      await expectLater(document.verify(), throwsA(isA<LibraryFailure>()));
      await File(document.path).delete();
      await expectLater(document.verify(), throwsA(isA<LibraryFailure>()));
      final outside = await File('${directory.path}/outside')
          .writeAsBytes([1, 2, 3]);
      await Link(document.path).create(outside.path);
      await expectLater(document.verify(), throwsA(isA<LibraryFailure>()));
      await document.delete();
      expect(await outside.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'descriptor ownership and filename are validated before filesystem access',
    () async {
      final document = await store.capture(Stream.value([1]), maximumBytes: 10);
      for (final record in [
        {...document.toJson(), 'owner': 'other-server'},
        {...document.toJson(), 'id': '../outside'},
        {...document.toJson(), 'bytes': maximumBackupFileBytes + 1},
        {...document.toJson(), 'sha256': 'bad'},
      ]) {
        expect(() => store.restore(record), throwsA(isA<LibraryFailure>()));
      }
      await document.delete();
      // Keeping an original descriptor does not recreate a disappeared file.
      final original = store.restore(document.toJson());
      await expectLater(original.verify(), throwsA(isA<LibraryFailure>()));
      expect(await store.directory.list().length, 0);
    },
  );
}
