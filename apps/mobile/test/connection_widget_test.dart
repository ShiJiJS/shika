import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';

void main() {
  testWidgets('connection input errors retain the entered values', (
    tester,
  ) async {
    final repo = DemoLibraryRepository(
      MemoryStateStore(),
      scenario: DemoScenario.offline,
      latency: Duration.zero,
    );
    await repo.initialize();
    await tester.pumpWidget(VideoViewerApp(repository: repo));
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
