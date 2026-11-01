import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/library/catalog_selection.dart';
import 'package:video_viewer/library/models.dart';

void main() {
  late CatalogSelection selection;
  late Object owner;
  late int cancellations;
  setUp(() {
    owner = Object();
    cancellations = 0;
    selection = CatalogSelection(
      connection: () => owner,
      cancelRead: () => cancellations++,
    );
  });
  tearDown(() => selection.dispose());

  test('manual exclusion replaces a pending all-selection and rejects its late response', () async {
    await selection.all(() async => {for (var i = 0; i < 1027; i++) '$i'});
    final gate = Completer<Set<String>>();
    final old = selection.all(() => gate.future);
    expect(selection.loading, isTrue);
    selection.toggle('0');
    expect(cancellations, 1);
    gate.complete({'0', 'replacement'});
    await old;
    expect(selection.ids.length, 1026);
    expect(selection.ids, isNot(contains('0')));
  });

  test('cancel and failure retain the previous choice, a successful retry uses complete new IDs', () async {
    selection.toggle('kept');
    final gate = Completer<Set<String>>();
    final old = selection.all(() => gate.future);
    selection.cancel();
    gate.complete({'discarded'});
    await old;
    expect(selection.ids, {'kept'});
    await selection.all(() => Future.error(const LibraryFailure('offline')));
    expect(selection.ids, {'kept'});
    expect(selection.error, contains('原选择已保留'));
    await selection.all(() async => {'a', 'b'});
    expect(selection.ids, {'a', 'b'});
    expect(selection.error, isEmpty);
  });

  test(
    'query clearing and a connection change reject late membership',
    () async {
      selection.toggle('old');
      final gate = Completer<Set<String>>();
      final old = selection.all(() => gate.future);
      selection.cancel(clear: true);
      gate.complete({'wrong-query'});
      await old;
      expect(selection.ids, isEmpty);
      final next = Completer<Set<String>>();
      final pending = selection.all(() => next.future);
      owner = Object();
      next.complete({'other-service'});
      await pending;
      expect(selection.ids, isEmpty);
      expect(selection.loading, isFalse);
    },
  );
}
