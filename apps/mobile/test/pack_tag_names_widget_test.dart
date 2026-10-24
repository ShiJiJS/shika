import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/packs/pack_sheets.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class NamedWorkspace extends WorkspaceLibrary {
  NamedWorkspace() {
    packNames
      ..clear()
      ..addAll({
        for (var i = 0; i < 61; i++) 't$i': '标签${i.toString().padLeft(2, '0')}',
      });
    packLinks['p1'] = {'t60'};
    packLinks['p2'] = {'t5'};
  }
  Object owner = Object();
  @override
  Object get connectionIdentity => owner;
  bool failNames = false, failMore = false;
  Completer<PackTagNames>? delayedNames;
  final lookups = <Set<String>>[];
  final tagReads = <({String search, int offset})>[];
  @override
  Future<PackTagNames> resolvePackTags(Set<String> ids) async {
    lookups.add({...ids});
    if (delayedNames != null) return delayedNames!.future;
    if (failNames) throw const LibraryFailure('名称连接失败');
    return super.resolvePackTags(ids);
  }

  @override
  Future<CatalogPage<PackTag>> loadPackTags({
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    tagReads.add((search: search, offset: offset));
    if (offset > 0 && failMore) throw const LibraryFailure('下一页未读取');
    return super.loadPackTags(search: search, offset: offset, limit: limit);
  }
}

void main() {
  late NamedWorkspace repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = NamedWorkspace();
    await repo.initialize();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await frames(t);
  }

  Future<void> start(WidgetTester t) async {
    await t.pumpWidget(VideoViewerApp(repository: repo));
    await frames(t);
    await tap(t, find.byKey(const Key('kind-pack')));
    final card = t.widget<Text>(find.byKey(const Key('pack-tag-names-p1')));
    expect(card.data, '# ${repo.packNames['t60']}');
  }

  Future<void> edit(WidgetTester t) async {
    await tap(t, find.byTooltip('图包操作 春日合集'));
    await tap(t, find.text('整包标签'));
    expect(repo.lookups.last, {'t60'});
  }

  Finder chosen() => find.byKey(const Key('chosen-pack-tag-t60'));
  Finder input() => find.descendant(
    of: find.byType(PackTagEditor),
    matching: find.byType(TextField),
  );
  Finder save() => find.widgetWithText(FilledButton, '保存整包标签');
  Future<void> close(WidgetTester t) async {
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await frames(t);
  }

  testWidgets(
    'selected label outside first page resolves after retry and remains selected through search and save',
    (t) async {
      repo.failNames = true;
      await start(t);
      await edit(t);
      expect(t.widget<FilledButton>(save()).onPressed, isNull);
      expect(find.textContaining('原选择已保留'), findsOneWidget);
      repo.failNames = false;
      await tap(t, find.text('重试读取名称'));
      expect(
        t.widget<InputChip>(chosen()).label,
        isA<Text>().having((w) => w.data, 'name', '标签60'),
      );
      expect(t.widget<FilledButton>(save()).onPressed, isNotNull);
      await t.enterText(input(), '标签00');
      await frames(t);
      await tap(t, find.widgetWithText(FilterChip, '标签00'));
      await tap(t, save());
      expect(repo.packLinks['p1'], {'t60', 't0'});
      await tap(t, find.text('整包标签'));
      expect(find.byKey(const Key('chosen-pack-tag-t0')), findsOneWidget);
      expect(chosen(), findsOneWidget);
      await close(t);
    },
  );

  testWidgets(
    'a late name response cannot overwrite a newer search result name',
    (t) async {
      repo.delayedNames = Completer();
      await start(t);
      await edit(t);
      repo.packNames['t60'] = '更新后的名称';
      await t.enterText(input(), '更新后的名称');
      await frames(t);
      repo.delayedNames!.complete(PackTagNames(names: {'t60': '过时名称'}));
      await frames(t);
      expect(
        t.widget<InputChip>(chosen()).label,
        isA<Text>().having((w) => w.data, 'name', '更新后的名称'),
      );
      expect(find.text('过时名称'), findsNothing);
      await close(t);
    },
  );

  testWidgets(
    'a deleted selected label is explicit and saving requires removing that choice',
    (t) async {
      await start(t);
      repo.packNames.remove('t60');
      await edit(t);
      expect(find.text('已移除的标签'), findsOneWidget);
      expect(t.widget<FilledButton>(save()).onPressed, isNull);
      t.widget<InputChip>(chosen()).onDeleted!();
      await frames(t);
      await tap(t, save());
      expect(repo.packLinks['p1'], isEmpty);
      await close(t);
    },
  );

  testWidgets(
    'connection replacement clears old names, rejects late resolution and disables saving',
    (t) async {
      repo.delayedNames = Completer();
      await start(t);
      await edit(t);
      repo.owner = Object();
      repo.notifyListeners();
      await frames(t);
      repo.delayedNames!.complete(PackTagNames(names: {'t60': '旧服务名称'}));
      await frames(t);
      expect(find.textContaining('服务连接已变化'), findsOneWidget);
      expect(find.text('旧服务名称'), findsNothing);
      expect(t.widget<FilledButton>(save()).onPressed, isNull);
      await close(t);
    },
  );

  testWidgets(
    'selected long Chinese names fit a narrow sheet with large system text',
    (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      repo.packNames['t60'] = List.filled(12, '很长的中文标签').join();
      await start(t);
      await edit(t);
      expect(t.getRect(chosen()).width, lessThanOrEqualTo(320));
      expect(t.widget<FilledButton>(save()).onPressed, isNotNull);
      await close(t);
    },
  );

  testWidgets(
    'filter-only selection resolves initial IDs beyond the first label page',
    (t) async {
      await start(t);
      final page = t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
      await page.change(PackQuery(tags: {'t60'}));
      await frames(t);
      await tap(t, find.byTooltip('筛选图包'));
      await tap(
        t,
        find.descendant(
          of: find.byType(PackFilterSheet),
          matching: find.text('标签'),
        ),
      );
      expect(repo.lookups.last, {'t60'});
      expect(
        t.widget<InputChip>(chosen()).label,
        isA<Text>().having((w) => w.data, 'name', '标签60'),
      );
      await tap(t, find.text('使用所选标签'));
      await tap(t, find.text('应用筛选'));
      expect(page.entry.query.tags, {'t60'});
      expect(repo.packLinks['p1'], {'t60'});
      await close(t);
    },
  );

  testWidgets(
    'editor paging failure retries original offset and retains selected label names',
    (t) async {
      repo.failMore = true;
      await start(t);
      await edit(t);
      await tap(t, find.text('更多标签'));
      expect(repo.tagReads.last.offset, 50);
      expect(find.text('重试读取标签'), findsOneWidget);
      repo.failMore = false;
      await tap(t, find.text('重试读取标签'));
      expect(repo.tagReads.last.offset, 50);
      expect(find.byType(FilterChip), findsNWidgets(61));
      expect(
        t.widget<InputChip>(chosen()).label,
        isA<Text>().having((w) => w.data, 'name', '标签60'),
      );
      await close(t);
    },
  );
}
