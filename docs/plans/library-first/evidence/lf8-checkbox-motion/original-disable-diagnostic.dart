import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  testWidgets('original SDK checkbox becomes disabled while pointer is held', (t) async {
    var enabled = true;
    late StateSetter update;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (_, set) {
        update = set;
        return Checkbox(value: false, onChanged: enabled ? (_) {} : null);
      },
    ))));
    final gesture = await t.startGesture(t.getCenter(find.byType(Checkbox)));
    await t.pump(const Duration(milliseconds: 150));
    update(() => enabled = false);
    await t.pump();
    await gesture.up();
    await t.pumpWidget(const SizedBox());
  });
}
