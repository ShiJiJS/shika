import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_sheets.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/sheets.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary;
import 'support/reveal_action.dart';

class AssignmentLibrary extends WorkspaceLibrary {
  Object owner = Object();
  bool restoring = false, failSave = false, failCreate = false;
  Completer<void>? pending;
  final writes =
      <
        ({
          bool pack,
          Set<String> ids,
          Set<String> tags,
          bool replace,
          bool remove,
        })
      >[];
  final creations = <bool>[];
  @override
  Object get connectionIdentity => owner;
  @override
  bool get backupRestorePending => restoring;
  @override
  Future<void> editTag({
    String? original,
    String? name,
    bool delete = false,
  }) async {
    creations.add(false);
    if (failCreate) throw const LibraryFailure('名称暂未保存');
    await super.editTag(original: original, name: name, delete: delete);
  }

  @override
  Future<PackTag> createPackTag(String name) async {
    creations.add(true);
    if (failCreate) throw const LibraryFailure('名称暂未保存');
    return super.createPackTag(name);
  }

  @override
  Future<void> setVideoTags(
    Set<String> ids,
    Set<String> tags, {
    bool remove = false,
    bool replace = false,
  }) async {
    writes.add((
      pack: false,
      ids: {...ids},
      tags: {...tags},
      replace: replace,
      remove: remove,
    ));
    await pending?.future;
    if (failSave) throw const LibraryFailure('关联暂未保存');
    await super.setVideoTags(ids, tags, remove: remove, replace: replace);
  }

  @override
  Future<void> setPackTags(
    Set<String> ids,
    Set<String> tags, {
    bool replace = false,
  }) async {
    writes.add((
      pack: true,
      ids: {...ids},
      tags: {...tags},
      replace: replace,
      remove: false,
    ));
    await pending?.future;
    if (failSave) throw const LibraryFailure('关联暂未保存');
    await super.setPackTags(ids, tags, replace: replace);
  }
}

