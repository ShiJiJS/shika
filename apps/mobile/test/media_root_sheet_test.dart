import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/settings/media_root_sheet.dart';
import 'package:shika/library/demo_repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/state_store.dart';
import 'package:shika/ui/paper.dart';

import 'fixed_preview_widget_test.dart' show frames;

class RootLibrary extends DemoLibraryRepository {
  RootLibrary() : super(MemoryStateStore(), latency: Duration.zero);
  bool typed = true, reject = false;
  Object owner = Object();
  MediaRoot? saved;
  int calls = 0;
  @override
  Object get connectionIdentity => owner;
  @override
  ServiceCapabilities get capabilities =>
      ServiceCapabilities([if (typed) 'typed_roots']);
  @override
  Future<void> saveRoot(MediaRoot root) async {
    calls++;
    if (reject) throw const LibraryFailure('已有内容的目录不能更改类型');
    saved = root;
  }
}

void main() {
  late RootLibrary repo;
  setUp(() async {
    repo = RootLibrary();
    await repo.initialize();
  });
  tearDown(() => repo.dispose());
  Future<void> show(
    WidgetTester t, {
    MediaRoot? root,
    double scale = 1,
    bool dark = false,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? Paper.darkTheme : Paper.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('show-root'),
              onPressed: () => paperSheet<void>(
                context,
                MediaRootSheet(repository: repo, root: root),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('show-root')));
    await frames(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await Scrollable.ensureVisible(t.element(f), alignment: .5);
    await t.pumpAndSettle();
    expect(f.hitTestable(), findsOneWidget);
    await t.tap(f);
    await frames(t);
  }

  for (final (size, scale, dark) in [
    (const Size(390, 844), 1.0, false),
    (const Size(360, 740), 2.0, false),
    (const Size(844, 390), 1.6, true),
  ]) {
    testWidgets(
      'create typed disabled root remains accessible at $size/$scale/$dark',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await show(t, scale: scale, dark: dark);
        await t.enterText(find.byKey(const Key('root-name')), '图包目录');
        await t.enterText(
          find.byKey(const Key('root-path')),
          '/media/packs///',
        );
        await tap(t, find.byKey(const Key('root-kind')));
        await tap(t, find.text('图包文件夹').hitTestable().last);
        await tap(t, find.byKey(const Key('root-enabled')));
        await tap(t, find.byKey(const Key('root-save')));
        expect(repo.calls, 1);
        expect(repo.saved!.kind, MediaKind.pack);
        expect(repo.saved!.enabled, isFalse);
        expect(repo.saved!.path, '/media/packs');
        expect(find.byType(MediaRootSheet), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'landscape keyboard keeps the focused input and save reachable without overflow',
    (t) async {
      t.view.physicalSize = const Size(844, 390);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      await show(t);
      final input = find.byKey(const Key('root-name'));
      await t.tap(input);
      await t.enterText(input, '横屏输入保留');
      t.view.viewInsets = const FakeViewPadding(bottom: 248);
      await frames(t);
      expect(t.takeException(), isNull);
      expect(t.widget<TextField>(input).controller!.text, '横屏输入保留');
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
      await Scrollable.ensureVisible(t.element(input), alignment: .5);
      await frames(t);
      expect(input.hitTestable(), findsOneWidget);
      await tap(t, find.byKey(const Key('root-save')));
      expect(find.byKey(const Key('root-error')).hitTestable(), findsOneWidget);
      expect(repo.calls, 0);
      t.view.resetViewInsets();
      await frames(t);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'root kind conflict retains input and cancellation has no second write',
    (t) async {
      repo.reject = true;
      await show(
        t,
        root: MediaRoot(
          'existing',
          '旧图包',
          '/media/packs',
          kind: MediaKind.pack,
          enabled: false,
        ),
      );
      expect(
        t.widget<SwitchListTile>(find.byKey(const Key('root-enabled'))).value,
        isFalse,
      );
      await t.enterText(find.byKey(const Key('root-name')), '保留输入');
      await tap(t, find.byKey(const Key('root-kind')));
      await tap(t, find.text('视频文件').hitTestable().last);
      await tap(t, find.byKey(const Key('root-save')));
      expect(find.textContaining('已有内容的目录不能更改类型'), findsOneWidget);
      expect(find.textContaining('请新建正确类型的接入目录'), findsOneWidget);
      final error = find.byKey(const Key('root-error'));
      expect(error.hitTestable(), findsOneWidget);
      expect(
        t.getRect(error).bottom,
        lessThanOrEqualTo(t.getRect(find.byKey(const Key('root-save'))).top),
      );
      expect(
        t
            .widget<TextField>(find.byKey(const Key('root-name')))
            .controller!
            .text,
        '保留输入',
      );
      await tap(t, find.byTooltip('关闭面板'));
      expect(repo.calls, 1);
      expect(repo.saved, isNull);
    },
  );
  testWidgets(
    'old service keeps original root controls and a changed connection cannot save',
    (t) async {
      repo.typed = false;
      await show(t);
      expect(find.byKey(const Key('root-kind-pack')), findsNothing);
      expect(find.byKey(const Key('root-enabled')), findsNothing);
      await t.enterText(find.byKey(const Key('root-name')), '旧目录');
      await t.enterText(find.byKey(const Key('root-path')), '/media/videos');
      repo.owner = Object();
      await tap(t, find.byKey(const Key('root-save')));
      expect(find.text('服务连接已变化，请关闭后重新打开目录设置'), findsOneWidget);
      expect(repo.calls, 0);
    },
  );
}
