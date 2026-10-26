import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_trash_page.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/pack_trash_fixture.dart';
import 'support/restore_plan_fixture.dart';
import 'support/reveal_action.dart';

void main() {
  for (final wholePlan in [false, true]) {
    testWidgets(
      'row restoration preserves unrelated selection, plan=$wholePlan',
      (t) async {
        final repo = wholePlan ? RestoreLibrary() : TrashLibrary(count: 3);
        await repo.initialize();
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
        });
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(body: PackTrashPage(repository: repo, active: true)),
          ),
        );
        await t.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await revealAction(t, f);
          await t.tap(f);
          await t.pumpAndSettle();
        }

        await tap(find.byKey(const Key('pack-trash-item-trash-0')));
        await tap(find.byKey(const Key('pack-trash-row-restore-trash-1')));
        if (wholePlan) {
          final plans = repo as RestoreLibrary;
          expect(find.text('恢复已选 1 个图包'), findsOneWidget);
          await tap(find.text('取消'));
          expect(plans.planBodies, isEmpty);
          expect(find.text('已选 1'), findsOneWidget);
          await tap(find.byKey(const Key('pack-trash-row-restore-trash-1')));
          await tap(find.byKey(const Key('pack-restore-plan-confirm')));
          expect(plans.planBodies.single['trash_ids'], ['trash-1']);
        } else {
          expect(repo.posts.single['trash_ids'], ['trash-1']);
          expect(repo.records.keys, contains('trash-0'));
          expect(repo.records.keys, isNot(contains('trash-1')));
        }
        expect(find.text('已选 1'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'short keyboard window retains search and reachable selection actions $scale',
      (t) async {
        final repo = TrashLibrary();
        await repo.initialize();
        t.view.physicalSize = const Size(844, 390);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        Widget host(double inset) => MaterialApp(
          theme: Paper.theme,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: const Size(844, 390),
                viewInsets: EdgeInsets.only(bottom: inset),
                textScaler: TextScaler.linear(scale),
              ),
              child: SizedBox(
                height: 390 - inset,
                child: PackTrashPage(repository: repo, active: true),
              ),
            ),
          ),
        );
        await t.pumpWidget(host(0));
        await t.pumpAndSettle();
        final select = find.byKey(const Key('pack-trash-select-all'));
        await revealAction(t, select);
        await t.tap(select);
        await t.pumpAndSettle();
        await t.pumpWidget(host(280));
        await t.pumpAndSettle();
        final action = find.byKey(const Key('pack-trash-restore'));
        await revealAction(t, action);
        expect(t.getRect(action).bottom, lessThanOrEqualTo(110.1));
        expect(repo.posts, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
