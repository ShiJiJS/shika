import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_viewer/features/library/pack_catalog_page.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/main.dart';

import 'media_workspace_widget_test.dart' show frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_return_widget_test.dart' show DeepPacks;
import 'pack_files_test.dart' show FilesFixture;

typedef Json = Map<String, dynamic>;

class CleanupLibrary extends DeepPacks {
  CleanupLibrary() : super(count: 27);
  final journal = PackFileJournal(MemoryFileCommandStore());
  final receipts = <String, Json>{},
      deleted = <String, Map<String, Set<String>>>{};
  final requests = <String>[];
  bool lose = false;
  @override
  ServiceCapabilities get capabilities =>
      ServiceCapabilities(['image_packs', 'pack_tags', 'pack_logical_trash']);
  @override
  PackFiles createPackFiles() => PackFiles(
    journal: journal,
    scope: 'fixture',
    isCurrent: () => true,
    call: (method, path, {body}) async {
      requests.add('$method $path');
      if (method == 'GET') {
        final task = receipts[path.split('/').last];
        if (task == null) {
          throw const ApiFailure('Unknown', code: 'not_found', status: 404);
        }
        return task;
      }
      final nonce = body!['request_id'] as String, id = 'op-$nonce';
      Json task;
      if (path == '/api/v1/packs/trash') {
        final ids = List<String>.from(body['pack_ids']);
        deleted[id] = {
          for (final id in ids) id: {...packLinks[id]!},
        };
        for (final id in ids) {
          packLinks.remove(id);
        }
        task = FilesFixture().task(id, 'trash', ids);
        (task['result'] as Map)['undo_expires_at'] =
            DateTime.now()
                .add(const Duration(seconds: 8))
                .millisecondsSinceEpoch /
            1000;
      } else {
        final original = Uri.decodeComponent(path.split('/')[4]);
        packLinks.addAll(deleted[original]!);
        task = FilesFixture().task(id, 'undo', ['trash-0']);
      }
      receipts[nonce] = task;
      if (lose) {
        lose = false;
        throw const ApiFailure('服务响应未确认', code: 'reply_lost', status: 503);
      }
      return task;
    },
  );
}

void main() {
  late CleanupLibrary repo;
  late VideoPlayerPlatform previous;
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = CleanupLibrary();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = previous;
  });
  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.tap(finder);
    await frames(t);
  }

  Future<PackCatalogPageState> start(WidgetTester t) async {
    await repo.initialize();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(VideoViewerApp(repository: repo));
    await frames(t);
    await tap(t, find.byKey(const Key('kind-pack')));
    return t.state<PackCatalogPageState>(find.byType(PackCatalogPage));
  }

  for (final confirm in [false, true]) {
    testWidgets(
      'ordinary card actions keep dismissed search input closed after ${confirm ? 'removal' : 'cancel'}',
      (t) async {
        final state = await start(t);
        final search = find.byKey(const Key('pack-search'));
        await t.enterText(search, '包000');
        await frames(t);
        await t.showKeyboard(search);
        final input = t.widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        );
        // Android Back hides the keyboard while the field can retain focus.
        t.testTextInput.hide();
        await frames(t);
        expect(input.focusNode.hasFocus, isTrue);
        expect(t.testTextInput.isVisible, isFalse);
        final scroll = state.scroll.offset;

        await tap(t, find.byTooltip('图包操作 包000'));
        await tap(t, find.text('移入回收站'));
        await tap(
          t,
          confirm
              ? find.widgetWithText(FilledButton, '移入回收站')
              : find.text('取消'),
        );

        expect(input.focusNode.hasFocus, isFalse);
        expect(t.testTextInput.isVisible, isFalse);
        expect(state.entry.query.search, '包000');
        expect(t.widget<TextField>(search).controller!.text, '包000');
        expect(state.scroll.offset, closeTo(scroll, 1));
        expect(state.data.total, confirm ? 0 : 1);
        expect(
          repo.requests.where((value) => value.startsWith('POST ')).length,
          confirm ? 1 : 0,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
  }

  testWidgets(
    'ordinary card menu confirms whole pack, removes it and undo restores the same library query',
    (t) async {
      final state = await start(t);
      await state.change(PackQuery(tags: {'自然', '收藏'}, search: '包'));
      await frames(t);
      await tap(t, find.byTooltip('图包操作 包000'));
      expect(find.text('移入回收站'), findsOneWidget);
      await tap(t, find.text('移入回收站'));
      expect(find.text('包000 · 3 张'), findsOneWidget);
      expect(repo.requests, isEmpty);
      await tap(t, find.widgetWithText(FilledButton, '移入回收站'));
      expect(repo.packLinks.containsKey('p0'), isFalse);
      expect(state.data.total, 26);
      expect(state.entry.query.search, '包');
      expect(state.entry.query.tags, {'自然', '收藏'});
      expect(find.text('撤销'), findsOneWidget);
      await tap(t, find.text('撤销'));
      expect(repo.packLinks.containsKey('p0'), isTrue);
      expect(state.data.total, 27);
      expect(repo.requests.where((s) => s.startsWith('POST ')).length, 2);
      expect(await repo.createPackFiles().pending(), isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );
  testWidgets(
    'lost reply remains queryable from library after the removed card disappears',
    (t) async {
      final state = await start(t);
      repo.lose = true;
      await tap(t, find.byTooltip('图包操作 包000'));
      await tap(t, find.text('移入回收站'));
      await tap(t, find.widgetWithText(FilledButton, '移入回收站'));
      expect(find.text('服务响应未确认'), findsOneWidget);
      await tap(t, find.text('稍后处理'));
      expect(repo.packLinks.containsKey('p0'), isFalse);
      expect(state.data.total, 26);
      expect(find.byKey(const Key('pack-pending-files')), findsOneWidget);
      final pending = (await repo.createPackFiles().pending()).single;
      expect(pending.label, '包000');
      final posts = repo.requests.where((s) => s.startsWith('POST ')).length;
      await tap(t, find.byKey(const Key('pack-pending-files')));
      expect(repo.requests.where((s) => s.startsWith('POST ')).length, posts);
      expect(await repo.createPackFiles().pending(), isEmpty);
      expect(find.byKey(const Key('pack-pending-files')), findsNothing);
      expect(find.text('撤销'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );
}
