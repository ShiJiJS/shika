import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/settings/default_settings_sheet.dart';
import 'package:video_viewer/features/settings/media_root_sheet.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/preferences.dart';

import 'prototype_fidelity_test.dart' show control;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Settings forms preserve drafts, roots and the active fixed range', (
    t,
  ) async {
    final previousError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('SETTINGS_PANELS_ERROR:$details');
      previousError?.call(details);
    };
    final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8768);
    final preferences = UiPreferences(preloadAdjacent: false);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      preferences.dispose();
      FlutterError.onError = previousError;
    });
    await repo.connect(
      'http://10.0.2.2',
      8768,
      'prototype-fidelity-owned-only',
    );
    await repo.beginPreview(VideoEntryScope(), order: PlayOrder.sequential);
    Future<Map<String, dynamic>> active() =>
        repo.api.json('GET', '/api/v1/playback', query: {'create': 'false'});
    final roundBefore = await active();
    final rootsBefore = repo.snapshot.roots.map((r) => r.toJson()).toList();
    final readerBefore = await repo.api.json('GET', '/api/v1/reading-defaults');
    final orderBefore = await repo.api.json('GET', '/api/v1/playback-defaults');
    await t.pumpWidget(
      VideoViewerApp(
        repository: repo,
        preferences: preferences,
        initializeRepository: false,
      ),
    );
    Future<void> until(FutureOr<bool> Function() done, String why) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!await done()) {
        if (DateTime.now().isAfter(deadline)) fail('Settings timeout: $why');
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    Future<void> tap(Finder target) async {
      await until(() => target.evaluate().isNotEmpty, 'target $target');
      if (target.hitTestable().evaluate().isEmpty)
        await t.ensureVisible(target);
      await until(
        () => target.hitTestable().evaluate().isNotEmpty,
        'visible $target',
      );
      await t.tap(target);
      await t.pump(const Duration(milliseconds: 260));
    }

    Future<void> hideKeyboard() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await until(
        () =>
            MediaQuery.of(t.element(find.byKey(const Key('app-shell')).first))
                .viewInsets
                .bottom ==
            0,
        'system keyboard closed',
      );
    }

    Future<void> capture(String state) async {
      await t.pump(const Duration(milliseconds: 200));
      final media = MediaQuery.of(
        t.element(find.byKey(const Key('app-shell')).first),
      );
      List<double> rect(Rect r) => [r.left, r.top, r.width, r.height];
      final keys = <String, List<double>>{};
      for (final key in [
        'connection-address',
        'connection-port',
        'connection-passphrase',
        'connection-save',
        'operation-error',
        'root-name',
        'root-path',
        'root-kind',
        'root-enabled',
        'root-save',
        'defaults-save',
        'default-reader-direction',
        'default-reader-fit',
        'default-reader-gap',
        'default-mode-horizontal',
        'default-mode-vertical',
      ]) {
        final f = find.byKey(Key(key));
        if (f.evaluate().length == 1 &&
            f.evaluate().single.renderObject is RenderBox)
          keys[key] = rect(t.getRect(f));
      }
      final texts = <Map<String, dynamic>>[];
      for (final element in find.byType(Text).evaluate()) {
        final box = element.renderObject;
        if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
        final position = box.localToGlobal(Offset.zero);
        if (position.dy < 0 || position.dy >= media.size.height) continue;
        final w = element.widget as Text;
        texts.add({
          'text': w.data ?? w.textSpan?.toPlainText(),
          'rect': rect(position & box.size),
          'fontSize': w.style?.fontSize,
        });
      }
      debugPrint(
        'FIDELITY_METRICS:${jsonEncode({
          'state': state,
          'size': [media.size.width, media.size.height],
          'dpr': media.devicePixelRatio,
          'viewPadding': [media.viewPadding.left, media.viewPadding.top, media.viewPadding.right, media.viewPadding.bottom],
          'viewInsets': [media.viewInsets.left, media.viewInsets.top, media.viewInsets.right, media.viewInsets.bottom],
          'textScale': media.textScaler.scale(14) / 14,
          'keys': keys,
          'texts': texts,
          'dark': preferences.dark,
          'theme_primary': Theme.of(t.element(find.byKey(const Key('app-shell')).first)).colorScheme.primary.toARGB32(),
        })}',
      );
      await control('/checkpoint/$state', post: true);
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while ((await control('/state'))['ack'] != true) {
        if (DateTime.now().isAfter(deadline))
          fail('Missing host screenshot: $state');
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> settings() async {
      if (find.byTooltip('返回设置').evaluate().isNotEmpty)
        await tap(find.byTooltip('返回设置'));
      else
        await tap(find.byKey(const Key('nav-settings')));
      await until(
        () => find.text('服务连接').evaluate().isNotEmpty,
        'settings entry',
      );
    }

    Future<void> openDefaults(bool video) async {
      await tap(find.text(video ? '默认播放顺序' : '阅读偏好'));
      await until(
        () =>
            find.byType(DefaultSettingsSheet).evaluate().isNotEmpty &&
            find.text('保存默认设置').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'current service defaults',
      );
    }

    Future<void> direction(String label) async {
      if (find
          .byKey(const Key('default-reader-direction'))
          .evaluate()
          .isNotEmpty)
        await tap(find.byKey(const Key('default-reader-direction')));
      await tap(find.text(label).last);
    }

    Future<void> fit(String label) async {
      if (find.byKey(const Key('default-reader-fit')).evaluate().isNotEmpty)
        await tap(find.byKey(const Key('default-reader-fit')));
      await tap(find.text(label).last);
    }

    Future<void> gap() => tap(
      find.byKey(const Key('default-reader-gap')).evaluate().isNotEmpty
          ? find.byKey(const Key('default-reader-gap'))
          : find.text('图片间距'),
    );
    Future<void> saveDefaults() async {
      await tap(find.text('保存默认设置'));
      await until(
        () => find.byType(DefaultSettingsSheet).evaluate().isEmpty,
        'defaults saved',
      );
    }

    Future<void> rootKind(MediaKind kind) async {
      if (find.byKey(const Key('root-kind')).evaluate().isNotEmpty)
        await tap(find.byKey(const Key('root-kind')));
      await tap(find.byKey(Key('root-kind-${kind.name}')).last);
    }

    await settings();
    await capture('settings-home');
    await tap(find.text('服务连接'));
    await capture('settings-connection');
    final port = find.byKey(const Key('connection-port'));
    await tap(port);
    await t.enterText(port, '0');
    await until(
      () => MediaQuery.of(t.element(port)).viewInsets.bottom > 0,
      'real connection IME',
    );
    await capture('settings-connection-keyboard');
    await hideKeyboard();
    await tap(find.byKey(const Key('connection-save')));
    await until(
      () => find.byKey(const Key('operation-error')).evaluate().isNotEmpty,
      'invalid port error',
    );
    expect(t.widget<TextField>(port).controller!.text, '0');
    expect(repo.snapshot.connected, isTrue);
    await capture('settings-connection-invalid');
    await tap(find.byTooltip('关闭错误提示'));
    await settings();
    await tap(find.text('媒体目录'));
    await capture('settings-roots');
    await tap(find.text('添加目录'));
    await capture('settings-root-add');
    await tap(find.byKey(const Key('root-name')));
    await t.enterText(find.byKey(const Key('root-name')), '保留目录草稿');
    await until(
      () =>
          MediaQuery.of(t.element(find.byKey(const Key('root-name'))))
              .viewInsets
              .bottom >
          0,
      'real root IME',
    );
    await capture('settings-root-keyboard');
    await hideKeyboard();
    await tap(find.byKey(const Key('root-save')));
    expect(find.text('请填写名称和挂载目录'), findsOneWidget);
    expect(
      t.widget<TextField>(find.byKey(const Key('root-name'))).controller!.text,
      '保留目录草稿',
    );
    await capture('settings-root-invalid');
    await tap(find.byTooltip('关闭面板'));
    final videoRoot = repo.snapshot.roots.firstWhere(
      (r) => r.kind == MediaKind.video,
    );
    await tap(find.byTooltip('编辑目录 ${videoRoot.name}'));
    await capture('settings-root-edit');
    await t.enterText(find.byKey(const Key('root-name')), '保留编辑草稿');
    await rootKind(MediaKind.pack);
    await hideKeyboard();
    await tap(find.byKey(const Key('root-save')));
    await until(
      () => find.textContaining('已有内容的目录不能直接更改媒体类型').evaluate().isNotEmpty,
      'actual root kind conflict',
    );
    expect(
      t.widget<TextField>(find.byKey(const Key('root-name'))).controller!.text,
      '保留编辑草稿',
    );
    await capture('settings-root-conflict');
    await tap(find.byTooltip('关闭面板'));
    await settings();
    await openDefaults(true);
    await capture('settings-playback');
    await tap(
      find.text(orderBefore['order'] == 'sequential' ? '随机播放' : '顺序播放'),
    );
    await capture('settings-playback-draft');
    await tap(find.byTooltip('关闭面板'));
    expect(
      await repo.api.json('GET', '/api/v1/playback-defaults'),
      orderBefore,
    );
    await openDefaults(false);
    await capture('settings-reader');
    await tap(find.text('纵向拼接'));
    await direction('从右向左');
    await gap();
    await fit('铺满宽度');
    await capture('settings-reader-draft');
    await saveDefaults();
    final saved = await repo.api.json('GET', '/api/v1/reading-defaults');
    expect(saved['mode'], 'vertical');
    expect(saved['direction'], 'rtl');
    expect(saved['gap'], true);
    expect(saved['fit'], 'width');
    await openDefaults(false);
    await capture('settings-reader-saved');
    await tap(find.text('横向翻页'));
    await direction('从左向右');
    await gap();
    await fit('完整显示');
    await saveDefaults();
    final restored = await repo.api.json('GET', '/api/v1/reading-defaults');
    for (final field in ['mode', 'direction', 'gap', 'fit'])
      expect(restored[field], readerBefore[field]);
    await openDefaults(false);
    await capture('settings-reader-restored');
    await tap(find.byTooltip('关闭面板'));
    await tap(find.byKey(const Key('dark-mode-setting')));
    await until(
      () =>
          preferences.dark &&
          Theme.of(t.element(find.byKey(const Key('app-shell')).first))
                  .colorScheme
                  .primary ==
              const Color(0xffb1c5a0),
      'dark theme rendered',
    );
    await capture('settings-dark');
    await tap(find.text('媒体目录'));
    await capture('settings-dark-roots');
    await settings();
    await openDefaults(false);
    await capture('settings-dark-reader');
    await tap(find.byTooltip('关闭面板'));
    await tap(find.byKey(const Key('dark-mode-setting')));
    await until(
      () =>
          !preferences.dark &&
          Theme.of(t.element(find.byKey(const Key('app-shell')).first))
                  .colorScheme
                  .primary ==
              Paper.olive,
      'light theme restored',
    );
    await tap(find.byKey(const Key('nav-library')));
    await capture('settings-return');
    final after = await active();
    expect(after, roundBefore);
    expect(repo.snapshot.roots.map((r) => r.toJson()).toList(), rootsBefore);
    debugPrint(
      'SETTINGS_PANELS_VERIFIED:${jsonEncode({'round_before': roundBefore, 'round_after': after, 'roots_before': rootsBefore, 'roots_after': repo.snapshot.roots.map((r) => r.toJson()).toList(), 'reader_before': readerBefore, 'reader_saved': saved, 'reader_restored': restored, 'order_before': orderBefore, 'order_after': await repo.api.json('GET', '/api/v1/playback-defaults')})}',
    );
    debugPrint('PROTOTYPE_FIDELITY_VERIFIED');
  });
}
