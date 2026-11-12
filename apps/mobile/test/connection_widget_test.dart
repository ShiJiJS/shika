import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/main.dart';
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

void main() {
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
      expect(find.text('个人口令'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(FilledButton, '连接'));
    await tester.pumpAndSettle();
    expect(find.text('请填写地址和 1–65535 之间的端口'), findsOneWidget);
    expect(find.text('my-nas'), findsOneWidget);
    expect(find.text('70000'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });
}
