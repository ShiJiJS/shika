import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/scoped_journal.dart';

void main() {
  final legacy = jsonEncode(['http://127.0.0.1:9876', 'server']);
  final old = jsonEncode(['http://127.0.0.1:9876', 'server', 'a' * 32]);
  final fresh = jsonEncode(['http://127.0.0.1:9876', 'server', 'b' * 32]);
  final foreign = jsonEncode(['http://127.0.0.1:9876', 'another', 'a' * 32]);
  test('legacy and old generation records survive migration, reopening and another server', () async {
    final saved = {
      'scope': legacy,
      'pending': {
        'key': 'original',
        'body': {
          'ids': ['one', 'two'],
        },
      },
    };
    String? disk = jsonEncode(saved);
    ScopedJournal open() => ScopedJournal(
      readText: () async => disk,
      writeText: (v) async => disk = v,
    );
    final book = open();
    expect(await book.read(fresh), isNull);
    await book.write(
      fresh,
      jsonEncode({
        'scope': fresh,
        'pending': {'key': 'new'},
      }),
    );
    await book.write(
      foreign,
      jsonEncode({
        'scope': foreign,
        'pending': {'key': 'other'},
      }),
    );
    final next = open();
    final rows = await next.entries(fresh);
    expect(rows.keys.toSet(), {legacy, fresh});
    expect(rows[legacy], saved);
    expect(jsonDecode((await next.read(foreign))!)['pending']['key'], 'other');
    expect(sameServerScope(old, fresh), isTrue);
    expect(sameServerScope(foreign, fresh), isFalse);
  });
  test('a delayed old generation write cannot replace a newer scope', () async {
    String? disk;
    final entered = Completer<void>(), release = Completer<void>();
    var first = true;
    final book = ScopedJournal(
      readText: () async => disk,
      writeText: (v) async {
        if (first) {
          first = false;
          entered.complete();
          await release.future;
        }
        disk = v;
      },
    );
    final pending = book.write(
      old,
      jsonEncode({
        'scope': old,
        'pending': {'key': 'old-original'},
      }),
    );
    await entered.future;
    final current = book.write(
      fresh,
      jsonEncode({
        'scope': fresh,
        'pending': {'key': 'new-original'},
      }),
    );
    release.complete();
    await Future.wait([pending, current]);
    final raw = jsonDecode(disk!)['scopes'];
    expect(raw[old]['pending']['key'], 'old-original');
    expect(raw[fresh]['pending']['key'], 'new-original');
  });
  for (final committed in [false, true]) {
    test(
      'storage failure after commit=$committed re-reads authoritative bytes before merging',
      () async {
        String? disk;
        var fail = true;
        final book = ScopedJournal(
          readText: () async => disk,
          writeText: (v) async {
            if (!fail || committed) disk = v;
            if (fail) {
              fail = false;
              throw StateError('lost storage acknowledgement');
            }
          },
        );
        await expectLater(
          book.write(
            old,
            jsonEncode({
              'scope': old,
              'pending': {'key': 'unknown'},
            }),
          ),
          throwsStateError,
        );
        await book.write(
          fresh,
          jsonEncode({
            'scope': fresh,
            'pending': {'key': 'new'},
          }),
        );
        final raw = jsonDecode(disk!)['scopes'];
        expect(raw.containsKey(old), committed);
        if (committed) expect(raw[old]['pending']['key'], 'unknown');
        expect(raw[fresh]['pending']['key'], 'new');
      },
    );
  }
  test(
    'corrupt, wrong-scope and mismatched envelope data is never overwritten',
    () async {
      for (final raw in [
        '{',
        '{}',
        jsonEncode({
          'version': 2,
          'scopes': {
            old: {'scope': fresh},
          },
        }),
      ]) {
        var disk = raw, writes = 0;
        final book = ScopedJournal(
          readText: () async => disk,
          writeText: (v) async {
            disk = v;
            writes++;
          },
        );
        await expectLater(
          book.write(fresh, jsonEncode({'scope': fresh})),
          throwsA(isA<LibraryFailure>()),
        );
        expect(disk, raw);
        expect(writes, 0);
      }
      var writes = 0;
      final book = ScopedJournal(
        readText: () async => null,
        writeText: (v) async {
          writes++;
        },
      );
      await expectLater(
        book.write(old, jsonEncode({'scope': fresh})),
        throwsA(isA<LibraryFailure>()),
      );
      expect(writes, 0);
    },
  );
  test('a single legacy scope keeps its compatible representation', () async {
    String? disk;
    final book = ScopedJournal(
      readText: () async => disk,
      writeText: (v) async => disk = v,
    );
    await book.write(
      legacy,
      jsonEncode({
        'scope': legacy,
        'pending': {'key': 'kept'},
      }),
    );
    expect(jsonDecode(disk!)['scope'], legacy);
    expect(jsonDecode(disk!)['version'], isNull);
  });
}
