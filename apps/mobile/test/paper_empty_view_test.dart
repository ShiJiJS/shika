import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';

void main() {
  testWidgets(
    'short library status keeps its complete message and action reachable',
    (t) async {
      var retried = false;
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: SizedBox(
              width: 844,
              height: 93,
              child: EmptyView(
                '媒体库暂时无法读取，请重试',
                action: TextButton(
                  onPressed: () => retried = true,
                  child: const Text('重试'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.text('重试'),
        60,
        scrollable: find.byType(Scrollable),
      );
      await t.tap(find.text('重试'));
      expect(retried, isTrue);
    },
  );
}
