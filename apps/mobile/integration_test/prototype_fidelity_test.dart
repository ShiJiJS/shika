import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/library/tag_catalog_page.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

Future<Map<String, dynamic>> control(String path, {bool post = false}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      post ? 'POST' : 'GET',
      Uri.parse('http://10.0.2.2:8768/__fidelity$path'),
    );
    request.headers.set('X-Fixture-Key', 'prototype-fidelity-owned-control');
    final response = await request.close();
    expect(response.statusCode, 200);
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('full native workspace with frozen public reference media', (
    t,
  ) async {
    final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
    final preferences = UiPreferences();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      preferences.dispose();
    });
    await repo.connect(
      'http://10.0.2.2',
      8768,
      'prototype-fidelity-owned-only',
    );
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: preferences,
        initializeRepository: false,
      ),
    );
    Future<void> until(bool Function() condition, String description) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail(description);
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> tap(Finder target) async {
      await until(() => target.hitTestable().evaluate().length == 1, '$target');
      await t.tap(target.hitTestable());
      await t.pump(const Duration(milliseconds: 350));
    }

    Future<void> images(int count) async {
      await until(
        () =>
            find.byType(RawImage).evaluate().where((element) {
              final render = element.renderObject;
              return render is RenderImage && render.image != null;
            }).length >=
            count,
        'Actual decoded catalog images: $count',
      );
    }

    Future<void> selectOutdoor() async {
      final page = find.byType(TagCatalogPage);
      await until(
        () =>
            page.evaluate().length == 1 &&
            !t.state<TagCatalogPageState>(page).loading &&
            t.state<TagCatalogPageState>(page).tags.isNotEmpty,
        'loaded tag catalog',
      );
      final target = find.text('户外');
      if (target.hitTestable().evaluate().isEmpty) {
        await t.scrollUntilVisible(
          target,
          160,
          scrollable: find
              .descendant(of: page, matching: find.byType(Scrollable))
              .first,
        );
      }
      await tap(target);
    }

    Future<void> capture(String name) async {
      await t.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final shell = t.element(find.byKey(const Key('app-shell')));
      final media = MediaQuery.of(shell);
      List<double> rectangle(Rect r) => [r.left, r.top, r.width, r.height];
      final texts = <Map<String, dynamic>>[];
      for (final element in find.byType(Text).evaluate()) {
        final widget = element.widget as Text;
        final box = element.renderObject;
        if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
        final position = box.localToGlobal(Offset.zero);
        if (position.dy < 0 || position.dy >= media.size.height) continue;
        texts.add({
          'text': widget.data ?? widget.textSpan?.toPlainText(),
          'rect': rectangle(position & box.size),
          'fontSize': widget.style?.fontSize,
          'fontFamily': widget.style?.fontFamily,
        });
      }
      final keys = <String, List<double>>{};
      for (final name in [
        'app-shell',
        'app-navigation',
        'video-search',
        'pack-search',
        'library-count',
      ]) {
        final finder = find.byKey(Key(name));
        if (finder.evaluate().length == 1) {
          keys[name] = rectangle(t.getRect(finder));
        }
      }
      debugPrint(
        'FIDELITY_METRICS:${jsonEncode({
          'state': name,
          'size': [media.size.width, media.size.height],
          'dpr': media.devicePixelRatio,
          'padding': [media.padding.left, media.padding.top, media.padding.right, media.padding.bottom],
          'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
          'textScale': media.textScaler.scale(14) / 14,
          'keys': keys,
          'texts': texts,
        })}',
      );
      await control('/checkpoint/$name', post: true);
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while ((await control('/state'))['ack'] != true) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Host screenshot missing: $name');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await until(
      () => find.text('2 个视频').evaluate().isNotEmpty,
      'two real scanned videos',
    );
    await images(2);
    await capture('home');
    await tap(find.byKey(const Key('kind-pack')));
    await until(
      () => find.text('4 个图包').evaluate().isNotEmpty,
      'four real scanned packs',
    );
    final viewport = t.view.physicalSize / t.view.devicePixelRatio;
    await images(viewport.width > viewport.height ? 2 : 4);
    await capture('packs');
    await tap(find.byKey(const Key('nav-tags')));
    await selectOutdoor();
    await until(
      () => find.text('匹配 2 个视频').evaluate().isNotEmpty,
      'video tag intersection',
    );
    await capture('video-tags');
    await tap(find.byKey(const Key('kind-pack')));
    await selectOutdoor();
    await until(
      () => find.text('匹配 2 个图包').evaluate().isNotEmpty,
      'pack tag intersection',
    );
    await capture('pack-tags');
    await tap(find.byKey(const Key('nav-settings')));
    await capture('settings');
    Future<void> bottom(String name) async {
      await t.scrollUntilVisible(
        find.text('阅读偏好'),
        160,
        scrollable: find.byType(Scrollable).hitTestable().last,
      );
      await t.pump(const Duration(milliseconds: 350));
      await capture(name);
    }

    await bottom('settings-bottom');
    t
        .state<ScrollableState>(find.byType(Scrollable).hitTestable().last)
        .position
        .jumpTo(0);
    await preferences.setDark(true);
    await until(
      () =>
          Theme.of(t.element(find.byKey(const Key('app-shell'))))
              .scaffoldBackgroundColor ==
          Paper.darkTheme.scaffoldBackgroundColor,
      'actual animated dark theme has settled',
    );
    await capture('dark');
    await bottom('dark-bottom');
    expect(t.takeException(), isNull);
    debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
  });
}