void main() {
  setUpAll(() async {
    final path = Platform.environment['LF6_CJK_FONT'];
    if (path == null) return;
    final font = ByteData.sublistView(await File(path).readAsBytes());
    await Future.wait([
      (FontLoader('Roboto')..addFont(Future.value(font))).load(),
      (FontLoader('PaperSerif')
            ..addFont(rootBundle.load('assets/fonts/PaperSerif.ttf'))
            ..addFont(Future.value(font)))
          .load(),
      (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load(),
    ]);
  });

  Future<void> tap(WidgetTester t, Finder f) async {
    await revealAction(t, f);
    await t.tap(f);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  final save = find.byKey(const Key('tag-assignment-save'));
  final input = find.byKey(const Key('tag-assignment-new'));
  final add = find.byKey(const Key('tag-assignment-add'));
  final search = find.byKey(const Key('tag-assignment-search'));
  for (final pack in [false, true]) {
    late AssignmentLibrary repo;
    Object? result;
    Future<void> host(
      WidgetTester t, {
      bool batch = false,
      Set<String>? targets,
    }) async {
      repo = AssignmentLibrary();
      await repo.initialize();
      result = null;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        repo.dispose();
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await paperSheet<Object>(
                    context,
                    pack
                        ? PackTagEditor(
                            repository: repo,
                            ids: targets ?? {'p1'},
                            initial: const {'自然'},
                            appendOnly: batch,
                          )
                        : TagEditor(
                            repository: repo,
                            ids: targets ?? {'v1'},
                            appendOnly: batch,
                          ),
                    dismissible: false,
                  );
                },
                child: const Text('打开标签'),
              ),
            ),
          ),
        ),
      );
      await tap(t, find.text('打开标签'));
    }

    Set<String> links() => pack
        ? repo.packLinks['p1']!
        : repo.snapshot.videos.firstWhere((v) => v.id == 'v1').tags;
    testWidgets(
      'single replacement creates only current namespace and returns persisted IDs pack=$pack',
      (t) async {
        await host(t);
        await tap(t, find.widgetWithText(FilterChip, '自然'));
        await tap(t, find.widgetWithText(FilterChip, pack ? '收藏' : '庭院'));
        await t.enterText(input, '共同新标签');
        await tap(t, save);
        expect(repo.creations, [pack]);
        expect(repo.writes.single.pack, pack);
        expect(repo.writes.single.replace, isTrue);
        expect(links(), isNot(contains('自然')));
        expect(links(), contains(pack ? '收藏' : '庭院'));
        expect(links(), contains(pack ? 'created-pack-tag' : '共同新标签'));
        if (pack) {
          expect(result, isA<PackTagNames>());
          expect((result as PackTagNames).names['created-pack-tag'], '共同新标签');
          expect(repo.snapshot.tags, isNot(contains('共同新标签')));
        } else {
          expect(result, isTrue);
          expect(repo.packNames.values, isNot(contains('共同新标签')));
          expect(links(), contains('花卉'));
        }
      },
    );
    testWidgets(
      'one remaining batch target appends, freezes target IDs, and preserves existing labels pack=$pack',
      (t) async {
        final targets = {pack ? 'p1' : 'v1'};
        await host(t, batch: true, targets: targets);
        targets
          ..clear()
          ..add(pack ? 'p2' : 'v2');
        await tap(t, find.widgetWithText(FilterChip, pack ? '收藏' : '庭院'));
        await tap(t, save);
        expect(repo.writes.single.ids, {pack ? 'p1' : 'v1'});
        expect(repo.writes.single.replace, isFalse);
        expect(links(), containsAll(['自然', pack ? '收藏' : '庭院']));
      },
    );
    testWidgets(
      'cancel retains original assignments and creates nothing from an unsubmitted draft pack=$pack',
      (t) async {
        await host(t);
        final before = {...links()};
        await t.enterText(input, '尚未添加');
        await tap(t, find.text('取消'));
        expect(repo.writes, isEmpty);
        expect(repo.creations, isEmpty);
        expect(links(), before);
      },
    );
    testWidgets(
      'create and assignment failures retain draft, selected IDs and namespace pack=$pack',
      (t) async {
        await host(t);
        repo.failCreate = true;
        await t.enterText(input, '重试名称');
        await tap(t, add);
        expect(t.widget<TextField>(input).controller!.text, '重试名称');
        expect(find.text('名称暂未保存'), findsOneWidget);
        await t.enterText(search, '自然');
        await t.pumpAndSettle();
        expect(find.text('名称暂未保存'), findsOneWidget);
        repo.failCreate = false;
        await tap(t, add);
        expect(t.widget<TextField>(input).controller!.text, isEmpty);
        repo.failSave = true;
        await tap(t, save);
        expect(find.text('关联暂未保存'), findsOneWidget);
        expect(
          find.byKey(
            Key(
              'chosen-${pack ? 'pack' : 'video'}-tag-${pack ? 'created-pack-tag' : '重试名称'}',
            ),
          ),
          findsOneWidget,
        );
        repo.failSave = false;
        await tap(t, save);
        expect(repo.creations, [pack, pack]);
        expect(repo.writes, hasLength(2));
        expect(repo.writes.first.tags, repo.writes.last.tags);
        expect(links(), contains(pack ? 'created-pack-tag' : '重试名称'));
      },
    );
    testWidgets(
      'pending save prevents duplicate/stale actions and back navigation pack=$pack',
      (t) async {
        await host(t);
        final callback = t.widget<FilledButton>(save).onPressed!;
        repo.pending = Completer<void>();
        callback();
        await t.pump();
        callback();
        await t.pump();
        expect(repo.writes, hasLength(1));
        expect(t.widget<FilledButton>(save).onPressed, isNull);
        await t.binding.handlePopRoute();
        await t.pump();
        expect(save, findsOneWidget);
        repo.pending!.complete();
        await t.pumpAndSettle();
        expect(result, isNotNull);
      },
    );
    testWidgets(
      'stale save callbacks cannot write after connection or restore change pack=$pack',
      (t) async {
        await host(t);
        final callback = t.widget<FilledButton>(save).onPressed!;
        repo.restoring = true;
        repo.notifyListeners();
        callback();
        await t.pumpAndSettle();
        expect(repo.writes, isEmpty);
        repo.restoring = false;
        repo.owner = Object();
        repo.notifyListeners();
        callback();
        await t.pumpAndSettle();
        expect(repo.writes, isEmpty);
        expect(t.widget<FilledButton>(save).onPressed, isNull);
      },
    );
  }

  for (final sample in [
    (390.0, 844.0, 1.0),
    (360.0, 740.0, 2.0),
    (844.0, 390.0, 1.0),
  ]) {
    for (final pack in [false, true]) {
      for (final batch in [false, true]) {
        testWidgets('assignment surface $sample pack=$pack batch=$batch', (
          t,
        ) async {
          final repo = WorkspaceLibrary();
          await repo.initialize();
          t.view.physicalSize = Size(sample.$1, sample.$2);
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.textScaleFactorTestValue = sample.$3;
          addTearDown(() async {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            repo.dispose();
            t.view.resetPhysicalSize();
            t.view.resetDevicePixelRatio();
            t.platformDispatcher.clearTextScaleFactorTestValue();
          });
          final boundary = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: Paper.theme,
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => paperSheet<Object>(
                        context,
                        pack
                            ? PackTagEditor(
                                repository: repo,
                                ids: batch ? {'p1', 'p2'} : {'p1'},
                                initial: const {'自然'},
                                initialNames: const {'自然': '自然'},
                                appendOnly: batch,
                              )
                            : TagEditor(
                                repository: repo,
                                ids: batch ? {'v1', 'v2'} : {'v1'},
                                appendOnly: batch,
                              ),
                        dismissible: false,
                      ),
                      child: const Text('打开标签'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('打开标签'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final directory = Platform.environment['LF8_ASSIGNMENT_SHOTS'];
          if (directory != null) {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await t.runAsync(() async {
              final image = await render.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(directory).create(recursive: true);
              await File(
                '$directory/${sample.$1.toInt()}-${pack ? 'pack' : 'video'}-${batch ? 'batch' : 'single'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await revealAction(t, find.byTooltip('关闭面板'));
          await t.tap(find.byTooltip('关闭面板'));
          await t.pumpAndSettle();
          expect(repo.snapshot.videos.first.tags, contains('自然'));
          expect(repo.packLinks['p1'], {'自然'});
        });
      }
    }
  }
}
