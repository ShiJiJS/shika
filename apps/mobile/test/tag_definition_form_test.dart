import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/library/tag_catalog_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/ui/paper.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary;
import 'support/reveal_action.dart';

class Definitions extends WorkspaceLibrary {
  Object identity = Object();
  @override
  Object get connectionIdentity => identity;
  final writes = <({MediaKind kind, String? id, String? name, bool delete})>[];
  void signal() => notifyListeners();
  bool fail = true;
  Completer<void>? gate;
  Future<void> record(
    MediaKind kind,
    String? id,
    String? name,
    bool delete,
  ) async {
    writes.add((kind: kind, id: id, name: name, delete: delete));
    await gate?.future;
    if (fail) throw const LibraryFailure('同名标签，请换一个名称');
  }

  @override
  Future<void> editTag({String? original, String? name, bool delete = false}) =>
      record(MediaKind.video, original, name, delete);
  @override
  Future<void> editPackTag({
    String? original,
    String? name,
    bool delete = false,
  }) => record(MediaKind.pack, original, name, delete);
}

void main() {
  Future<({Definitions repo, TagCatalogPageState state})> host(
    WidgetTester t,
    MediaKind kind, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    final repo = Definitions();
    await repo.initialize();
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(() async {
      if (repo.gate?.isCompleted == false) repo.gate!.complete();
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      repo.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      t.view.resetViewInsets();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: Paper.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: TagCatalogPage(
            repository: repo,
            kind: kind,
            active: true,
            onView: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return (
      repo: repo,
      state: t.state<TagCatalogPageState>(find.byType(TagCatalogPage)),
    );
  }

  Future<void> tap(WidgetTester t, Finder target) async {
    await revealAction(t, target);
    await t.tap(target);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final profile in [
    (390.0, 844.0, 1.0),
    (360.0, 740.0, 2.0),
    (844.0, 390.0, 1.0),
    (844.0, 390.0, 2.0),
  ]) {
    for (final kind in MediaKind.values) {
      testWidgets(
        '${kind.name} definition keeps failed draft and has no directory error $profile',
        (t) async {
          final (:repo, :state) = await host(
            t,
            kind,
            size: Size(profile.$1, profile.$2),
            scale: profile.$3,
          );
          unawaited(state.form());
          await t.pumpAndSettle();
          final field = find.byKey(const Key('tag-name'));
          expect(
            MediaQuery.textScalerOf(t.element(field)).scale(13),
            13 * profile.$3,
          );
          t.view.viewInsets = FakeViewPadding(
            bottom: profile.$1 > profile.$2 ? 150 : 300,
          );
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('tag-definition-save')));
          expect(repo.writes, isEmpty);
          expect(find.text('请输入1至100字的标签名称'), findsOneWidget);
          await t.enterText(find.byKey(const Key('tag-name')), '  保留的名称  ');
          await tap(t, find.byKey(const Key('tag-definition-save')));
          expect(repo.writes.single.name, '保留的名称');
          expect(
            t
                .widget<TextField>(find.byKey(const Key('tag-name')))
                .controller!
                .text,
            '  保留的名称  ',
          );
          expect(find.byKey(const Key('tag-definition-error')), findsOneWidget);
          expect(state.error, isEmpty);
          repo.fail = false;
          await tap(t, find.byKey(const Key('tag-definition-save')));
          expect(repo.writes, hasLength(2));
          expect(repo.writes.every((v) => v.kind == kind && !v.delete), isTrue);
          expect(find.byKey(const Key('tag-name')), findsNothing);
        },
      );
    }
  }
  for (final kind in MediaKind.values) {
    testWidgets(
      '${kind.name} removal requires separate confirmation and returns the exact selected id',
      (t) async {
        final (:repo, :state) = await host(t, kind);
        repo.fail = false;
        state.selected.add('same-id');
        unawaited(state.edit(const TagCatalogItem('same-id', '同名', 2)));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('tag-name')), '尚未保存的草稿');
        await tap(t, find.byKey(const Key('tag-definition-remove')));
        expect(find.byType(SheetFrame), findsOneWidget);
        expect(find.byKey(const Key('tag-name')), findsNothing);
        await tap(t, find.text('取消'));
        expect(repo.writes, isEmpty);
        expect(
          t
              .widget<TextField>(find.byKey(const Key('tag-name')))
              .controller!
              .text,
          '尚未保存的草稿',
        );
        expect(state.selected, {'same-id'});
        await tap(t, find.byKey(const Key('tag-definition-remove')));
        await tap(t, find.byKey(const Key('tag-definition-remove-confirm')));
        expect(repo.writes.single.kind, kind);
        expect(repo.writes.single.id, 'same-id');
        expect(repo.writes.single.delete, isTrue);
        expect(state.selected, isEmpty);
      },
    );
  }
  testWidgets(
    'old callbacks cannot submit to a new connection even before rebuild',
    (t) async {
      final (:repo, :state) = await host(t, MediaKind.pack);
      unawaited(state.form());
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('tag-name')), '旧连接草稿');
      final submit = t
          .widget<FilledButton>(find.byKey(const Key('tag-definition-save')))
          .onPressed!;
      repo.identity = Object();
      submit();
      await t.pumpAndSettle();
      expect(repo.writes, isEmpty);
      repo.signal();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tag-definition-stale')), findsOneWidget);
      expect(
        t.widget<TextField>(find.byKey(const Key('tag-name'))).controller!.text,
        '旧连接草稿',
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('tag-definition-save')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('a pending definition disables repeated submit and closing', (
    t,
  ) async {
    final (:repo, :state) = await host(t, MediaKind.video);
    repo.fail = false;
    repo.gate = Completer<void>();
    unawaited(state.form());
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tag-name')), '保存中');
    final submit = t
        .widget<FilledButton>(find.byKey(const Key('tag-definition-save')))
        .onPressed!;
    submit();
    submit();
    await t.pump();
    expect(repo.writes, hasLength(1));
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('tag-definition-save')))
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '关闭面板',
            ),
          )
          .onPressed,
      isNull,
    );
    repo.gate!.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tag-name')), findsNothing);
  });
  testWidgets('a connection switch during removal confirmation never submits', (
    t,
  ) async {
    final (:repo, :state) = await host(t, MediaKind.pack);
    unawaited(state.edit(const TagCatalogItem('old-id', '旧标签', 1)));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const Key('tag-definition-remove')));
    repo.identity = Object();
    repo.signal();
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(
            find.byKey(const Key('tag-definition-remove-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(repo.writes, isEmpty);
    await tap(t, find.text('取消'));
    expect(find.byKey(const Key('tag-name')), findsOneWidget);
  });
}
