import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/library/backup_file_picker.dart';
import 'package:shika/library/request_scope.dart';
import 'package:shika/library/models.dart';

/// Driven with the real Android DocumentsUI; no method-channel or picker mock.
/// Stage lines coordinate external UI actions. Uses an isolated private owner.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real SAF cancellation, large save, pick, bounds and late cancel',
    (t) async {
      const gateway = NativeBackupArchiveFiles();
      final store = await NativeBackupArchiveFiles.storeFor(
        'native-files-isolated',
      );
      await store.directory.create(recursive: true);
      final document = await store.capture(
        Stream.fromIterable(
          Iterable.generate(641, (n) => List<int>.filled(65536, n % 251)),
        ),
        maximumBytes: 48 * 1024 * 1024,
      );
      addTearDown(() async {
        await document.delete();
      });
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Android 备份文件流程验证'))),
      );
      Future<T> stage<T>(String name, Future<T> Function() action) async {
        debugPrint('SAF_STAGE:$name');
        final outcome = await t.runAsync(() async {
          try {
            return (value: await action(), error: null, trace: null);
          } catch (error, trace) {
            return (value: null, error: error, trace: trace);
          }
        });
        if (outcome!.error case final Object error) {
          debugPrint('SAF_EXPECTED_ERROR:$name');
          Error.throwWithStackTrace(error, outcome.trace!);
        }
        debugPrint('SAF_DONE:$name');
        return outcome.value as T;
      }

      expect(await stage('cancel-save', () => gateway.save(document)), isFalse);
      await document.verify();
      expect(await stage('save-large', () => gateway.save(document)), isTrue);
      await document.verify();
      expect(
        await stage(
          'cancel-pick',
          () => gateway.pick(store, maximumBytes: 48 * 1024 * 1024),
        ),
        isNull,
      );
      final selected = await stage(
        'pick-large',
        () => gateway.pick(store, maximumBytes: 48 * 1024 * 1024),
      );
      expect(selected, isNotNull);
      expect(selected!.bytes, document.bytes);
      expect(selected.sha256, document.sha256);
      await selected.verify();
      await selected.delete();
      final before = await store.directory.list().map((f) => f.path).toSet();
      await expectLater(
        stage('pick-over-limit', () => gateway.pick(store, maximumBytes: 4096)),
        throwsA(anything),
      );
      expect(await store.directory.list().map((f) => f.path).toSet(), before);
      final scope = RequestScope();
      await stage('programmatic-cancel', () async {
        final timer = Timer(const Duration(seconds: 2), scope.cancel);
        try {
          await expectLater(
            gateway.pick(store, maximumBytes: 4096, scope: scope),
            throwsA(isA<RequestCancelled>()),
          );
        } finally {
          timer.cancel();
        }
      });
      await document.verify();
      debugPrint(
        'SAF_VERIFIED:bytes=${document.bytes},sha256=${document.sha256}',
      );
      expect(await File(document.path).exists(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
