import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/media_layout.dart';
import 'package:video_viewer/ui/paper.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('long catalog actions remain reachable at scale $scale', (
      t,
    ) async {
      t.view.physicalSize = const Size(360, 809);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final pressed = <String>[];
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: MediaCatalogToolbar(
              children: [
                const Text('4 个图包'),
                for (final label in ['阅读状态', '最近加入 ↓', '快速整理'])
                  TextButton(
                    onPressed: () => pressed.add(label),
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('快速整理'));
      await t.pumpAndSettle();
      await t.tap(find.text('快速整理'));
      await t.ensureVisible(find.text('阅读状态'));
      await t.pumpAndSettle();
      await t.tap(find.text('阅读状态'));
      expect(pressed, ['快速整理', '阅读状态']);
      expect(t.takeException(), isNull);
    });
  }
}
