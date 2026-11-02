import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;
import 'media_workspace_widget_test.dart' show frames;

void main() {
  for (final custom in [false, true]) {
    testWidgets(
      'reader default and saved position; horizontal override=$custom',
      (t) async {
        final repo = AssetReadingLibrary();
        repo.marks['p0'] = const ReaderMark('p0-1', offsetRatio: .37);
        if (custom) {
          repo.prefs['p0'] = const ReaderPreferences(
            mode: ReaderMode.horizontal,
            overridden: true,
          );
        }
        await t.pumpWidget(
          MaterialApp(
            home: PackReaderPage(
              repository: repo,
              entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
              editTags: (_) async {},
            ),
          ),
        );
        for (var i = 0; i < 30; i++) {
          await frames(t);
          final state = t.state<PackReaderPageState>(
            find.byType(PackReaderPage),
          );
          if (state.session.opened && !state.session.busy) break;
        }
        final state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
        expect(state.session.opened, isTrue);
        expect(
          find.byKey(Key(custom ? 'reader-horizontal' : 'reader-vertical')),
          findsOneWidget,
        );
        expect(state.session.index, 1);
        expect(repo.marks['p0']!.pageId, 'p0-1');
        expect(repo.marks['p0']!.offsetRatio, closeTo(.37, .01));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
        repo.dispose();
      },
    );
  }
}
