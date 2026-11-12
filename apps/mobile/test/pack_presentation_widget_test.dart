import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/main.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary, frames;
import 'nonblocking_widgets_test.dart' show UnreadyVideo;

class PresentedLibrary extends WorkspaceLibrary {
  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) async {
    final page = await super.loadPacks(query, offset: offset, limit: limit);
    return CatalogPage(
      items: [
        for (final p in page.items)
          LibraryPack(
            id: p.id,
            rootId: p.rootId,
            path: p.path,
            name: p.name,
            title: p.id == 'p1' ? '春日外景' : null,
            author: p.id == 'p1' ? '作者很长也要保留原始完整资料' * 5 : null,
            number: p.id == 'p1' ? '034' : null,
            pageCount: p.pageCount,
            readableCount: p.readableCount,
            contentVersion: p.contentVersion,
            status: p.status,
            createdAt: p.createdAt,
            cover: p.cover,
            progress: p.id == 'p1'
                ? const PackProgress(
                    pageId: 'page3',
                    pageIndex: 2,
                    offsetRatio: 0,
                    completed: false,
                    revision: 1,
                    updatedAt: 100,
                  )
                : null,
            tags: p.tags,
            tagNames: p.tagNames,
          ),
      ],
      total: page.total,
      offset: page.offset,
      limit: page.limit,
    );
  }
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'card title and author preserve reference rows at scale $scale',
      (t) async {
        t.view.physicalSize = scale == 1
            ? const Size(390, 844)
            : const Size(360, 809);
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final original = VideoPlayerPlatform.instance;
        VideoPlayerPlatform.instance = UnreadyVideo();
        final repo = PresentedLibrary();
        await repo.initialize();
        addTearDown(() {
          repo.dispose();
          VideoPlayerPlatform.instance = original;
        });
        await t.pumpWidget(ShikaApp(repository: repo));
        await frames(t);
        await t.tap(find.byKey(const Key('kind-pack')));
        await frames(t);
        expect(
          MediaQuery.textScalerOf(t.element(find.text('春日外景'))).scale(14) / 14,
          scale,
        );
        expect(find.text('春日外景'), findsOneWidget);
        expect(find.text('作者很长也要保留原始完整资料' * 5), findsOneWidget);
        expect(find.text('庭院随拍'), findsOneWidget);
        expect(find.text('37 张'), findsOneWidget);
        expect(find.text('500 张'), findsOneWidget);
        expect(find.text('499 张可读'), findsNothing);
        expect(find.text('读到第 3 张'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byTooltip('图包操作 春日外景'));
        await t.tap(find.byTooltip('图包操作 春日外景'));
        await frames(t);
        expect(find.text('图包详情'), findsOneWidget);
        expect(find.text('春日外景'), findsWidgets);
        await t.tap(find.text('图包详情'));
        await frames(t);
        expect(find.text('500 张 · 499 张可读'), findsOneWidget);
        expect(find.text('春日外景'), findsWidgets);
        expect(t.takeException(), isNull);
        await t.tap(find.byTooltip('关闭面板'));
        await frames(t);
        await t.tap(find.byKey(const Key('catalog-select')));
        await frames(t);
        expect(find.text('读到第 3 张'), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await frames(t);
      },
    );
  }
}
