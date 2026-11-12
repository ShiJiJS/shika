import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/main.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/ui/home.dart';
import 'package:shika/ui/preferences.dart';

/// Run against an isolated, initially unclaimed service, never a personal NAS.
/// The test claims it with a test-only passphrase and leaves all media untouched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native first-use setup, logout, wrong password, saved login and expiry',
    (t) async {
      const address = String.fromEnvironment(
        'ONBOARDING_TEST_ADDRESS',
        defaultValue: 'http://10.0.2.2',
      );
      const port = int.fromEnvironment(
        'ONBOARDING_TEST_PORT',
        defaultValue: 8781,
      );
      const secret = 'onboarding-test-secret';
      final endpoint = Uri.parse(address).replace(port: port);
      expect(
        ['10.0.2.2', '127.0.0.1', 'localhost'],
        contains(endpoint.host),
        reason: 'This test must use an isolated local service.',
      );
      final preflight = ServerApi(endpoint);
      try {
        expect(
          (await preflight.json('GET', '/api/v1/auth/status'))['initialized'],
          false,
          reason: 'Use a fresh disposable data directory for each run.',
        );
      } finally {
        preflight.close();
      }
      final store = MemoryCredentialStore(),
          preferences = UiPreferences(preloadAdjacent: false);
      var repo = ServerLibraryRepository(store);
      Widget host() => ShikaApp(
        repository: repo,
        preferences: preferences,
        initializeRepository: true,
      );
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        preferences.dispose();
      });
      Future<void> until(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native onboarding state timed out');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 100));
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pump(const Duration(milliseconds: 100));
      }

      Future<void> enter(Finder f, String value) async {
        // Disabled fields close their platform input connection. A real tap
        // restores focus; tester.enterText alone can retain its old client.
        await tap(f);
        await t.enterText(f, value);
        expect(t.widget<TextField>(f).controller!.text, value);
      }

      Future<void> shot(String name) async {
        // Capture through adb, outside Flutter's software-rendered test surface.
        // Keeping image readback off the app also exercises its normal renderer.
        debugPrint('ONBOARDING_SHOT:$name');
        await t.pump(const Duration(seconds: 1));
      }

      await configureApplicationWindow();
      await t.pumpWidget(host());
      await until(() => find.text('连接我的媒体库').evaluate().isNotEmpty);
      expect(find.byType(LibraryHome), findsNothing);
      expect(find.byTooltip('更多'), findsNothing);
      await shot('onboarding-welcome');
      await tap(find.text('连接我的媒体库'));
      await enter(find.byKey(const Key('connection-address')), address);
      await enter(find.byKey(const Key('connection-port')), '8789');
      await tap(find.byKey(const Key('connection-save')));
      await until(
        () => find.byKey(const Key('connection-error')).evaluate().isNotEmpty,
      );
      expect(find.byType(LibraryHome), findsNothing);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('connection-address')))
            .controller!
            .text,
        address,
      );
      await shot('onboarding-connect-error');
      await until(
        () =>
            t
                .widget<FilledButton>(find.byKey(const Key('connection-save')))
                .onPressed !=
            null,
      );
      await enter(find.byKey(const Key('connection-port')), '$port');
      await tap(find.byKey(const Key('connection-save')));
      await until(() => find.text('设置个人口令').evaluate().isNotEmpty);
      await shot('onboarding-setup');
      await enter(find.byKey(const Key('connection-passphrase')), secret);
      await enter(
        find.byKey(const Key('connection-confirm-passphrase')),
        'different-secret',
      );
      await tap(find.byKey(const Key('connection-save')));
      expect(find.text('两次输入的口令不一致'), findsOneWidget);
      expect(store.value, isNull);
      await enter(
        find.byKey(const Key('connection-confirm-passphrase')),
        secret,
      );
      await tap(find.byKey(const Key('connection-save')));
      await until(
        () =>
            repo.snapshot.connected &&
            find.byType(LibraryHome).evaluate().isNotEmpty,
      );
      expect(store.value, isNotNull);
      expect(store.value!.encode(), isNot(contains(secret)));
      await until(
        () => find.byKey(const Key('first-media-root')).evaluate().isNotEmpty,
      );
      await shot('onboarding-first-library');
      await tap(find.byKey(const Key('nav-settings')));
      await tap(find.text('退出登录'));
      await until(() => find.text('连接已有媒体库').evaluate().isNotEmpty);
      expect(store.value, isNull);
      expect(find.byType(LibraryHome), findsNothing);
      await shot('onboarding-existing-login');
      await enter(
        find.byKey(const Key('connection-passphrase')),
        'wrong-password',
      );
      await tap(find.byKey(const Key('connection-save')));
      await until(() => find.text('口令不正确').evaluate().isNotEmpty);
      await enter(find.byKey(const Key('connection-passphrase')), secret);
      await tap(find.byKey(const Key('connection-save')));
      await until(
        () =>
            repo.snapshot.connected &&
            find.byType(LibraryHome).evaluate().isNotEmpty,
      );

      await t.pumpWidget(const SizedBox());
      await t.pump();
      repo.dispose();
      repo = ServerLibraryRepository(store);
      await t.pumpWidget(host());
      expect(find.byType(LibraryHome), findsNothing);
      await until(
        () =>
            repo.snapshot.connected &&
            find.byType(LibraryHome).evaluate().isNotEmpty,
      );
      expect(find.text('连接我的媒体库'), findsNothing);
      final api = ServerApi(store.value!.endpoint, token: store.value!.token);
      await api.json('DELETE', '/api/v1/auth/session');
      api.close();
      try {
        await repo.refresh();
      } catch (_) {
        /* 401 closes the same auth boundary */
      }
      await until(
        () =>
            !repo.snapshot.connected &&
            find.text('连接已有媒体库').evaluate().isNotEmpty,
      );
      expect(find.byType(LibraryHome), findsNothing);
      expect(find.byTooltip('更多'), findsNothing);
      await shot('onboarding-login-expired');
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byType(LibraryHome), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
