import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:shika/main.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/models.dart';
import 'package:shika/features/connection/connection_flow.dart';
import 'package:shika/ui/home.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/ui/preferences.dart';

import 'connection_widget_test.dart'
    show CredentialLibrary, ReconnectingLibrary;
import 'player_lifecycle_test.dart' show ReadyVideo, frames;

class BoundaryLibrary extends CredentialLibrary {
  Future<void> Function()? startup;
  Completer<bool>? check;
  int cancellations = 0;
  @override
  Future<void> initialize() => startup?.call() ?? super.initialize();
  @override
  Future<bool> connectionNeedsSetup(String address, int port) =>
      check?.future ?? super.connectionNeedsSetup(address, port);
  @override
  void cancelConnection() => cancellations++;
}

class EmptyLibrary extends BoundaryLibrary {
  EmptyLibrary(this.withRoots);
  final bool withRoots;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    ...super.capabilities.values,
    'typed_roots',
    'media_catalog_counts',
  ]);
  @override
  LibrarySnapshot get snapshot =>
      super.snapshot.copy(roots: withRoots ? super.snapshot.roots : []);
}

void main() {
  void locked() {
    expect(find.byType(LibraryHome), findsNothing);
    expect(find.byTooltip('更多'), findsNothing);
    expect(find.byKey(const Key('app-navigation')), findsNothing);
    expect(find.byKey(const Key('workspace-navigation')), findsNothing);
  }

  testWidgets('first welcome persists once and never mounts a media shell', (
    t,
  ) async {
    final preferences = UiPreferences();
    final repo = BoundaryLibrary();
    await repo.initialize();
    repo.savedEndpoint('', 8760);
    addTearDown(() {
      repo.dispose();
      preferences.dispose();
    });
    await t.pumpWidget(ShikaApp(repository: repo, preferences: preferences));
    await t.pumpAndSettle();
    expect(find.text('连接我的媒体库'), findsOneWidget);
    locked();
    await t.tap(find.text('连接我的媒体库'));
    await t.pumpAndSettle();
    expect(preferences.onboardingComplete, isTrue);
    expect(find.byKey(const Key('connection-address')), findsOneWidget);
    locked();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('连接我的媒体库'), findsOneWidget);
    locked();
  });

  for (final withRoots in [false, true]) {
    testWidgets(
      'empty library offers the appropriate directory action; configured=$withRoots',
      (t) async {
        final repo = EmptyLibrary(withRoots);
        await repo.initialize();
        repo.catalogCounts.value = const MediaCatalogCounts(0, 0);
        addTearDown(repo.dispose);
        await t.pumpWidget(ShikaApp(repository: repo));
        await t.pumpAndSettle();
        expect(find.text(withRoots ? '管理媒体目录' : '添加媒体目录'), findsOneWidget);
        await t.tap(find.byKey(const Key('first-media-root')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('first-media-root')), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'back during server check rejects its late result and preserves address',
    (t) async {
      final repo = BoundaryLibrary();
      await repo.initialize();
      repo.connection(false);
      repo.check = Completer<bool>();
      addTearDown(repo.dispose);
      await t.pumpWidget(ShikaApp(repository: repo));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('connection-address')), 'my-nas');
      await t.tap(find.byKey(const Key('connection-save')));
      await t.pump();
      await t.tap(find.byKey(const Key('connection-back')));
      await t.pumpAndSettle();
      repo.check!.complete(true);
      await t.pumpAndSettle();
      expect(find.text('设置个人口令'), findsNothing);
      expect(repo.cancellations, greaterThan(0));
      locked();
      await t.tap(find.text('连接我的媒体库'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('connection-address')))
            .controller!
            .text,
        'my-nas',
      );
    },
  );

  testWidgets(
    'saved session is verified before library mounts; offline retry retains endpoint',
    (t) async {
      final repo = BoundaryLibrary();
      await repo.initialize();
      repo.connection(false);
      repo.savedEndpoint('http://saved-nas', 9000);
      var attempts = 0;
      final wait = Completer<void>();
      repo.startup = () async {
        attempts++;
        await wait.future;
        throw const ApiFailure('连接超时', code: 'network_error');
      };
      addTearDown(repo.dispose);
      await t.pumpWidget(
        ShikaApp(repository: repo, initializeRepository: true),
      );
      await t.pump();
      locked();
      expect(find.text('正在验证登录状态'), findsOneWidget);
      wait.complete();
      await t.pumpAndSettle();
      expect(find.text('暂时无法连接'), findsOneWidget);
      expect(repo.snapshot.address, 'http://saved-nas');
      locked();
      repo.startup = () async {
        attempts++;
        repo.connection(true);
      };
      await t.tap(find.byKey(const Key('connection-retry')));
      await t.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(LibraryHome), findsOneWidget);
      expect(find.text('连接我的媒体库'), findsNothing);
    },
  );

  testWidgets(
    'authentication expiry closes root sheets and back cannot reopen business pages',
    (t) async {
      final repo = ReconnectingLibrary();
      await repo.initialize();
      addTearDown(repo.dispose);
      await t.pumpWidget(ShikaApp(repository: repo));
      await t.pumpAndSettle();
      final context = t.element(find.byType(LibraryHome));
      unawaited(
        paperSheet<void>(
          context,
          const SheetFrame(title: '私有管理面板', children: [Text('已登录内容')]),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('私有管理面板'), findsOneWidget);
      repo.connection(false);
      await t.pumpAndSettle();
      expect(find.text('私有管理面板'), findsNothing);
      locked();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      locked();
      repo.connection(true);
      await t.pumpAndSettle();
      expect(find.byType(LibraryHome), findsOneWidget);
      expect(find.byType(ConnectionFlow), findsNothing);
      expect(find.text('私有管理面板'), findsNothing);
    },
  );

  testWidgets(
    'expiry disposes the playing video and reconnect never resumes it',
    (t) async {
      final original = VideoPlayerPlatform.instance;
      final platform = ReadyVideo();
      VideoPlayerPlatform.instance = platform;
      final repo = ReconnectingLibrary();
      await repo.initialize();
      addTearDown(() {
        repo.dispose();
        VideoPlayerPlatform.instance = original;
      });
      await t.pumpWidget(ShikaApp(repository: repo));
      await frames(t);
      await t.tap(find.byKey(const Key('video-quick-cleanup')));
      await frames(t);
      expect(find.byKey(const Key('video-preview-route')), findsOneWidget);
      expect(platform.events, isNotEmpty);
      repo.connection(false);
      await frames(t);
      locked();
      expect(platform.events, isEmpty);
      final created = platform.next;
      await t.binding.handlePopRoute();
      await frames(t);
      repo.connection(true);
      await frames(t);
      expect(find.byType(LibraryHome), findsOneWidget);
      expect(find.byKey(const Key('video-preview-route')), findsNothing);
      expect(platform.next, created);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await frames(t);
    },
  );

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(320, 740), 2.0),
    (const Size(844, 390), 2.0),
  ]) {
    testWidgets('welcome and setup actions remain reachable $size/$scale', (
      t,
    ) async {
      final repo = BoundaryLibrary();
      await repo.initialize();
      repo.savedEndpoint('', 8760);
      addTearDown(repo.dispose);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(ShikaApp(repository: repo));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('连接我的媒体库'));
      await t.tap(find.text('连接我的媒体库'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('connection-address')), 'nas');
      await t.ensureVisible(find.byKey(const Key('connection-save')));
      await t.tap(find.byKey(const Key('connection-save')));
      await t.pumpAndSettle();
      expect(find.text('设置个人口令'), findsOneWidget);
      locked();
      await t.showKeyboard(
        find.byKey(const Key('connection-confirm-passphrase')),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('connection-save')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('connection-save')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }
}
