import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/main.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/state_store.dart';

class ReconnectingLibrary extends DemoLibraryRepository {
  ReconnectingLibrary() : super(MemoryStateStore(), latency: Duration.zero);
  LibrarySnapshot? disconnected;
  @override
  LibrarySnapshot get snapshot => disconnected ?? super.snapshot;
  void connection(bool connected) {
    disconnected = connected ? null : super.snapshot.copy(connected: false);
    notifyListeners();
  }
}

void main() {
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
