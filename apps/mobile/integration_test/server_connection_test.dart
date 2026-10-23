import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/sheets.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('E2E_RESUME')) {
    testWidgets(
      'I1 encrypted connection and deep folder survive Android process restart',
      (t) async {
        final store = SecureCredentialStore(
          key: 'video_viewer.e2e.connection.v1',
        );
        final before =
            (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
        final logins = before
            .where((r) => r['path'] == '/api/v1/auth/login')
            .length;
        final repo = ServerLibraryRepository(store, port: 9999);
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(milliseconds: 200));
          repo.dispose();
        });
        await t.pumpWidget(
          VideoViewerApp(repository: repo, initializeRepository: true),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!repo.snapshot.connected ||
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Saved Android session did not reopen');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(repo.snapshot.port, 8761);
        expect(repo.snapshot.query.folder, '/media/shorts/自然/花卉');
        expect(repo.playbackTotal, 25);
        expect(find.text('连接你的视频库'), findsNothing);
        final after =
            (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
        expect(
          after.where((r) => r['path'] == '/api/v1/auth/login').length,
          logins,
          reason: 'restored token used without resending a passphrase',
        );
        await store.clear();
      },
    );
    return;
  }
  testWidgets('I1 real service connection, pages, folders, restart and outage', (
    t,
  ) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await fixture('/__fixture/actions/reset-login-limit');
    final store = SecureCredentialStore(key: 'video_viewer.e2e.connection.v1');
    await store.clear();
    // This dedicated namespace never changes the normal app's connection.
    await store.storage.delete(key: '${store.key}.endpoint');
    var repo = ServerLibraryRepository(store, port: 8761);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 200));
      repo.dispose();
    });

    Future<void> until(
      bool Function() condition,
      String reason, {
      int seconds = 35,
    }) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out: $reason');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pump(const Duration(milliseconds: 100));
    }

    Future<void> idle() => until(
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      'operation finished',
    );
    Future<void> tap(Finder finder) async {
      if (finder.hitTestable().evaluate().isEmpty) {
        await t.ensureVisible(finder);
      }
      await t.tap(finder);
      await t.pump(const Duration(milliseconds: 300));
      await idle();
    }

    Future<void> textTap(String text) => tap(find.text(text).last);
    Future<void> nav(String name) async {
      if (find.byKey(Key('nav-$name')).evaluate().isEmpty) {
        await tap(find.byTooltip('返回设置'));
      }
      await tap(find.byKey(Key('nav-$name')));
    }

    Future<void> count(int expected) => until(
      () =>
          find.text('$expected 个视频').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
      '$expected videos',
    );
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    Future<void> start() async {
      await t.pumpWidget(
        VideoViewerApp(repository: repo, initializeRepository: true),
      );
      await t.pump(const Duration(milliseconds: 500));
      await idle();
    }

    Future<void> folder(List<String> names, {bool all = false}) async {
      await tap(find.byTooltip('选择文件夹'));
      await textTap('媒体目录');
      for (final name in names) {
        await until(() => find.text(name).evaluate().isNotEmpty, name);
        await textTap(name);
      }
      await until(
        () =>
            t
                .widget<FilledButton>(
                  find.descendant(
                    of: find.byType(FolderPicker),
                    matching: find.byType(FilledButton),
                  ),
                )
                .onPressed !=
            null,
        'folder loaded',
      );
      await textTap(all ? '使用全部目录' : '使用此目录');
    }

    Future<void> syncRoots() async {
      await textTap('同步外部变更');
      await until(
        () => !repo.libraryPreparation.value.scanning,
        'external change scan finished',
      );
    }

    Future<void> refreshRoots() async {
      await nav('settings');
      await textTap('媒体目录');
      await syncRoots();
    }

    await start();
    expect(find.text('连接你的视频库'), findsOneWidget);
    await t.enterText(field('个人口令'), 'wrong-fixture-password');
    await t.pump(const Duration(milliseconds: 300));
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await textTap('连接');
    expect(find.text('口令不正确'), findsOneWidget);
    expect(t.widget<TextField>(field('个人口令')).obscureText, isTrue);
    expect(
      t.widget<TextField>(field('个人口令')).controller!.text,
      'wrong-fixture-password',
    );
    expect(t.widget<TextField>(field('端口')).controller!.text, '8761');
    // The disabled field closed its IME connection during the first request.
    // Refocus through its public UI before injecting the replacement text.
    await tap(field('个人口令'));
    await t.enterText(field('个人口令'), fixturePassword);
    await t.pump(const Duration(milliseconds: 300));
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await t.pump(const Duration(milliseconds: 500));
    expect(
      t.widget<TextField>(field('个人口令')).controller!.text == fixturePassword,
      isTrue,
      reason: 'correct fixture input survives keyboard dismissal',
    );
    await textTap('连接');
    expect(
      repo.snapshot.connected,
      isTrue,
      reason: find.byKey(const Key('operation-error')).evaluate().isEmpty
          ? 'No visible error'
          : t.widget<Text>(find.byKey(const Key('operation-error'))).data,
    );
    expect(repo.snapshot.roots, hasLength(2));
    // Initial connection gets a small playback window, not the entire catalog.
    expect(repo.snapshot.videos.length, lessThan(27));
    await nav('library');
    await count(27);
    await until(
      () => t
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
      'authenticated thumbnails decoded on Android',
    );
    final grid = find.byKey(const Key('video-grid'));
    int loadedCards() => t
        .widget<SliverGrid>(
          find.descendant(of: grid, matching: find.byType(SliverGrid)),
        )
        .delegate
        .estimatedChildCount!;
    expect(loadedCards(), 24);
    await fixture('/__fixture/checkpoint/library');
    await t.pump(const Duration(seconds: 2));
    await t.drag(grid, const Offset(0, -6000));
    await until(
      () => loadedCards() == 27,
      'second page appended automatically',
    );
    await folder(['端到端短视频', '自然', '花卉']);
    await count(25);
    expect(repo.snapshot.query.folder, '/media/shorts/自然/花卉');
    await folder(['端到端短视频', '空目录']);
    await count(0);
    expect(find.text('没有符合条件的视频'), findsOneWidget);
    expect(repo.playbackTotal, 0);
    await folder([], all: true);
    await count(27);
    await t.enterText(find.byKey(const Key('video-search')), '片');
    await t.pump(const Duration(milliseconds: 100));
    await t.enterText(find.byKey(const Key('video-search')), '片段02');
    await count(1);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('1 个视频'), findsOneWidget);
    await t.enterText(find.byKey(const Key('video-search')), '');
    await t.pump(const Duration(milliseconds: 300));
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await count(27);

    await fixture('/__fixture/actions/add');
    await refreshRoots();
    await nav('library');
    await count(28);
    expect(repo.playbackTotal, 27, reason: 'new media joins the next round');
    await folder(['端到端短视频', '自然', '花卉']);
    await count(25);
    final serverId = (await store.read())!.serverId;
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 300));
    repo.dispose();
    repo = ServerLibraryRepository(store, port: 9999);
    await start();
    expect(
      repo.snapshot.connected,
      isTrue,
      reason: 'native encrypted session restored',
    );
    expect(repo.snapshot.port, 8761);
    expect(repo.snapshot.query.folder, '/media/shorts/自然/花卉');
    expect(find.text('连接你的视频库'), findsNothing);
    await nav('library');
    await count(25);

    await fixture('/__fixture/actions/disconnect');
    await refreshRoots();
    expect(repo.snapshot.roots.where((r) => !r.available), hasLength(1));
    expect(
      repo.missingCount,
      0,
      reason: 'a detached root is not mass missing media',
    );
    expect(find.textContaining('目录暂不可用'), findsOneWidget);
    await fixture('/__fixture/checkpoint/roots');
    await t.pump(const Duration(seconds: 2));
    await fixture('/__fixture/actions/reconnect');
    await syncRoots();
    expect(repo.snapshot.roots.every((r) => r.available), isTrue);

    final trace =
        (await fixture('/__fixture/trace', method: 'GET'))['items'] as List;
    // The host runner now stops the actual dedicated Docker service.
    await fixture('/__fixture/checkpoint/outage');
    var down = false;
    for (var i = 0; i < 80 && !down; i++) {
      try {
        await fixture('/health', method: 'GET');
      } on IOException {
        down = true;
      }
      if (!down) await t.pump(const Duration(milliseconds: 100));
    }
    expect(
      down,
      isTrue,
      reason: 'host runner must physically stop the fixture',
    );
    await syncRoots();
    expect(find.byKey(const Key('operation-error')), findsOneWidget);
    expect(repo.snapshot.connected, isTrue);
    expect((await store.read())!.serverId, serverId);
    var up = false;
    for (var i = 0; i < 160 && !up; i++) {
      try {
        await fixture('/health', method: 'GET');
        up = true;
      } on IOException {
        await t.pump(const Duration(milliseconds: 150));
      }
    }
    expect(up, isTrue);
    await syncRoots();
    expect(find.byKey(const Key('operation-error')), findsNothing);
    expect((await store.read())!.serverId, serverId);
    await nav('library');
    await count(25);
    await folder([], all: true);
    await count(28);
    await fixture('/__fixture/checkpoint/recovered');
    await t.pump(const Duration(seconds: 2));

    trace.addAll(
      (await fixture('/__fixture/trace', method: 'GET'))['items'] as List,
    );
    expect(
      trace.any(
        (r) => r['path'] == '/api/v1/videos' && r['query']['offset'] == '24',
      ),
      isTrue,
    );
    expect(
      trace.any(
        (r) =>
            (r['path'] as String).endsWith('/thumbnail') &&
            r['authenticated'] == true,
      ),
      isTrue,
    );
    // Expiry is different from an outage: revoke the exact app session publicly.
    final saved = (await store.read())!;
    final client = HttpClient();
    try {
      final thumbnail = trace.firstWhere(
        (r) => (r['path'] as String).endsWith('/thumbnail'),
      )['path'];
      final anonymous = await client.getUrl(
        Uri.parse('$fixtureBase$thumbnail'),
      );
      final rejected = await anonymous.close();
      expect(
        rejected.statusCode,
        401,
        reason: 'thumbnail requires authentication',
      );
      await rejected.drain<void>();
      final request = await client.deleteUrl(
        Uri.parse('$fixtureBase/api/v1/auth/session'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${saved.token}',
      );
      final response = await request.close();
      expect(response.statusCode, 204);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    // Opening roots already performs an authenticated read and detects expiry.
    await nav('settings');
    await textTap('媒体目录');
    await until(() => !repo.snapshot.connected, 'revoked session detected');
    expect(find.text('连接你的视频库'), findsOneWidget);
    expect(await store.read(), isNull);
    expect(
      t.widget<TextField>(field('服务地址')).controller!.text,
      contains('10.0.2.2'),
    );
    expect(t.widget<TextField>(field('端口')).controller!.text, '8761');
    expect(t.widget<TextField>(field('个人口令')).controller!.text, isEmpty);
    await tap(field('个人口令'));
    await t.enterText(field('个人口令'), fixturePassword);
    await t.pump(const Duration(milliseconds: 300));
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await t.pump(const Duration(milliseconds: 300));
    await textTap('连接');
    expect(repo.snapshot.connected, isTrue);
    await nav('library');
    await count(28);
    await folder(['端到端短视频', '自然', '花卉']);
    await count(25);
    await fixture('/__fixture/checkpoint/done');
  });
}
