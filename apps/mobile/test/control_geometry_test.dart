import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';

void main() {
  testWidgets(
    'steady chip layout and every pixel match original in both themes, selection and disabled states',
    (t) async {
      var compared = 0;
      for (final dark in [false, true]) {
        for (final selected in [false, true]) {
          for (final enabled in [false, true]) {
            for (final multiple in [false, true]) {
              List<int>? original;
              Size? originalSize;
              for (final paper in [false, true]) {
                final ValueChanged<bool>? onSelected = enabled ? (_) {} : null;
                final Widget chip = multiple
                    ? paper
                          ? PaperFilterChip(
                              label: const Text('收藏 标签'),
                              selected: selected,
                              onSelected: onSelected,
                            )
                          : FilterChip(
                              label: const Text('收藏 标签'),
                              selected: selected,
                              onSelected: onSelected,
                            )
                    : paper
                    ? PaperChoiceChip(
                        label: const Text('横向翻页'),
                        selected: selected,
                        onSelected: onSelected,
                      )
                    : ChoiceChip(
                        label: const Text('横向翻页'),
                        selected: selected,
                        onSelected: onSelected,
                      );
                await t.pumpWidget(
                  MaterialApp(
                    theme: dark ? Paper.darkTheme : Paper.theme,
                    home: Scaffold(
                      body: Center(
                        child: RepaintBoundary(
                          key: const Key('chip-pixels'),
                          child: chip,
                        ),
                      ),
                    ),
                  ),
                );
                await t.pumpAndSettle();
                final boundary = t.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('chip-pixels')),
                );
                final pixels = (await t.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final data = (await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))!.buffer.asUint8List();
                  image.dispose();
                  return data.toList();
                }))!;
                if (!paper) {
                  original = pixels.toList();
                  originalSize = boundary.size;
                } else {
                  expect(boundary.size, originalSize);
                  expect(
                    pixels,
                    original,
                    reason:
                        'dark=$dark selected=$selected enabled=$enabled multi=$multiple',
                  );
                  compared++;
                }
              }
            }
          }
        }
      }
      expect(compared, 16);
      expect(t.takeException(), isNull);
    },
  );
}
