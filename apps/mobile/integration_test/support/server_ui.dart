import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/ui/player.dart';
import 'package:video_viewer/ui/sheets.dart';

/// Public controls shared by the real-service management tests.
class ServerUi {
  ServerUi(this.t, this.repo);
  final WidgetTester t;
  final ServerLibraryRepository repo;
  final surface = find.byKey(const Key('video-gesture-surface')).last;

  Future<void> until(bool Function() condition, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        debugPrint(
          'VISIBLE_UI ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().join(' | ')}',
        );
        fail('Timed out: $reason');
      }
      await t.pump(const Duration(milliseconds: 80));
    }
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> idle() => until(
    () => find.byKey(const Key('management-loading')).evaluate().isEmpty,
    'management operation',
  );

  Future<void> tap(Finder target) async {
    bool exists() {
      try {
        return target.evaluate().isNotEmpty;
      } on StateError {
        return false;
      }
    }

    await until(exists, 'control appears');
    if (target.hitTestable().evaluate().isEmpty) await t.ensureVisible(target);
    await until(
      () =>
          target.hitTestable().evaluate().isNotEmpty &&
          target.evaluate().every(
            (e) => e.widget is! InkWell || (e.widget as InkWell).onTap != null,
          ),
      'control accepts taps',
    );
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 300));
    await idle();
  }

  Future<void> text(String value) => tap(find.text(value).last);
  Future<void> nav(String page) async {
    if (find.byKey(Key('nav-$page')).evaluate().isEmpty &&
        find.byTooltip('返回设置').evaluate().isNotEmpty) {
      await tap(find.byTooltip('返回设置'));
    }
    await tap(find.byKey(Key('nav-$page')));
  }

  Future<void> ready() => until(
    () =>
        find
            .byWidgetPredicate(
              (w) =>
                  w is PlayerSurface &&
                  w.name == repo.current?.name &&
                  w.interactionsEnabled,
            )
            .evaluate()
            .isNotEmpty &&
        find.byType(VideoPlayer).evaluate().isNotEmpty &&
        t
            .widget<VideoPlayer>(find.byType(VideoPlayer).last)
            .controller
            .value
            .isInitialized,
    'authenticated video',
  );

  Future<void> folder(List<String> names) async {
    await tap(find.byTooltip('选择文件夹'));
    await text('媒体目录');
    for (final name in names) {
      await text(name);
    }
    await until(
      () =>
          t
              .widget<FilledButton>(
                find.descendant(
                  of: find.byType(FolderPicker),
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed !=
          null,
      'directory loaded',
    );
    await text(names.isEmpty ? '使用全部目录' : '使用此目录');
  }

  Future<void> clearScope() async {
    await nav('library');
    await tap(find.byTooltip('筛选视频'));
    await text('清除条件');
    await text('应用筛选');
  }

  Future<void> search(String name, int count) async {
    final field = find.byKey(const Key('video-search'));
    await until(() => field.evaluate().isNotEmpty, 'search field');
    await t.enterText(field, name);
    await until(
      () => find.text('$count 个视频').evaluate().isNotEmpty,
      'search results',
    );
  }

  Future<void> tagChip(String name) =>
      tap(find.widgetWithText(FilterChip, name).last);
  Future<void> select(String current, String value) async {
    await text(current);
    await text(value);
  }
}
