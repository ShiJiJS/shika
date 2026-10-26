import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/state_store.dart';
import 'package:video_viewer/main.dart';

class _PendingRestore extends DemoLibraryRepository {
  _PendingRestore() : super(MemoryStateStore(), scenario: DemoScenario.empty);
  bool pending = true;
  @override
  bool get backupRestorePending => pending;
  @override
  Future<void> reconcileBackupRestore() async {
    pending = false;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'uncertain restore permits navigation, reconnection and query while writes remain locked',
    (t) async {
      final repo = _PendingRestore();
      await repo.initialize();
      await t.pumpWidget(VideoViewerApp(repository: repo));
      await t.pumpAndSettle();
      expect(
        t.widget<TextButton>(find.byKey(const Key('backup-query'))).onPressed,
        isNotNull,
      );
      await t.tap(find.byKey(const Key('nav-tags')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '新建视频标签',
              ),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.byKey(const Key('nav-settings')));
      await t.pumpAndSettle();
      await t.tap(find.text('备份与恢复'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出备份'))
            .onPressed,
        isNull,
      );
      await t.tap(find.byTooltip('返回设置'));
      await t.pumpAndSettle();
      await t.tap(find.text('服务连接'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('connection-save')))
            .onPressed,
        isNotNull,
      );
      expect(
        t
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == true),
        isTrue,
      );
      await t.tap(find.byTooltip('返回设置'));
      await t.pumpAndSettle();
      await t.tap(find.text('备份与恢复'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('backup-query')));
      await t.pumpAndSettle();
      expect(repo.backupRestorePending, isFalse);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, '导出备份'))
            .onPressed,
        isNotNull,
      );
      await t.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}
