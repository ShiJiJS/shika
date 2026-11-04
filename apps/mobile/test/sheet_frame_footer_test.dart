import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';

void main() {
  for (final sample in [
    (const Size(844, 390), 1.0),
    (const Size(360, 740), 2.0),
  ]) {
    testWidgets(
      'sheet action stays visible while long content scrolls $sample',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = sample.$1;
        t.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        var activated = 0;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.view.resetPadding();
        });
        const action = Key('complete-sheet');
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(sample.$2)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SheetFrame(
                  title: '阅读设置',
                  footer: FilledButton(
                    key: action,
                    onPressed: () => activated++,
                    child: const Text('继续阅读'),
                  ),
                  children: [
                    for (var i = 0; i < 30; i++)
                      SizedBox(height: 64, child: Text('阅读选项 $i')),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final before = t.getRect(find.byKey(action));
        expect(find.byKey(action).hitTestable(), findsOneWidget);
        expect(before.bottom, lessThanOrEqualTo(sample.$1.height - 24));
        await t.drag(find.byType(Scrollable), const Offset(0, -700));
        await t.pumpAndSettle();
        expect(t.getRect(find.byKey(action)), before);
        await t.tap(find.byKey(action));
        expect(activated, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
}
