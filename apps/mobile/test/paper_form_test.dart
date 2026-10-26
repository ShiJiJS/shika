import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/ui/paper_form.dart';

void main() {
  testWidgets(
    'keyboard geometry reveals the focused connection value and next field',
    (t) async {
      t.view.physicalSize = const Size(844, 390);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final port = TextEditingController(text: '8768');
      addTearDown(port.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 52, child: Text('服务器连接')),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const SizedBox(height: 80),
                      const PaperField(
                        label: '服务地址',
                        child: TextField(textInputAction: TextInputAction.next),
                      ),
                      const SizedBox(height: 20),
                      PaperField(
                        label: '端口',
                        child: TextField(
                          key: const Key('port'),
                          controller: port,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const PaperField(
                        label: '个人口令',
                        child: TextField(key: Key('secret'), obscureText: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final field = find.byKey(const Key('port'));
      await t.ensureVisible(field);
      await t.tap(field);
      await t.enterText(field, '0');
      for (final inset in [210.0, 248.0]) {
        t.view.viewInsets = FakeViewPadding(bottom: inset);
        await t.pumpAndSettle();
        expect(t.getRect(field).top, greaterThanOrEqualTo(52));
        expect(t.getRect(field).bottom, lessThanOrEqualTo(390 - inset));
        expect(
          t
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
      }
      expect(port.text, '0');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      final secret = find.byKey(const Key('secret'));
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: secret, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(t.getRect(secret).bottom, lessThanOrEqualTo(142));
      expect(t.takeException(), isNull);
    },
  );
}
