import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

void main() {
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 2.0),
  ]) {
    testWidgets(
      'reader settings keep accessible mode sections stable ${sample.$1}/${sample.$2}',
      (t) async {
        final semantics = t.ensureSemantics();
        final repo = AssetReadingLibrary();
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = sample.$1;
        try {
          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(sample.$2)),
                child: child!,
              ),
              home: PackReaderPage(
                repository: repo,
                entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
                editTags: (_) async {},
              ),
            ),
          );
          PackReaderPageState state() => t.state(find.byType(PackReaderPage));
          Future<void> until(bool Function() done) async {
            for (var i = 0; i < 150; i++) {
              await t.pump(const Duration(milliseconds: 40));
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 2)),
              );
              expect(t.takeException(), isNull);
              if (done()) return;
            }
            fail('Reader settings did not reach expected state');
          }

          Future<void> tap(Finder target) async {
            await until(() => target.evaluate().isNotEmpty);
            await t.ensureVisible(target);
            await t.pump(const Duration(milliseconds: 350));
            expect(target.hitTestable(), findsOneWidget);
            await t.tap(target);
            await t.pump(const Duration(milliseconds: 350));
            expect(t.takeException(), isNull);
          }

          await until(() => state().session.opened && !state().session.busy);
          await tap(find.byTooltip('阅读设置'));
          await t.pumpAndSettle();
          final done = find.byKey(const Key('reader-settings-done'));
          expect(done.hitTestable(), findsOneWidget);
          expect(t.getRect(done).bottom, lessThanOrEqualTo(sample.$1.height));
          expect(
            t.getRect(find.text('纵向拼接')).bottom,
            lessThan(t.getRect(find.text('翻页方向')).top),
          );
          for (var round = 0; round < 3; round++) {
            repo.preferenceStarted = Completer<void>();
            repo.preferenceRelease = Completer<void>();
            await tap(find.text('纵向拼接'));
            expect(repo.preferenceStarted!.isCompleted, isTrue);
            expect(state().session.busy, isTrue);
            expect(t.widget<Slider>(find.byType(Slider)).onChanged, isNull);
            repo.preferenceRelease!.complete();
            await until(
              () =>
                  state().session.preferences.mode == ReaderMode.vertical &&
                  !state().session.busy,
            );
            expect(
              find.byType(DropdownButtonFormField<ReaderDirection>),
              findsNothing,
            );
            expect(
              t
                  .getSemantics(find.byType(SwitchListTile))
                  .getSemanticsData()
                  .label,
              contains('图片之间留间距'),
            );
            await tap(find.text('图片之间留间距'));
            await until(() => !state().session.busy);
            expect(
              t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
              state().session.preferences.gap,
            );
            await tap(find.text('横向翻页'));
            await until(
              () =>
                  state().session.preferences.mode == ReaderMode.horizontal &&
                  !state().session.busy,
            );
            expect(find.byType(SwitchListTile), findsNothing);
            expect(
              find.byType(DropdownButtonFormField<ReaderDirection>),
              findsOneWidget,
            );
            expect(
              find.byType(DropdownButtonFormField<ReaderFit>),
              findsOneWidget,
            );
          }
          await tap(find.text('继续阅读'));
          await until(
            () =>
                find.text('继续阅读').evaluate().isEmpty &&
                t.widget<Slider>(find.byType(Slider)).onChanged != null,
          );
          await t.drag(find.byType(Slider), const Offset(80, 0));
          await until(() => state().session.index > 0);
          expect(await state().session.flush(), isTrue);
        } finally {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          repo.dispose();
          semantics.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        }
      },
    );
  }
}
