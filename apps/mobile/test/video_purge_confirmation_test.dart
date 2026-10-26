import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';

import 'support/reveal_action.dart';

class _Repository extends DemoLibraryRepository {
  _Repository() : super(MemoryStateStore());
  Object identity = Object();
  final calls = <Set<String>>[];
  @override
  Object get connectionIdentity => identity;
  void invalidate() {
    identity = Object();
    notifyListeners();
  }

  @override
  Future<void> permanentlyDelete(Set<String> ids) async {
    calls.add({...ids});
  }
}

void main() {
  Future<void> tap(WidgetTester t, Finder target) async {
    await revealAction(t, target);
    await t.tap(target);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<(_Repository, String)> host(
    WidgetTester t,
    double width,
    double height,
    double scale,
  ) async {
    final repo = _Repository();
    await repo.initialize();
    final id = repo.query().first.id;
    await t.runAsync(
      () => repo.deleteVideos({id}, requestId: 'video-purge-test-seed'),
    );
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      repo.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      t.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await t.pumpWidget(VideoViewerApp(repository: repo));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const Key('nav-settings')));
    await tap(t, find.text('回收站'));
    await tap(t, find.byKey(Key('trash-$id')));
    await tap(t, find.byKey(const Key('video-trash-permanent')));
    return (repo, id);
  }

  for (final p in [
    (390.0, 844.0, 1.0),
    (360.0, 740.0, 2.0),
    (844.0, 390.0, 1.0),
    (844.0, 390.0, 2.0),
  ]) {
    testWidgets(
      'video purge requires a fresh checkbox and dispatches only the captured choice $p',
      (t) async {
        final (repo, id) = await host(t, p.$1, p.$2, p.$3);
        final submit = find.byKey(const Key('video-purge-submit'));
        expect(t.widget<FilledButton>(submit).onPressed, isNull);
        await tap(t, find.text('取消'));
        expect(repo.calls, isEmpty);
        await tap(t, find.byKey(const Key('video-trash-permanent')));
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('video-purge-confirm')),
              )
              .value,
          isFalse,
        );
        await tap(t, find.byKey(const Key('video-purge-confirm')));
        await tap(t, submit);
        expect(repo.calls, [
          {id},
        ]);
      },
    );
  }
  testWidgets(
    'management identity change clears approval and prevents the old video deletion',
    (t) async {
      final (repo, _) = await host(t, 390, 844, 1);
      await tap(t, find.byKey(const Key('video-purge-confirm')));
      repo.invalidate();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('video-purge-stale')), findsOneWidget);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const Key('video-purge-confirm')),
            )
            .value,
        isFalse,
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('video-purge-submit')))
            .onPressed,
        isNull,
      );
      await tap(t, find.text('取消'));
      expect(repo.calls, isEmpty);
    },
  );
}
