import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/settings/default_settings_sheet.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/preferences.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;
import 'fixed_preview_widget_test.dart' show frames;

class DraftReader extends Fake implements PackReader {
  int writes = 0, queries = 0;
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
  Future<T?> receipt<T>(ReaderCommand<T> command) async {
    queries++;
    return null;
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
  testWidgets('failed fixed-footer save reveals error and keeps the draft', (
    t,
  ) async {
    final repo = DefaultDraftLibrary();
    final local = UiPreferences();
    await repo.initialize();
    addTearDown(repo.dispose);
    addTearDown(local.dispose);
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: DefaultSettingsSheet(
            repository: repo,
            local: local,
            video: false,
          ),
        ),
      ),
    );
    await frames(t);
    await t.tap(find.byKey(const Key('default-mode-vertical')));
    await frames(t);
    await t.tap(find.byKey(const Key('defaults-save')));
    await t.pumpAndSettle();
    final error = find.byKey(const Key('defaults-error'));
    final save = find.byKey(const Key('defaults-save'));
    expect(error.hitTestable(), findsOneWidget);
    expect(t.getRect(error).bottom, lessThanOrEqualTo(t.getRect(save).top));
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    expect(repo.reader.writes, 1);
    await t.tap(find.text('核对原设置请求'));
    await t.pumpAndSettle();
    expect(repo.reader.queries, 1);
    expect(repo.reader.writes, 1);
    expect(find.textContaining('暂未找到原设置请求'), findsOneWidget);
    await Scrollable.ensureVisible(
      t.element(find.byKey(const Key('default-mode-vertical'))),
    );
    await frames(t);
    final selected = t.widgetList<Semantics>(
      find.ancestor(
        of: find.byKey(const Key('default-mode-vertical')),
        matching: find.byType(Semantics),
      ),
    );
    expect(selected.any((s) => s.properties.selected == true), isTrue);
    expect(t.takeException(), isNull);
  });
  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.0),
    (const Size(844, 390), 2.0),
  ]) {
    testWidgets(
      'reader draft remains reachable and cancel never writes at $size/$scale',
      (t) async {
        final repo = DefaultDraftLibrary();
        final local = UiPreferences();
        await repo.initialize();
        addTearDown(() {
          repo.dispose();
          local.dispose();
        });
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
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
        final save = find.byKey(const Key('defaults-save'));
        final footerBefore = t.getRect(save);
        await Scrollable.ensureVisible(
          t.element(find.byKey(const Key('default-mode-vertical'))),
          alignment: .5,
        );
        await frames(t);
        await t.tap(find.text('纵向拼接'));
        await frames(t);
        final direction = find.byKey(const Key('default-reader-direction'));
        await Scrollable.ensureVisible(t.element(direction), alignment: .5);
        await frames(t);
        await t.tap(direction);
        await frames(t);
        await t.tap(find.text('从右向左').hitTestable().last);
        await frames(t);
        expect(
          t
              .widget<PaperDropdownButtonFormField<ReaderDirection>>(direction)
              .initialValue,
          ReaderDirection.rtl,
        );
        expect(t.getRect(save), footerBefore);
        await t.drag(find.byType(Scrollable).last, const Offset(0, -250));
        await frames(t);
        expect(t.getRect(save), footerBefore);
        expect(save.hitTestable(), findsOneWidget);
        expect(footerBefore.bottom, lessThanOrEqualTo(size.height));
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
