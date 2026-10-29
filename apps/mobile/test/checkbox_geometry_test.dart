import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';

void main() {
  testWidgets(
    'checkbox and row retain every original RGBA pixel in 96 configurations',
    (t) async {
      var count = 0;
      for (final dark in [false, true]) {
        for (final material3 in [false, true]) {
          for (final rtl in [false, true]) {
            for (final value in <bool?>[false, true, null]) {
              for (final enabled in [false, true]) {
                for (final tile in [false, true]) {
                  List<int>? original;
                  Size? size;
                  for (final paper in [false, true]) {
                    final ValueChanged<bool?>? change = enabled ? (_) {} : null;
                    final Widget control = tile
                        ? paper
                              ? PaperCheckboxListTile(
                                  title: const Text('Keep selection'),
                                  value: value,
                                  tristate: true,
                                  onChanged: change,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                )
                              : CheckboxListTile(
                                  title: const Text('Keep selection'),
                                  value: value,
                                  tristate: true,
                                  onChanged: change,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                )
                        : paper
                        ? PaperCheckbox(
                            value: value,
                            tristate: true,
                            onChanged: change,
                          )
                        : Checkbox(
                            value: value,
                            tristate: true,
                            onChanged: change,
                          );
                    await t.pumpWidget(
                      MaterialApp(
                        theme: (dark ? Paper.darkTheme : Paper.theme).copyWith(
                          // Preserve every other Paper theme field for the SDK parity check.
                          // ignore: deprecated_member_use
                          useMaterial3: material3,
                        ),
                        home: Directionality(
                          textDirection: rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Scaffold(
                            body: Center(
                              child: RepaintBoundary(
                                key: const Key('pixels'),
                                child: SizedBox(
                                  width: tile ? 320 : 48,
                                  child: control,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                    await t.pumpAndSettle();
                    final boundary = t.renderObject<RenderRepaintBoundary>(
                      find.byKey(const Key('pixels')),
                    );
                    final rgba = (await t.runAsync(() async {
                      final image = await boundary.toImage(pixelRatio: 1);
                      final data = (await image.toByteData(
                        format: ui.ImageByteFormat.rawRgba,
                      ))!.buffer.asUint8List();
                      image.dispose();
                      return data;
                    }))!;
                    if (!paper) {
                      original = rgba;
                      size = boundary.size;
                    } else {
                      expect(boundary.size, size);
                      expect(
                        rgba,
                        orderedEquals(original!),
                        reason: '$dark/$material3/$rtl/$value/$enabled/$tile',
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
      }
      expect(count, 96);
      debugPrint('ACTUAL checkbox RGBA comparisons=$count');
      expect(t.takeException(), isNull);
    },
  );
}
