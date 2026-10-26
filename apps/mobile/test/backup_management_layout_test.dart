import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';
import 'package:video_viewer/ui/home.dart' show BackupFiles;

import 'support/reveal_action.dart';

class _Repository extends DemoLibraryRepository {
  _Repository() : super(MemoryStateStore(), scenario: DemoScenario.empty);
  int inspections = 0, restores = 0;
  @override
  Future<BackupPreview> inspectBackupFile(String text) async {
    inspections++;
    return super.inspectBackupFile(text);
  }

  @override
  Future<void> restoreBackup(String text, Map<String, String> paths) async {
    restores++;
  }
}

class _Files implements BackupFiles {
  String? selected;
  bool saved = false;
  @override
  Future<String?> open() async => selected;
  @override
  Future<bool> save(String text) async => saved;
}

void main() {
  for (final p in [
    (390.0, 844.0, 1.0),
    (360.0, 740.0, 2.0),
    (844.0, 390.0, 1.0),
    (844.0, 390.0, 2.0),
  ]) {
    testWidgets(
      'legacy preview inspects once, preserves keyboard draft and cancels without restore $p',
      (t) async {
        final repo = _Repository();
        await repo.initialize();
        final files = _Files()..selected = await repo.exportBackupFile();
        t.view.physicalSize = Size(p.$1, p.$2);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = p.$3;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.view.resetViewInsets();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await t.pumpWidget(
          VideoViewerApp(repository: repo, backupFiles: files),
        );
        await t.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await revealAction(t, f);
          await t.tap(f);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }

        await tap(find.byKey(const Key('nav-settings')));
        await tap(find.text('备份与恢复'));
        await tap(find.byKey(const Key('backup-export')));
        expect(
          t.widget<Text>(find.byKey(const Key('backup-status'))).data,
          '保存已取消，可在操作任务下载原备份',
        );
        files.saved = true;
        await tap(find.byKey(const Key('backup-export')));
        expect(
          t.widget<Text>(find.byKey(const Key('backup-status'))).data,
          '备份已保存到所选位置',
        );
        await tap(find.byKey(const Key('backup-pick')));
        expect(repo.inspections, 1);
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('restore-confirm')),
              )
              .value,
          isFalse,
        );
        final submit = find.byKey(const Key('restore-submit'));
        await revealAction(t, submit);
        expect(t.widget<FilledButton>(submit).onPressed, isNull);
        final field = find.byKey(const Key('mapping-r1'));
        await revealAction(t, field);
        await t.enterText(field, '/保留/草稿');
        await t.showKeyboard(field);
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpAndSettle();
        expect(MediaQuery.viewInsetsOf(t.element(field)).bottom, 280);
        expect(
          t
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(
          t
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .controller
              .text,
          '/保留/草稿',
        );
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        await tap(find.byKey(const Key('restore-cancel')));
        expect(repo.restores, 0);
        files.selected = null;
        await tap(find.byKey(const Key('backup-pick')));
        expect(repo.inspections, 1);
        expect(find.byKey(const Key('restore-confirm')), findsNothing);
        files.selected = 'not a backup';
        await tap(find.byKey(const Key('backup-pick')));
        expect(repo.inspections, 2);
        expect(find.byKey(const Key('operation-error')), findsOneWidget);
        expect(find.byKey(const Key('restore-confirm')), findsNothing);
        expect(repo.restores, 0);
      },
    );
  }
}
