import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/playback_session.dart';
import 'package:shika/ui/player.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF3 real library scope, native player, complete queue and return',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8761);
      PlaybackSession? session;
      var peakDecoders = 0;
      void bounded() {
        final players = session?.debugPlayers ?? <VideoPlayerController>[];
        peakDecoders = peakDecoders < players.length
            ? players.length
            : peakDecoders;
        expect(players.length, lessThanOrEqualTo(3));
        expect(
          players.where((p) => p.value.isPlaying && p.value.volume > 0).length,
          lessThanOrEqualTo(1),
        );
      }

      Future<void> until(
        FutureOr<bool> Function() condition,
        String reason, {
        int seconds = 40,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (!await condition()) {
          bounded();
          if (DateTime.now().isAfter(deadline)) {
            debugPrint(
              'VISIBLE_UI ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).join(' | ')}',
            );
            await fixture('/__fixture/checkpoint/error');
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 80));
        }
        bounded();
        await t.pump(const Duration(milliseconds: 80));
      }

      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
      });
      await repo.connect(fixtureBase, 8761, fixturePassword);
      await t.pumpWidget(ShikaApp(repository: repo));
      await until(
        () =>
            repo.libraryPreparation.value.ready &&
            find.byKey(const Key('video-search')).evaluate().isNotEmpty,
        'library ready',
      );
      expect(find.byType(MovieStage), findsNothing);
      expect(repo.playbackIdentity, isEmpty);
      expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 0);
      await t.enterText(find.byKey(const Key('video-search')), '花卉');
      await until(
        () => find.text('25 个视频').evaluate().isNotEmpty,
        'directory search matches all 25',
      );
      final before =
          (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
      expect(
        before.where(
          (row) => row['method'] == 'POST' && row['path'] == '/api/v1/rounds',
        ),
        isEmpty,
      );
      expect(
        before.where(
          (row) =>
              row['path'] == '/api/v1/videos' &&
              row['query']['search'] == '花卉' &&
              row['query']['limit'] == '24',
        ),
        isNotEmpty,
      );
      await t.tap(find.text('预览此范围'));
      await until(
        () =>
            find.byType(MovieStage).evaluate().isNotEmpty && repo.fixedPreview,
        'secondary preview',
      );
      session = t.widget<MovieStage>(find.byType(MovieStage)).session!;
      await until(
        () =>
            find.byType(VideoPlayer).evaluate().isNotEmpty &&
            session!.debugPlayers.any(
              (p) =>
                  p.value.isInitialized &&
                  !p.value.size.isEmpty &&
                  p.value.isPlaying,
            ),
        'native picture and playback',
      );
      expect(find.byKey(const Key('app-navigation')), findsNothing);
      final round = await repo.api.json(
        'GET',
        '/api/v1/playback',
        query: {'create': 'false'},
      );
      expect(round['membership'], 'fixed');
      expect(round['scope']['search'], '花卉');
      expect(round['candidate_count'], 25);
      expect(repo.playbackTotal, 25);
      final identity = repo.playbackIdentity, firstId = repo.current!.id;
      await until(
        () async =>
            (await repo.api.json('GET', '/api/v1/recent'))['total'] == 1,
        'only visible video enters recents',
      );
      await fixture('/__fixture/checkpoint/preview');
      await t.pump(const Duration(seconds: 1));

      // A native long press retains the existing temporary 2x behavior.
      final current = session.debugPlayers.firstWhere((p) => p.value.isPlaying);
      final gesture = await t.startGesture(
        t.getCenter(find.byKey(const Key('video-gesture-surface')).last),
      );
      await t.pump(const Duration(milliseconds: 650));
      expect(current.value.playbackSpeed, 2);
      await gesture.up();
      await until(
        () => current.value.playbackSpeed == 1,
        'temporary speed restored',
      );

      await t.tap(find.byKey(const Key('preview-scope')));
      await until(
        () => find.byKey(const Key('preview-queue')).evaluate().isNotEmpty,
        'queue opens',
      );
      await t.tap(find.byKey(const Key('queue-order-sequential')));
      await until(
        () => repo.snapshot.order == PlayOrder.sequential,
        'sequential mode uses the same members',
      );
      expect(repo.current!.id, firstId);
      expect(repo.playbackIdentity, identity);
      final entries =
          (await repo.api.json(
                'GET',
                '/api/v1/rounds/$identity/entries',
                query: {'limit': '100'},
              ))['items']
              as List;
      final lastId = entries.last['video']['id'] as String;
      final last = find.byKey(Key('queue-video-$lastId'));
      for (var i = 0; i < 15 && last.hitTestable().evaluate().isEmpty; i++) {
        await t.drag(
          find.byKey(const Key('preview-queue')),
          const Offset(0, -500),
        );
        await t.pump(const Duration(milliseconds: 180));
      }
      await until(
        () => last.hitTestable().evaluate().isNotEmpty,
        'last complete candidate, beyond first library page',
      );
      await t.tap(last);
      await until(
        () =>
            find.byKey(const Key('preview-queue')).evaluate().isEmpty &&
            repo.current?.id == lastId,
        'queue selects last video',
      );
      expect(repo.playbackPosition, 24);
      await t.tap(find.byKey(const Key('preview-next')));
      await until(
        () => find.text('本次范围已到末尾').evaluate().isNotEmpty,
        'explicit range end',
      );
      await t.tap(find.byKey(const Key('preview-restart')));
      await until(
        () =>
            repo.playbackPosition == 0 &&
            find.text('本次范围已到末尾').evaluate().isEmpty,
        'restart stays inside same session',
      );
      expect(repo.playbackIdentity, identity);
      expect(repo.playbackTotal, 25);
      await t.tap(find.byKey(const Key('preview-back')));
      await until(
        () =>
            find.byKey(const Key('video-preview-route')).evaluate().isEmpty &&
            session!.debugPlayers.isEmpty,
        'return releases every decoder',
      );
      await until(
        () => find.text('25 个视频').evaluate().isNotEmpty,
        'source results restored',
      );
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        '花卉',
      );
      expect((await repo.api.json('GET', '/api/v1/playback'))['id'], identity);
      expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 2);
      debugPrint(
        'LF3_PREVIEW peak_decoders=$peakDecoders candidates=25 initial_page=24',
      );
      await fixture('/__fixture/checkpoint/library');
      await t.pump(const Duration(seconds: 1));
      await t.enterText(find.byKey(const Key('video-search')), '横版片段');
      await until(
        () => find.text('1 个视频').evaluate().isNotEmpty,
        'landscape result',
      );
      await t.tap(find.text('预览此范围'));
      await until(
        () =>
            find.byType(MovieStage).evaluate().isNotEmpty &&
            repo.playbackIdentity != identity,
        'explicit new entry creates a new scope',
      );
      session = t.widget<MovieStage>(find.byType(MovieStage)).session!;
      await until(
        () => session!.debugPlayers.any(
          (p) => p.value.isInitialized && p.value.isPlaying,
        ),
        'landscape picture',
      );
      final landscape = session.debugPlayers.firstWhere(
        (p) => p.value.isPlaying,
      );
      await t.tap(find.byKey(const Key('video-gesture-surface')).last);
      await until(() => !landscape.value.isPlaying, 'pause intent');
      await until(
        () => find
            .byKey(const Key('inline-play'))
            .hitTestable()
            .evaluate()
            .isNotEmpty,
        'paused inline controls',
      );
      await fixture('/__fixture/checkpoint/formats');
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.widgetWithText(FilledButton, '横向全屏'));
      await until(
        () => find.byKey(const Key('fullscreen-exit')).evaluate().isNotEmpty,
        'native fullscreen',
      );
      expect(landscape.value.isPlaying, isFalse);
      await t.tap(find.byKey(const Key('fullscreen-exit')));
      await until(
        () =>
            find.byKey(const Key('fullscreen-exit')).evaluate().isEmpty &&
            find
                .byKey(const Key('preview-back'))
                .hitTestable()
                .evaluate()
                .isNotEmpty,
        'fullscreen returns to preview',
      );
      expect(landscape.value.isPlaying, isFalse);
      await t.tap(find.byKey(const Key('preview-back')));
      await until(
        () =>
            find.byKey(const Key('video-preview-route')).evaluate().isEmpty &&
            session!.debugPlayers.isEmpty,
        'landscape leave releases decoders',
      );
      expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 3);
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
