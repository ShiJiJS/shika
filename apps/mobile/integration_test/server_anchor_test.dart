import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/player.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF3 deep return locates surviving IDs and retries without losing the source',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      await fixture('/__fixture/preview/extend');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      Future<void> until(
        FutureOr<bool> Function() condition,
        String reason,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            debugPrint(
              'ANCHOR_UI ${t.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}',
            );
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        await t.pump(const Duration(milliseconds: 80));
      }

      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
      });
      await repo.connect(fixtureBase, 8761, fixturePassword);
      await repo.requestScan();
      await until(
        () => repo.libraryPreparation.value.ready,
        'extended library scan',
      );
      final entry = VideoEntryScope(search: '花卉', sort: VideoSort.name);
      final original = await repo.loadVideoEntry(entry, limit: 200);
      expect(original.total, 73);
      await repo.editTag(name: '返回定位');
      final label = repo.snapshot.tags.singleWhere(
        (id) => repo.tagName(id) == '返回定位',
      );
      await repo.setVideoTags(original.items.map((item) => item.id).toSet(), {
        label,
      });
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await until(
        () => find.byKey(const Key('nav-tags')).evaluate().isNotEmpty,
        'library entry',
      );
      await t.tap(find.byKey(const Key('nav-tags')));
      await until(() => find.text('返回定位').evaluate().isNotEmpty, 'tag entry');
      await t.tap(find.text('返回定位'));
      await until(() => find.text('73 个视频').evaluate().isNotEmpty, 'tag range');
      await t.enterText(find.byKey(const Key('video-search')), '花卉');
      await t.testTextInput.receiveAction(TextInputAction.done);
      final grid = find.byKey(const Key('video-grid'));
      ScrollController scroll() => t.widget<CustomScrollView>(grid).controller!;
      const targetPixels = 29 * 308.0 + 37;
      await until(() async {
        scroll().jumpTo(
          math.min(targetPixels, scroll().position.maxScrollExtent),
        );
        return (scroll().offset - targetPixels).abs() < 1;
      }, 'load through third page');
      final anchor = original.items[58].id, neighbor = original.items[59].id;
      final anchorTile = find.byKey(Key('tile-$anchor'));
      await until(
        () => anchorTile.hitTestable().evaluate().isNotEmpty,
        'deep anchor visible',
      );
      final originalTop = t.getTopLeft(anchorTile).dy;
      await t.tap(anchorTile);
      await until(
        () => find.byType(MovieStage).evaluate().isNotEmpty,
        'deep preview',
      );
      final session = t.widget<MovieStage>(find.byType(MovieStage)).session!;
      await until(
        () => session.debugPlayers.any((player) => player.value.isInitialized),
        'native deep video',
      );
      expect(repo.current!.id, anchor);
      final identity = repo.playbackIdentity;
      await fixture('/__fixture/preview/insert');
      await repo.requestScan();
      await until(
        () => repo.libraryPreparation.value.ready,
        'inserted content scanned',
      );
      final inserted = await repo.loadVideoEntry(
        VideoEntryScope(search: '000-new'),
      );
      expect(inserted.items, hasLength(1));
      await repo.setVideoTags({inserted.items.single.id}, {label});
      await repo.setVideoTags({anchor}, {label}, remove: true);
      expect(repo.current!.id, anchor);
      expect(repo.playbackTotal, 73);
      expect(repo.playbackIdentity, identity);
      await fixture('/__fixture/preview/fail');
      await t.tap(find.byKey(const Key('preview-back')));
      await until(
        () =>
            find.byKey(const Key('library-return-retry')).evaluate().isNotEmpty,
        'return failure has a local retry',
      );
      expect(session.debugPlayers, isEmpty);
      expect(scroll().offset, closeTo(targetPixels, 1));
      expect(anchorTile, findsOneWidget);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        '花卉',
      );
      await fixture('/__fixture/checkpoint/library');
      await t.pump(const Duration(seconds: 1));
      await fixture('/__fixture/preview/recover');
      await t.tap(find.byKey(const Key('library-return-retry')));
      final neighborTile = find.byKey(Key('tile-$neighbor'));
      await until(
        () =>
            find.byKey(const Key('library-return-retry')).evaluate().isEmpty &&
            neighborTile.hitTestable().evaluate().isNotEmpty,
        'retry locates the surviving neighbor',
      );
      // The inserted row and removed tag cancel numerically, but the saved anchor
      // is gone. The next stable ID is at 59 in the refreshed filtered catalog.
      expect(scroll().offset, closeTo(5 * 308.0 + 37, 1));
      expect(t.getTopLeft(neighborTile).dy, closeTo(originalTop, 1));
      expect(anchorTile, findsNothing);
      expect(find.text('73 个视频'), findsOneWidget);
      final round = await repo.api.json('GET', '/api/v1/playback');
      expect(round['id'], identity);
      expect(round['candidate_count'], 73);
      expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 1);
      final trace =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      final lookups = trace
          .where(
            (row) =>
                row['path'] == '/api/v1/videos' &&
                (row['query'] as Map).containsKey('anchor_ids'),
          )
          .toList();
      expect(lookups.any((row) => row['status'] == 503), isTrue);
      expect(
        lookups.any(
          (row) =>
              row['status'] == 200 &&
              row['query']['limit'] == '24' &&
              row['query']['offset'] == '58',
        ),
        isTrue,
      );
      await fixture('/__fixture/checkpoint/recovered');
      await t.pump(const Duration(seconds: 1));
      final refreshed = await repo.loadVideoEntry(
        VideoEntryScope(
          query: VideoQuery(tags: {label}),
          search: '花卉',
          sort: VideoSort.name,
        ),
        offset: 48,
        limit: 1,
      );
      final topId = refreshed.items.single.id;
      scroll().jumpTo(0);
      await until(
        () => find.byKey(Key('tile-$topId')).evaluate().isNotEmpty,
        'top of restored window',
      );
      await until(
        () => scroll().offset > 3000,
        'prepend previous page while retaining visible row',
      );
      expect(scroll().offset, closeTo(12 * 308.0, 1));
      expect(session.debugPlayers, isEmpty);
      debugPrint(
        'LF3_ANCHOR candidates=73 return_page=48 page_size=24 fallback_neighbor=59 retry=503/200 prepend=24',
      );
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
