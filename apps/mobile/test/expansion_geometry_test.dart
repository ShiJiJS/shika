import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/ui/paper.dart';

void main() {
  testWidgets(
    'scan expansion retains SDK RGBA and size in32 settled configurations',
    (t) async {
      var count = 0;
      for (final dark in [false, true]) {
        for (final material3 in [false, true]) {
          for (final rtl in [false, true]) {
            for (final open in [false, true]) {
              for (final explicitTitle in [false, true]) {
                List<int>? expected;
                Size? expectedSize;
                for (final owned in [false, true]) {
                  final theme = (dark ? Paper.darkTheme : Paper.theme).copyWith(
                    // Same pinned theme except the SDK version's M2/M3 defaults.
                    // ignore: deprecated_member_use
                    useMaterial3: material3,
                  );
                  final title = Text(
                    'Scan completed · 4 / 4',
                    style: explicitTitle
                        ? TextStyle(
                            fontSize: 13,
                            color: theme.extension<PaperPalette>()!.catalogMeta,
                          )
                        : null,
                  );
                  const children = [
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Four retained files\nNo scan command'),
                    ),
                  ];
                  final tile = owned
                      ? PaperExpansionTile(
                          title: title,
                          tilePadding: EdgeInsets.zero,
                          children: children,
                        )
                      : ExpansionTile(
                          title: title,
                          tilePadding: EdgeInsets.zero,
                          children: children,
                        );
                  await t.pumpWidget(
                    MaterialApp(
                      theme: theme,
                      home: Directionality(
                        textDirection: rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Scaffold(
                          body: Center(
                            child: RepaintBoundary(
                              key: const Key('expansion-pixels'),
                              child: SizedBox(width: 320, child: tile),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  await t.pumpAndSettle();
                  if (open) {
                    await t.tap(find.text('Scan completed · 4 / 4'));
                    await t.pumpAndSettle();
                  }
                  final boundary = t.renderObject<RenderRepaintBoundary>(
                    find.byKey(const Key('expansion-pixels')),
                  );
                  final pixels = (await t.runAsync(() async {
                    final image = await boundary.toImage(pixelRatio: 1);
                    final data = (await image.toByteData(
                      format: ui.ImageByteFormat.rawRgba,
                    ))!.buffer.asUint8List();
                    image.dispose();
                    return data;
                  }))!;
                  if (!owned) {
                    expected = pixels;
                    expectedSize = boundary.size;
                  } else {
                    expect(boundary.size, expectedSize);
                    expect(
                      pixels,
                      expected,
                      reason: '$dark/$material3/$rtl/$open/$explicitTitle',
                    );
                    count++;
                  }
                  await t.pumpWidget(const SizedBox());
                }
              }
            }
          }
        }
      }
      expect(count, 32);
    },
  );
}
