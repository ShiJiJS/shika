import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';

Future<Map<String, dynamic>> control(String path, {bool post = false}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      post ? 'POST' : 'GET',
      Uri.parse('http://10.0.2.2:8764/__reader_errors$path'),
    );
    request.headers.set('X-Fixture-Key', 'reader-image-errors-owned-control');
    final response = await request.close();
    expect(response.statusCode, 200);
    return Map<String, dynamic>.from(
      jsonDecode(await response.transform(utf8.decoder).join()) as Map,
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real missing and corrupt last images stop at explicit pack end',
    (t) async {
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8764);
      final preferences = UiPreferences(preloadAdjacent: false);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        preferences.dispose();
      });
      await repo.connect(
        'http://10.0.2.2',
        8764,
        'reader-image-errors-owned-only',
      );
      final root = repo.snapshot.roots.single;
      await repo.saveRoot(
        MediaRoot(root.id, root.name, root.path, kind: MediaKind.pack),
      );
      await repo.refresh();
      final all = await repo.loadPacks(PackQuery(), limit: 24);
      expect(all.total, 2);
      final failed = all.items.singleWhere((v) => v.name == '异常图包 A');
      final good = all.items.singleWhere((v) => v.name == '正常图包 B');
      await t.pumpWidget(
        VideoViewerApp(
          repository: repo,
          preferences: preferences,
          initializeRepository: false,
        ),
      );
      PackReaderPageState reader() => t.state(find.byType(PackReaderPage));
      Future<void> until(bool Function() done, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Reader error timeout: $label');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> tap(Finder target) async {
        await until(() => target.evaluate().length == 1, 'unique target');
        await t.ensureVisible(target);
        await until(
          () => target.hitTestable().evaluate().length == 1,
          'visible target',
        );
        await t.tap(target.hitTestable());
        await t.pump(const Duration(milliseconds: 350));
      }

      Future<void> capture(String name) async {
        await control('/checkpoint/$name', post: true);
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while ((await control('/state'))['ack'] != true) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Host did not capture $name');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> unmodifiedFailure() async {
        final value = await repo.api.json('GET', '/api/v1/packs/${failed.id}');
        expect(value['progress'], isNull);
        final recent = await repo.api.json(
          'GET',
          '/api/v1/recent',
          query: {'kind': 'pack'},
        );
        expect(recent['items'], isEmpty);
        expect(reader().session.range!.pack!.id, failed.id);
        expect(reader().session.opened, isFalse);
      }

      await tap(find.byKey(const Key('kind-pack')));
      for (final mode in ['missing', 'corrupt']) {
        final armed = await control(
          '/arm/$mode?pack_id=${failed.id}',
          post: true,
        );
        expect((armed['page_ids'] as List).length, 3);
        await tap(find.byKey(Key('pack-tile-${failed.id}')));
        await until(
          () => reader().session.range != null && !reader().session.busy,
          'range',
        );
        if (mode == 'corrupt') {
          await tap(find.byTooltip('阅读设置'));
          await tap(find.text('纵向拼接'));
          await until(
            () =>
                reader().session.preferences.mode == ReaderMode.vertical &&
                !reader().session.busy,
            'vertical preference',
          );
          await tap(find.text('继续阅读'));
        }
        for (var index = 1; index < 3; index++) {
          await tap(find.byTooltip('下一张'));
          await until(() => reader().session.index == index, 'next image');
        }
        final skip = find.byKey(
          Key('reader-image-skip-${reader().session.currentPage!.id}'),
        );
        await until(() => skip.evaluate().length == 1, 'last image failed');
        await t.ensureVisible(skip);
        await t.pump(const Duration(milliseconds: 200));
        await capture('$mode-last-failure');
        if (mode == 'missing') await tap(find.text('沉浸'));
        await tap(skip);
        await until(
          () => find.text('跳过这一张').evaluate().isEmpty,
          'failed image left',
        );
        expect(find.text('已到本包末尾').hitTestable(), findsOneWidget);
        await unmodifiedFailure();
        await capture('$mode-pack-end');
        if (mode == 'missing') {
          await tap(find.text('返回最后一张'));
          await until(
            () => find.text('跳过这一张').evaluate().isNotEmpty,
            'last image reopened',
          );
          await t.ensureVisible(
            find.byKey(
              Key('reader-image-skip-${reader().session.currentPage!.id}'),
            ),
          );
          await capture('missing-last-image');
          await tap(find.byTooltip('下一张'));
          await until(
            () => find.text('跳过这一张').evaluate().isEmpty,
            'next button reaches end',
          );
          await unmodifiedFailure();
          await tap(find.text('返回来源'));
          await until(
            () => find.byType(PackReaderPage).evaluate().isEmpty,
            'source returned',
          );
        }
      }
      expect(reader().session.range!.next!.packId, good.id);
      await tap(find.text('阅读下一包'));
      await until(
        () =>
            reader().session.range!.pack!.id == good.id &&
            reader().session.opened &&
            !reader().session.busy,
        'explicit next pack decoded',
      );
      final recent = await repo.api.json(
        'GET',
        '/api/v1/recent',
        query: {'kind': 'pack'},
      );
      expect((recent['items'] as List).map((v) => v['id']).toSet(), {good.id});
      final unchanged = await repo.api.json(
        'GET',
        '/api/v1/packs/${failed.id}',
      );
      expect(unchanged['progress'], isNull);
      await capture('explicit-next-pack');
      debugPrint(
        'READER_ERRORS_VERIFIED:${jsonEncode({
          'failed_pack': failed.id,
          'good_pack': good.id,
          'failed_progress': null,
          'recent': [good.id],
          'modes': ['missing', 'corrupt'],
        })}',
      );
      expect(t.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
