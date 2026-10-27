import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/tag_catalog_page.dart';
import 'package:video_viewer/features/library/video_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/preferences.dart';
import 'package:video_viewer/ui/paper.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('video tag definitions retain edits and isolate pack names', (
    t,
  ) async {
    final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
    final prefs = UiPreferences(preloadAdjacent: false);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      prefs.dispose();
    });
    await repo.connect(
      'http://10.0.2.2',
      8768,
      'prototype-fidelity-owned-only',
    );
    final initialVideo = await repo.loadVideoTags();
    final initialPack = await repo.loadPackTags();
    final videoId = initialVideo.items.singleWhere((v) => v.name == '户外').id;
    final packId = initialPack.items.singleWhere((v) => v.name == '户外').id;
    expect(videoId, isNot(packId));
    final packKimonoId = initialPack.items
        .singleWhere((v) => v.name == '和服')
        .id;
    expect(initialVideo.items.every((v) => v.name != '和服'), isTrue);
    final linkedVideos =
        (await repo.api.json(
              'GET',
              '/api/v1/videos',
              query: {'tag_ids': videoId},
            ))['items']
            as List;
    final linkedPacks =
        (await repo.api.json(
              'GET',
              '/api/v1/packs',
              query: {'tag_ids': packId},
            ))['items']
            as List;
    expect(linkedVideos.length, 2);
    expect(linkedPacks, isNotEmpty);
    Future<Map<String, dynamic>> playback() async {
      try {
        return await repo.api.json(
          'GET',
          '/api/v1/playback',
          query: {'create': 'false'},
        );
      } on ApiFailure catch (error) {
        expect(error.status, 404);
        expect(error.code, 'round_not_started');
        return {'status': error.status, 'code': error.code};
      }
    }

    final playbackBefore = await playback();
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: prefs,
        initializeRepository: false,
      ),
    );
    Future<void> until(FutureOr<bool> Function() done, String reason) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!await done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Video tag definition timeout: $reason');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> tap(Finder target) async {
      if (target.evaluate().isEmpty &&
          find.byType(TagCatalogPage).evaluate().length == 1 &&
          find.byType(SheetFrame).evaluate().isEmpty) {
        final body = find.descendant(
          of: find.byType(TagCatalogPage),
          matching: find.byType(CustomScrollView),
        );
        final scroller = find.descendant(
          of: body,
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
        await t.scrollUntilVisible(
          target,
          160,
          scrollable: scroller.first,
          maxScrolls: 40,
        );
      }
      await until(() => target.evaluate().length == 1, 'unique $target');
      if (target.hitTestable().evaluate().isEmpty) {
        await t.ensureVisible(target);
      }
      await until(
        () => target.hitTestable().evaluate().length == 1,
        'visible $target',
      );
      await t.tap(target);
      await t.pump(const Duration(milliseconds: 200));
    }

    TagCatalogPageState state() => t.state(find.byType(TagCatalogPage));
    final field = find.byKey(const Key('tag-name'));
    TextEditingController input() => t.widget<TextField>(field).controller!;
    Future<void> hideKeyboard() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await until(
        () => t.view.viewInsets.bottom == 0,
        'native keyboard hidden',
      );
    }

    Future<void> enter(String name, {bool keyboard = false}) async {
      await tap(field);
      await t.enterText(field, name);
      await until(() => input().text == name, 'input delivered');
      if (keyboard) {
        await until(
          () => t.view.viewInsets.bottom > 0,
          'actual native keyboard shown',
        );
        await t.pumpAndSettle();
        await t.ensureVisible(field);
        await t.pumpAndSettle();
        final view = MediaQueryData.fromView(t.view);
        expect(
          t.getRect(field).bottom,
          lessThanOrEqualTo(view.size.height - view.viewInsets.bottom),
        );
      } else {
        await hideKeyboard();
      }
    }

    Future<void> error(String draft, {bool confirming = false}) async {
      final message = find.byKey(const Key('tag-definition-error'));
      await until(
        () => message.evaluate().length == 1 && !state().saving,
        'write rejected and draft enabled',
      );
      await t.ensureVisible(message);
      expect(state().error, isEmpty);
      if (confirming) {
        expect(
          find.descendant(
            of: find.byType(SheetFrame),
            matching: find.text(draft),
          ),
          findsOneWidget,
        );
        expect(
          t
              .widget<FilledButton>(
                find.byKey(const Key('tag-definition-remove-confirm')),
              )
              .onPressed,
          isNotNull,
        );
      } else {
        expect(input().text, draft);
        expect(t.widget<TextField>(field).enabled, isTrue);
      }
    }

    Future<void> capture(String name) async {
      await t.pump(const Duration(milliseconds: 200));
      final media = MediaQueryData.fromView(t.view);
      final boxes = <String, List<double>>{};
      for (final key in [
        'tag-name',
        'tag-definition-save',
        'tag-definition-error',
        'tag-definition-remove-confirm',
      ]) {
        final f = find.byKey(Key(key));
        if (f.evaluate().length == 1) {
          final r = t.getRect(f);
          boxes[key] = [r.left, r.top, r.width, r.height];
        }
      }
      final page = find.byType(TagCatalogPage).evaluate().length == 1
          ? state()
          : null;
      debugPrint(
        'FIDELITY_METRICS:${jsonEncode({
          'state': name,
          'physical': [media.size.width * media.devicePixelRatio, media.size.height * media.devicePixelRatio],
          'dpr': media.devicePixelRatio,
          'text_scale': media.textScaler.scale(14) / 14,
          'keyboard': media.viewInsets.bottom,
          'boxes': boxes,
          'draft': field.evaluate().length == 1 ? input().text : null,
          'kind': page?.widget.kind.name,
          'tags': page?.tags.map((v) => {'id': v.id, 'name': v.name, 'count': v.count}).toList(),
          'selected': page?.selected.toList(),
          'matching': page?.matching,
          'saving': page?.saving,
        })}',
      );
      await control('/checkpoint/$name', post: true);
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while ((await control('/state'))['ack'] != true) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Missing screenshot $name');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> save() => tap(find.byKey(const Key('tag-definition-save')));
    Future<void> ready(bool pack) => until(
      () =>
          find.byType(TagCatalogPage).evaluate().length == 1 &&
          state().pack == pack &&
          !state().loading,
      'tag directory ready',
    );

    await until(
      () => find.byKey(const Key('nav-tags')).evaluate().isNotEmpty,
      'workspace ready',
    );
    await tap(find.byKey(const Key('nav-tags')));
    await ready(false);
    await tap(find.byKey(Key('video-tag-$videoId')));
    await until(
      () => state().matching == 2,
      'selected video association count',
    );
    await capture('tagdef-video');
    await tap(find.byTooltip('新建视频标签'));
    await enter('户外', keyboard: true);
    await capture('tagdef-create-keyboard');
    await hideKeyboard();
    await save();
    await error('户外');
    await capture('tagdef-create-conflict');
    await tap(find.byTooltip('关闭面板'));
    expect((await repo.api.json('GET', '/api/v1/tags'))['total'], 3);
    await tap(find.byTooltip('新建视频标签'));
    await enter('和服');
    await save();
    await until(
      () => field.evaluate().isEmpty && state().tags.any((v) => v.name == '和服'),
      'created video-only definition',
    );
    final created =
        ((await repo.api.json(
                      'GET',
                      '/api/v1/tags',
                      query: {'search': '和服'},
                    ))['items']
                    as List)
                .single['id']
            as String;
    expect(created, isNot(packKimonoId));
    expect(
      ((await repo.api.json(
                'GET',
                '/api/v1/pack-tags',
                query: {'search': '和服'},
              ))['items']
              as List)
          .single['id'],
      packKimonoId,
    );
    await capture('tagdef-created');

    await tap(find.byTooltip('管理视频标签 户外'));
    await enter('自然');
    await save();
    await error('自然');
    await capture('tagdef-rename-conflict');
    await enter('户外视频改名');
    await control('/tag-definition-failure/rename', post: true);
    await save();
    await error('户外视频改名');
    expect(state().selected, {videoId});
    await capture('tagdef-rename-failure');
    await control('/tag-definition-failure/off', post: true);
    await save();
    await until(
      () =>
          field.evaluate().isEmpty &&
          state().tags.any((v) => v.id == videoId && v.name == '户外视频改名'),
      'rename retained ID',
    );
    expect(state().selected, {videoId});
    await until(() => state().matching == 2, 'rename retained associations');
    expect(
      ((await repo.api.json(
                'GET',
                '/api/v1/tags',
                query: {'search': '户外视频改名'},
              ))['items']
              as List)
          .single['id'],
      videoId,
    );
    await capture('tagdef-renamed');
    await tap(find.byKey(const Key('kind-pack')));
    await ready(true);
    await tap(find.byKey(Key('pack-tag-$packId')));
    await until(
      () => state().matching == linkedPacks.length,
      'pack-only count',
    );
    await capture('tagdef-pack');
    await tap(find.byKey(const Key('kind-video')));
    await ready(false);
    expect(state().selected, {videoId});

    await tap(find.byTooltip('管理视频标签 户外视频改名'));
    await enter('取消后的草稿');
    await tap(find.byKey(const Key('tag-definition-remove')));
    await until(
      () =>
          find
              .byKey(const Key('tag-definition-remove-confirm'))
              .evaluate()
              .length ==
          1,
      'remove confirmation',
    );
    await capture('tagdef-remove-confirm');
    await tap(find.text('取消').last);
    expect(input().text, '取消后的草稿');
    await capture('tagdef-remove-cancel');
    await tap(find.byTooltip('关闭面板'));
    await tap(find.byTooltip('管理视频标签 户外视频改名'));
    expect(input().text, '户外视频改名');
    await tap(find.byKey(const Key('tag-definition-remove')));
    await control('/tag-definition-failure/remove', post: true);
    await tap(find.byKey(const Key('tag-definition-remove-confirm')));
    await error('户外视频改名', confirming: true);
    await capture('tagdef-remove-failure');
    await control('/tag-definition-failure/off', post: true);
    await tap(find.byKey(const Key('tag-definition-remove-confirm')));
    await until(
      () =>
          find
              .byKey(const Key('tag-definition-remove-confirm'))
              .evaluate()
              .isEmpty &&
          state().tags.every((v) => v.id != videoId),
      'video-only definition removed',
    );
    expect(state().selected, isEmpty);
    await capture('tagdef-removed');
    await tap(find.byKey(const Key('nav-settings')));
    await tap(find.byKey(const Key('nav-tags')));
    await ready(false);
    expect(state().tags.any((v) => v.id == created), isTrue);
    expect(state().tags.any((v) => v.id == videoId), isFalse);
    await capture('tagdef-reopened');
    await tap(find.byKey(const Key('kind-pack')));
    await ready(true);
    expect(state().selected, {packId});
    expect(state().tags.singleWhere((v) => v.id == packId).name, '户外');
    await until(
      () => state().matching == linkedPacks.length,
      'unchanged pack matches',
    );
    await capture('tagdef-pack-final');
    await tap(find.byKey(const Key('nav-library')));
    await until(
      () =>
          find.byType(VideoCatalogPage).evaluate().length == 1 &&
          !t
              .state<VideoCatalogPageState>(find.byType(VideoCatalogPage))
              .data
              .loading,
      'video library returned',
    );
    await capture('tagdef-library');
    final playbackAfter = await playback();
    expect(playbackAfter, playbackBefore);
    expect((await repo.api.json('GET', '/api/v1/recent'))['total'], 0);
    final packsAfter =
        (await repo.api.json(
              'GET',
              '/api/v1/packs',
              query: {'tag_ids': packId},
            ))['items']
            as List;
    expect(
      packsAfter.map((v) => v['id']).toSet(),
      linkedPacks.map((v) => v['id']).toSet(),
    );
    debugPrint(
      'VIDEO_TAG_DEFINITIONS_VERIFIED:${jsonEncode({'video_tag': videoId, 'pack_tag': packId, 'created_tag': created, 'pack_kimono_tag': packKimonoId, 'linked_videos': linkedVideos.map((v) => v['id']).toList(), 'linked_packs': linkedPacks.map((v) => v['id']).toList(), 'playback_before': playbackBefore, 'playback_after': playbackAfter})}',
    );
    debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
  });
}
