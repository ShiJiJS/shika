import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/settings/default_settings_sheet.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;
import 'fixed_preview_widget_test.dart' show frames;

class DraftReader extends Fake implements PackReader {
  int writes = 0;
  bool alive = true;
  @override
  bool get isCurrent => alive;
  @override
  Future<ReaderPreferences> defaults() async => const ReaderPreferences();
  @override
  Future<T> submit<T>(ReaderCommand<T> command) async {
    writes++;
    throw StateError('Cancelled drafts must not submit');
  }

  @override
  void dispose() {
    alive = false;
  }
}

class DefaultDraftLibrary extends AssetReadingLibrary {
  final reader = DraftReader();
  @override
  PackReader createPackReader() => reader;
}

void main() {
  for (final (width, scale) in [(390.0, 1.0), (360.0, 2.0)]) {
    testWidgets(
      'reader draft remains reachable and cancel never writes at $width/$scale',
      (t) async {
        final repo = DefaultDraftLibrary();
        final local = UiPreferences();
        await repo.initialize();
        addTearDown(() {
          repo.dispose();
          local.dispose();
        });
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: DefaultSettingsSheet(
                  repository: repo,
                  local: local,
                  video: false,
                ),
              ),
            ),
          ),
        );
        await frames(t);
        await t.tap(find.text('纵向拼接'));
        await frames(t);
        await t.scrollUntilVisible(
          find.text('保存默认设置'),
          150,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('保存默认设置').hitTestable(), findsOneWidget);
        expect(repo.reader.writes, 0);
        await t.pumpWidget(const SizedBox());
        await frames(t);
        expect(t.takeException(), isNull);
      },
    );
  }
}
