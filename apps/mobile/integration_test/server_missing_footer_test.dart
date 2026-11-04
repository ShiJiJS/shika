import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/settings/missing_media_page.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/preferences.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Read-only missing footer and complete confirmation at large/short viewports',
    (t) async {
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      Future<void> until(FutureOr<bool> Function() done, String why) async {
        final end = DateTime.now().add(const Duration(seconds: 60));
        while (!await done()) {
          if (DateTime.now().isAfter(end)) fail('Footer timeout: $why');
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '页尾验证图包', seed['path'] as String, kind: MediaKind.pack),
      );
      final root = repo.snapshot.roots.singleWhere(
        (r) => r.path == seed['path'],
      );
      Future<void> enabled(bool value) => repo.saveRoot(
        MediaRoot(
          root.id,
          root.name,
          root.path,
          kind: MediaKind.pack,
          enabled: value,
        ),
      );
      await enabled(true);
      Future<void> sync() async {
        final previous = repo.libraryPreparation.value.taskId;
        await repo.requestScan();
        await until(
          () =>
              repo.libraryPreparation.value.taskId != previous &&
              repo.libraryPreparation.value.status == 'completed',
          'new scan complete',
        );
      }

      await sync();
      final available = await repo.loadPacks(PackQuery());
      expect(available.total, 27);
      await fixture('/__fixture/actions/missing-native-folders');
      await sync();
      await enabled(false);
      final catalog = repo.createPackMissing();
      expect((await catalog.page()).total, 25);
      catalog.dispose();
      final before = await fixture('/__fixture/actions/pack-trash-hashes');
      final beforeStats = await fixture(
        '/__fixture/actions/missing-native-stats',
      );
      final video = (await repo.loadVideos(limit: 1)).items.single;
      await repo.beginPreview(VideoEntryScope(), anchor: video.id);
      final roundBefore = await repo.api.json(
        'GET',
        '/api/v1/playback',
        query: {'create': 'false'},
      );
      await fixture('/__fixture/actions/reset-task-trace');
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      Future<void> reveal(Finder target) async {
        for (final direction in [1, -1]) {
          for (var i = 0; target.evaluate().isEmpty && i < 60; i++) {
            final scroll = find.byType(Scrollable).hitTestable();
            if (scroll.evaluate().isEmpty) break;
            await t.drag(scroll.last, Offset(0, -450.0 * direction));
            await t.pumpAndSettle();
          }
          if (target.evaluate().isNotEmpty) break;
        }
        expect(target, findsOneWidget);
        await t.ensureVisible(target);
        await t.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
      }

      Future<void> tap(Finder target) async {
        await reveal(target);
        await t.tap(target);
        await t.pumpAndSettle();
      }

      Future<void> shot(String state, Map<String, dynamic> details) async {
        final m = MediaQueryData.fromView(t.view);
        debugPrint(
          'FOOTER_METRICS:${jsonEncode({
            'state': state,
            'window': [m.size.width, m.size.height],
            'dpr': m.devicePixelRatio,
            'viewPadding': [m.viewPadding.left, m.viewPadding.top, m.viewPadding.right, m.viewPadding.bottom],
            'text13': m.textScaler.scale(13),
            ...details,
          })}',
        );
        await fixture('/__fixture/checkpoint/$state');
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
      }

      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('媒体目录'));
      await tap(find.text('缺失内容'));
      await until(
        () =>
            find.byType(MissingMediaPage).evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'missing route ready',
      );
      await tap(find.byKey(const Key('missing-kind-pack')));
      await until(
        () =>
            find.text('共 25 个缺失图包').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'typed missing count',
      );
      await tap(find.text('下一页'));
      await until(
        () => find.text('25–25 / 25').evaluate().isNotEmpty,
        'second page',
      );
      await reveal(find.text('返回媒体目录'));
      final pageScroll = t
          .widget<ListView>(find.byKey(const Key('missing-list')))
          .controller!;
      expect(pageScroll.position.extentAfter, closeTo(0, 1));
      expect(
        find.byKey(const Key('clear-missing-kind')).hitTestable(),
        findsOneWidget,
      );
      final footer = t.getRect(find.byKey(const Key('clear-missing-kind')));
      await shot('missing-paged', {
        'footer': [footer.left, footer.top, footer.width, footer.height],
        'remaining_scroll': pageScroll.position.extentAfter,
      });
      await tap(find.byKey(const Key('clear-missing-kind')));
      final sheetScroll = find
          .descendant(
            of: find.byType(SheetFrame),
            matching: find.byType(Scrollable),
          )
          .last;
      final position = t.state<ScrollableState>(sheetScroll).position;
      for (var i = 0; position.extentAfter > 1 && i < 20; i++) {
        await t.drag(sheetScroll, const Offset(0, -350));
        await t.pumpAndSettle();
      }
      expect(position.extentAfter, closeTo(0, 1));
      final message = find.textContaining('之后找回会作为新图包入库。');
      expect(
        t.getRect(message).bottom,
        lessThanOrEqualTo(t.getRect(sheetScroll).bottom + 1),
      );
      expect(
        find.byKey(const Key('missing-confirm')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('取消').hitTestable(), findsOneWidget);
      await shot('missing-confirm-cancel', {
        'confirmation_tail_visible': true,
        'remaining_scroll': position.extentAfter,
      });
      await tap(find.text('取消'));
      expect(await fixture('/__fixture/actions/pack-trash-hashes'), before);
      expect(
        await fixture('/__fixture/actions/missing-native-stats'),
        beforeStats,
      );
      expect(
        await repo.api.json(
          'GET',
          '/api/v1/playback',
          query: {'create': 'false'},
        ),
        roundBefore,
      );
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(trace.where((e) => e['method'] != 'GET'), isEmpty);
      debugPrint(
        'MISSING_FOOTER_VERIFIED:${jsonEncode({'images': (before['hashes'] as Map).length, 'zero_writes_after_preparation': true, 'current_video_unchanged': true, 'cancelled': true})}',
      );
    },
  );
}
