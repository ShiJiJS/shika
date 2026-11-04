import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/player.dart';
import 'package:shika/features/library/tag_catalog_page.dart';
import 'package:shika/ui/preferences.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF4 native dual catalogs, independent labels, source queries and retained settings',
    (t) async {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      expect(seed['pack_count'], 27);
      final store = SecureCredentialStore(key: 'video_viewer.e2e.workspace.v1');
      await store.clear();
      final repo = ServerLibraryRepository(store, port: 8761);
      final preferences = UiPreferences();
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
        preferences.dispose();
        await store.clear();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '测试图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final packs = await repo.loadPacks(PackQuery());
      expect(packs.total, 27);
      expect(packs.items, hasLength(24));
      expect(packs.items.first.pageCount, 3);
      final packTag = await repo.createPackTag('自然');
      await repo.setPackTags({packs.items.first.id}, {packTag.id});
      await repo.editTag(name: '自然');
      final videoTag = repo.snapshot.tags.singleWhere(
        (id) => repo.tagName(id) == '自然',
      );
      final videos = await repo.loadVideos();
      await repo.setVideoTags({videos.items.first.id}, {videoTag});
      expect((await repo.loadPackTags()).items.single.count, 1);
      expect(repo.tagVideoCount(videoTag), 1);
      await t.pumpWidget(
        ShikaApp(repository: repo, preferences: preferences),
      );

      Future<void> until(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            await fixture('/__fixture/checkpoint/error');
            await t.pump(const Duration(seconds: 1));
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 200));
      }

      Future<void> idle() => until(
        () =>
            find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'catalog settled',
      );
      Future<void> tap(Finder finder) async {
        if (finder.hitTestable().evaluate().isEmpty) {
          await t.ensureVisible(finder);
        }
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 300));
        await idle();
      }

      Future<void> nav(String tab) => tap(find.byKey(Key('nav-$tab')));
      Future<void> count(int value, {bool pack = false}) => until(() {
        final label = find.byKey(Key(pack ? 'pack-count' : 'library-count'));
        return label.evaluate().isNotEmpty &&
            t.widget<Text>(label).data == '$value 个${pack ? '图包' : '视频'}';
      }, 'authoritative result-list count $value');
      Future<void> shot(String state) async {
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/workspace-$state');
        await t.pump(const Duration(seconds: 2));
      }

      Future<void> search(String value, {bool pack = false}) async {
        await tap(find.byKey(Key(pack ? 'pack-search' : 'video-search')));
        await t.enterText(
          find.byKey(Key(pack ? 'pack-search' : 'video-search')),
          value,
        );
        await t.pump(const Duration(milliseconds: 200));
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await idle();
        expect(
          t
              .widget<TextField>(
                find.byKey(Key(pack ? 'pack-search' : 'video-search')),
              )
              .controller!
              .text,
          value,
        );
      }

      await nav('library');
      await count(27);
      expect(find.byKey(const Key('nav-browse')), findsNothing);
      expect(find.byType(MovieStage), findsNothing);
      await until(
        () => t
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
        'video covers decoded',
      );
      await shot('video');
      await search('片段02');
      await count(1);
      await tap(find.byKey(const Key('kind-pack')));
      await count(27, pack: true);
      final grid = find.byKey(const Key('pack-grid'));
      int cards() => t
          .widget<SliverGrid>(
            find.descendant(of: grid, matching: find.byType(SliverGrid)),
          )
          .delegate
          .estimatedChildCount!;
      expect(cards(), 24);
      await until(
        () => t
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
        'authenticated pack covers decoded',
      );
      await until(
        () => find.byTooltip('重新加载封面').hitTestable().evaluate().isEmpty,
        'busy covers retried with a bounded delay',
      );
      await shot('packs');
      await t.drag(grid, const Offset(0, -6000));
      await until(() => cards() == 27, 'second pack page appended');
      await search('图包02', pack: true);
      await count(1, pack: true);
      await tap(find.byKey(const Key('kind-video')));
      await count(1);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('video-search')))
            .controller!
            .text,
        '片段02',
      );
      await nav('tags');
      await t.scrollUntilVisible(
        find.byKey(Key('video-tag-$videoTag')),
        140,
        scrollable: find.descendant(
          of: find.byType(TagCatalogPage),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await until(
        () => find.byKey(Key('video-tag-$videoTag')).evaluate().isNotEmpty,
        'video label row',
      );
      await tap(find.byKey(Key('video-tag-$videoTag')));
      await until(
        () => find.text('匹配 1 个视频').evaluate().isNotEmpty,
        'video intersection count',
      );
      await shot('video-tags');
      await tap(find.byKey(const Key('tag-preview-results')));
      await until(
        () => find.byType(MovieStage).evaluate().isNotEmpty,
        'direct tag preview route',
      );
      expect(repo.fixedPreview, isTrue);
      expect(repo.playbackTotal, 1);
      expect(repo.savedPreviewEntry!.source, BrowseSource.tags);
      expect(repo.savedPreviewEntry!.query.tags, {videoTag});
      final previewId = repo.playbackIdentity;
      await tap(find.byKey(const Key('preview-back')));
      await until(
        () => find.byType(MovieStage).evaluate().isEmpty,
        'direct preview returns to tag results',
      );
      await tap(find.byTooltip('返回标签选择'));
      await tap(find.byKey(const Key('tag-view-results')));
      await count(1);
      expect(find.byType(MovieStage), findsNothing);
      await tap(find.byTooltip('返回标签选择'));
      await tap(find.byKey(const Key('kind-pack')));
      await t.scrollUntilVisible(
        find.byKey(Key('pack-tag-${packTag.id}')),
        140,
        scrollable: find.descendant(
          of: find.byType(TagCatalogPage),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await until(
        () => find.byKey(Key('pack-tag-${packTag.id}')).evaluate().isNotEmpty,
        'separate pack label row',
      );
      await tap(find.byKey(Key('pack-tag-${packTag.id}')));
      await until(
        () => find.text('查看 1 个图包').evaluate().isNotEmpty,
        'pack intersection count',
      );
      await shot('pack-tags');
      await tap(find.byKey(const Key('tag-view-results')));
      await count(1, pack: true);
      await nav('library');
      await count(1);
      await tap(find.byKey(const Key('kind-pack')));
      await count(1, pack: true);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('pack-search')))
            .controller!
            .text,
        '图包02',
      );
      await nav('settings');
      for (final entry in ['服务连接', '媒体目录', '回收站', '备份与恢复']) {
        expect(find.text(entry), findsOneWidget);
      }
      await shot('settings');
      await preferences.setDark(true);
      await until(
        () =>
            Theme.of(t.element(find.byKey(const Key('nav-settings'))))
                .brightness ==
            Brightness.dark,
        'dark appearance applied',
      );
      await nav('library');
      await search('', pack: true);
      await count(27, pack: true);
      await shot('dark');
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        trace.any(
          (r) => r['path'] == '/api/v1/packs' && r['query']['offset'] == '24',
        ),
        isTrue,
      );
      expect(
        trace.any(
          (r) =>
              (r['path'] as String).endsWith('/cover') &&
              r['authenticated'] == true,
        ),
        isTrue,
      );
      expect(
        repo.playbackIdentity,
        previewId,
        reason: 'subsequent catalog browsing does not replace the explicit tag preview',
      );
      expect(t.takeException(), isNull);
    },
  );
}
