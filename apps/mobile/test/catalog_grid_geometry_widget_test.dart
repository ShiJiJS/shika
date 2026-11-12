import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/features/library/pack_catalog_page.dart';
import 'package:shika/features/library/video_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/media_layout.dart';

import 'media_workspace_widget_test.dart' show frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;
import 'pack_return_widget_test.dart' show DeepPacks;

class GridLibrary extends DeepPacks {
  GridLibrary() : super(count: 120);
  final videoReads = <int>[];
  final packRequests = <int>[];
  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) {
    packRequests.add(offset);
    return super.loadPacks(query, offset: offset, limit: limit);
  }

  @override
  Future<VideoPage> loadVideoEntry(
    VideoEntryScope entry, {
    int offset = 0,
    int limit = 24,
  }) async {
    videoReads.add(offset);
    return VideoPage(
      items: [
        for (var i = offset; i < offset + limit && i < 120; i++)
          LibraryVideo(
            id: 'grid-video-$i',
            path: '/videos/grid/视频$i.mp4',
            rootId: 'r1',
            portrait: true,
            tags: {'自然'},
            source: const MediaSource('assets/media/flower-portrait.mp4'),
            poster: 'assets/media/flower-portrait.jpg',
          ),
      ],
      total: 120,
      offset: offset,
      limit: limit,
    );
  }
}

void main() {
  late GridLibrary repo;
  late VideoPlayerPlatform original;
  setUp(() async {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = UnreadyVideo();
    repo = GridLibrary();
    await repo.initialize();
  });
  tearDown(() {
    repo.dispose();
    VideoPlayerPlatform.instance = original;
  });
  Future<void> start(WidgetTester t, MediaKind kind) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ShikaApp(repository: repo));
    await frames(t);
    if (kind == MediaKind.pack) {
      await t.tap(find.byKey(const Key('kind-pack')));
      await frames(t);
    }
  }

  dynamic state(WidgetTester t, MediaKind kind) => kind == MediaKind.pack
      ? t.state<PackCatalogPageState>(find.byType(PackCatalogPage))
      : t.state<VideoCatalogPageState>(find.byType(VideoCatalogPage));
  Finder tile(MediaKind kind, String id) =>
      find.byKey(Key('${kind == MediaKind.pack ? 'pack-tile' : 'tile'}-$id'));

  for (final kind in MediaKind.values) {
    testWidgets(
      '${kind.name} compact caption keeps readable tags and a full action target',
      (t) async {
        await start(t, kind);
        final s = state(t, kind), item = state(t, kind).data.items.first;
        final tag = find.byKey(Key('${kind.name}-tag-names-${item.id}'));
        final text = t.widget<Text>(tag);
        expect(text.style!.fontSize, 12);
        expect(text.style!.height, 1.6);
        final title = find.text(item.displayTitle as String);
        expect(
          t.getRect(title).top -
              t.getRect(tile(kind, item.id as String)).bottom,
          closeTo(8, .01),
        );
        final caption = find.byWidgetPredicate(
          (w) =>
              w is MediaCardCaption &&
              w.tagKey == Key('${kind.name}-tag-names-${item.id}'),
        );
        final button = find.descendant(
          of: caption,
          matching: find.byType(IconButton),
        );
        expect(t.getSize(button).width, greaterThanOrEqualTo(48));
        expect(t.getSize(button).height, greaterThanOrEqualTo(48));
        expect(
          t.getRect(tag).bottom,
          lessThanOrEqualTo(t.getRect(caption).bottom),
        );
        expect(s.columns, 2);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );

    testWidgets(
      '${kind.name} rotation preserves the anchored member without a new query',
      (t) async {
        await start(t, kind);
        final s = state(t, kind);
        final id = s.data.items[10].id as String;
        s.scroll.jumpTo(s.listHeader + 5 * s.stride + 31);
        await frames(t);
        expect(s.position().ids.first, id);
        final reads = repo.videoReads.length, packs = repo.packRequests.length;
        t.view.physicalSize = const Size(844, 442);
        await frames(t);
        expect(s.columns, 4);
        expect(s.position().context.scrollIndex, 8);
        expect(s.position().context.scrollInset, closeTo(31, .1));
        final grid = find.byKey(Key('${kind.name}-grid'));
        expect(
          t.getRect(tile(kind, id)).top,
          closeTo(t.getRect(grid).top - 31, 1),
        );
        expect(repo.videoReads.length, reads);
        expect(repo.packRequests.length, packs);
        t.view.physicalSize = const Size(390, 844);
        await frames(t);
        expect(s.columns, 2);
        expect(s.position().context.scrollIndex, 8);
        expect(
          find
              .byKey(
                Key('${kind == MediaKind.pack ? 'pack-tile' : 'tile'}-$id'),
              )
              .hitTestable(),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );

    testWidgets('${kind.name} font reflow retains row inset and member', (
      t,
    ) async {
      await start(t, kind);
      final s = state(t, kind);
      final id = s.data.items[8].id as String, oldStride = s.stride as double;
      s.scroll.jumpTo(s.listHeader + 4 * s.stride + 27);
      await frames(t);
      t.platformDispatcher.textScaleFactorTestValue = 2;
      await frames(t);
      expect(s.stride, greaterThan(oldStride));
      expect(s.position().ids.first, id);
      expect(s.position().context.scrollInset, closeTo(27, .1));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    });
  }

  testWidgets('keyboard height does not change portrait columns', (t) async {
    int? columns;
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            viewInsets: EdgeInsets.only(bottom: 600),
          ),
          child: Builder(
            builder: (context) {
              columns = MediaLayout.columns(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(columns, 2);
  });
}
