import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/main.dart';
import 'package:shika/features/settings/change_passphrase_sheet.dart';
import 'package:shika/ui/paper.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/server_repository.dart';

class ReconnectingLibrary extends DemoLibraryRepository {
  ReconnectingLibrary() : super(MemoryStateStore(), latency: Duration.zero);
  LibrarySnapshot? disconnected;
  @override
  LibrarySnapshot get snapshot => disconnected ?? super.snapshot;
  void connection(bool connected) {
    disconnected = connected ? null : super.snapshot.copy(connected: false);
    notifyListeners();
  }

  void savedEndpoint(String address, int port) {
    disconnected = snapshot.copy(
      address: address,
      port: port,
      connected: false,
    );
    notifyListeners();
  }
}

class CredentialLibrary extends ReconnectingLibrary {
  int setups = 0, changes = 0;
  @override
  Future<bool> connectionNeedsSetup(String address, int port) async => true;
  @override
  Future<void> setupConnection(
    String address,
    int port,
    String passphrase,
  ) async {
    setups++;
    connection(true);
  }

  @override
  Future<void> changePassphrase(String current, String replacement) async {
    changes++;
    if (current != 'old-secret') throw const LibraryFailure('当前口令不正确');
  }
}

void main() {
  testWidgets(
    'first connection reveals setup and rejects mismatched confirmation',
    (tester) async {
      final repo = CredentialLibrary();
      await repo.initialize();
      repo.connection(false);
      await tester.pumpWidget(ShikaApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('connection-address')),
        'my-nas',
      );
      await tester.tap(find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();
      expect(find.text('设置个人口令'), findsOneWidget);
      expect(repo.setups, 0);
      await tester.enterText(
        find.byKey(const Key('connection-passphrase')),
        'new-secret',
      );
      await tester.enterText(
        find.byKey(const Key('connection-confirm-passphrase')),
        'different',
      );
      await tester.ensureVisible(find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();
      expect(find.text('两次输入的口令不一致'), findsOneWidget);
      expect(repo.setups, 0);
      await tester.enterText(
        find.byKey(const Key('connection-confirm-passphrase')),
        'new-secret',
      );
      await tester.ensureVisible(find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();
      expect(repo.setups, 1);
      expect(find.text('设置个人口令'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets(
    'change form validates confirmation and retains a rejected draft',
    (tester) async {
      final repo = CredentialLibrary();
      await repo.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(body: ChangePassphraseSheet(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('change-current-passphrase')),
        'wrong',
      );
      await tester.enterText(
        find.byKey(const Key('change-new-passphrase')),
        'new-secret',
      );
      await tester.enterText(
        find.byKey(const Key('change-confirm-passphrase')),
        'different',
      );
      await tester.tap(find.byKey(const Key('change-passphrase-save')));
      await tester.pumpAndSettle();
      expect(find.text('两次输入的新口令不一致'), findsOneWidget);
      expect(repo.changes, 0);
      await tester.enterText(
        find.byKey(const Key('change-confirm-passphrase')),
        'new-secret',
      );
      await tester.tap(find.byKey(const Key('change-passphrase-save')));
      await tester.pumpAndSettle();
      expect(find.text('当前口令不正确'), findsOneWidget);
      expect(repo.changes, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('change-new-passphrase')))
            .controller!
            .text,
        'new-secret',
      );
      expect(find.widgetWithText(FilledButton, '保存新口令'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets(
    'first connection has no emulator IP and saved endpoints fill the form',
    (tester) async {
      final store = MemoryCredentialStore()
        ..endpoint = Uri.parse('http://192.0.2.45:9876');
      final repo = ServerLibraryRepository(store);
      expect(repo.snapshot.address, isEmpty);
      await tester.pumpWidget(
        ShikaApp(repository: repo, initializeRepository: true),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('connection-address')))
            .controller!
            .text,
        'http://192.0.2.45',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('connection-port')))
            .controller!
            .text,
        '9876',
      );
      expect(find.textContaining('10.0.2.2'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets(
    'restored endpoint updates inputs while ordinary refresh preserves drafts',
    (tester) async {
      final repo = ReconnectingLibrary();
      await repo.initialize();
      repo.connection(false);
      await tester.pumpWidget(ShikaApp(repository: repo));
      await tester.pumpAndSettle();
      repo.savedEndpoint('https://remembered.example', 9443);
      await tester.pumpAndSettle();
      final address = find.byKey(const Key('connection-address'));
      final port = find.byKey(const Key('connection-port'));
      expect(
        tester.widget<TextField>(address).controller!.text,
        'https://remembered.example',
      );
      expect(tester.widget<TextField>(port).controller!.text, '9443');
      await tester.enterText(address, 'editing.example');
      await tester.enterText(port, '9000');
      repo.savedEndpoint('https://remembered.example', 9443);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(address).controller!.text,
        'editing.example',
      );
      expect(tester.widget<TextField>(port).controller!.text, '9000');
      repo.savedEndpoint('http://other.example', 8760);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(address).controller!.text,
        'http://other.example',
      );
      expect(tester.widget<TextField>(port).controller!.text, '8760');
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );

  testWidgets(
    'automatic reconnection leaves the connection form without another password',
    (tester) async {
      final repo = ReconnectingLibrary();
      await repo.initialize();
      await tester.pumpWidget(ShikaApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('个人口令'), findsNothing);
      repo.connection(false);
      await tester.pumpAndSettle();
      expect(find.text('服务器地址'), findsOneWidget);
      expect(find.byKey(const Key('app-navigation')), findsNothing);
      repo.connection(true);
      await tester.pumpAndSettle();
      expect(find.text('个人口令'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
  testWidgets('connection input errors retain the entered values', (
    tester,
  ) async {
    final repo = DemoLibraryRepository(
      MemoryStateStore(),
      scenario: DemoScenario.offline,
      latency: Duration.zero,
    );
    await repo.initialize();
    await tester.pumpWidget(ShikaApp(repository: repo));
    await tester.enterText(find.byType(TextField).at(0), 'my-nas');
    await tester.enterText(find.byType(TextField).at(1), '70000');
    await tester.tap(find.byKey(const Key('connection-save')));
    await tester.pumpAndSettle();
    expect(find.text('请填写地址和 1–65535 之间的端口'), findsOneWidget);
    expect(find.text('my-nas'), findsOneWidget);
    expect(find.text('70000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
}
