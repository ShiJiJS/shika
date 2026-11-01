import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_viewer/features/packs/pack_sheets.dart';
import 'package:video_viewer/library/credentials.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_repository.dart';
import 'package:video_viewer/main.dart';

import 'support/fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'LF4 real pack names beyond first page, retry, readback, rename and delete',
    (t) async {
      await fixture('/__fixture/actions/reset-login-limit');
      final seed = await fixture('/__fixture/actions/workspace-packs');
      final store = SecureCredentialStore(
        key: 'video_viewer.e2e.pack-names.v1',
      );
      await store.clear();
      final repo = ServerLibraryRepository(store, port: 8761);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(milliseconds: 200));
        repo.dispose();
        await store.clear();
      });
      await repo.connect('http://10.0.2.2', 8761, fixturePassword);
      await repo.saveRoot(
        MediaRoot('', '标签图包', seed['path'], kind: MediaKind.pack),
      );
      await repo.refresh();
      final ids = <String>[];
      for (var i = 0; i < 61; i++) {
        ids.add(
          (await repo.createPackTag('名称${i.toString().padLeft(2, '0')}')).id,
        );
      }
      await repo.editTag(name: '名称60');
      final pack = (await repo.loadPacks(PackQuery())).items.first;
      await repo.setPackTags({pack.id}, {ids.last});
      await t.pumpWidget(VideoViewerApp(repository: repo));

      Future<void> until(bool Function() done, String reason) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            await fixture('/__fixture/checkpoint/error');
            await t.pump(const Duration(seconds: 2));
            fail('Timed out: $reason');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pump(const Duration(milliseconds: 200));
      }

      Future<void> idle() => until(
        () =>
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        'catalog settled',
      );
      Future<void> tap(Finder finder) async {
        await until(() {
          final elements = finder.evaluate().toList();
          if (elements.length != 1) return false;
          final route = ModalRoute.of(elements.single);
          return route == null ||
              (route.isCurrent &&
                  (route.animation == null ||
                      route.animation!.status == AnimationStatus.completed));
        }, 'target route entered');
        await t.ensureVisible(finder);
        await until(() {
          if (finder.hitTestable().evaluate().length != 1) return false;
          final size = t.view.physicalSize / t.view.devicePixelRatio;
          return (Offset.zero & size).contains(t.getCenter(finder));
        }, 'target is inside the viewport and can receive input');
        await t.tap(finder);
        await t.pump(const Duration(milliseconds: 300));
        await idle();
      }

      Future<void> shot(String phase) async {
        if (phase != 'retry') {
          final label = find.byKey(Key('pack-tag-names-${pack.id}'));
          await Scrollable.ensureVisible(
            t.element(label),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
          await t.pump(const Duration(milliseconds: 200));
          await until(
            () => label.hitTestable().evaluate().isNotEmpty,
            'card label visible for native evidence',
          );
          if (phase == 'card') {
            await until(
              () => t
                  .widgetList<RawImage>(find.byType(RawImage))
                  .any((image) => image.image != null),
              'pack covers decoded',
            );
            await until(
              () => find.byTooltip('重新加载封面').hitTestable().evaluate().isEmpty,
              'bounded cover retry settled',
            );
          }
        }
        expect(t.takeException(), isNull);
        await fixture('/__fixture/checkpoint/pack-names-$phase');
        await t.pump(const Duration(seconds: 2));
      }

      Finder chosen(String id) => find.byKey(Key('chosen-pack-tag-$id'));
      Finder editorInput() => find.byKey(const Key('tag-assignment-search'));
      Future<void> text(Finder input, String value) async {
        await tap(input);
        await t.enterText(input, value);
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await idle();
      }

      final card = find.byKey(Key('pack-tag-names-${pack.id}'));
      String cardText() => t.widget<Text>(card).data!;
      Future<void> library() async {
        await tap(find.byKey(const Key('nav-library')));
        await until(() => card.evaluate().isNotEmpty, 'pack card returned');
      }

      Future<void> manage(String name) async {
        await tap(find.byKey(const Key('nav-tags')));
        if (find.byKey(const Key('pack-tag-search')).evaluate().isEmpty) {
          await tap(find.byKey(const Key('kind-pack')));
        }
        await text(find.byKey(const Key('pack-tag-search')), '名称60');
        await tap(find.byTooltip('管理图包标签 $name'));
      }

      await idle();
      await tap(find.byKey(const Key('kind-pack')));
      await until(
        () => card.evaluate().isNotEmpty && cardText() == '# 名称60',
        'authoritative card label name',
      );
      await shot('card');
      await fixture('/__fixture/actions/fail-pack-names');
      await tap(find.byTooltip('图包操作 ${pack.name}'));
      await tap(find.text('整包标签'));
      await until(() {
        final retry = find.widgetWithText(TextButton, '重试读取名称');
        return retry.evaluate().length == 1 &&
            t.widget<TextButton>(retry).onPressed != null;
      }, 'selected-name failure is visible and ready for explicit retry');
      expect(chosen(ids.last), findsOneWidget);
      final save = find.widgetWithText(FilledButton, '保存整包标签');
      expect(t.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text('重试读取名称'), findsOneWidget);
      await shot('retry');
      // A broken idle transport may fail before reaching the injected 503.
      // Exercise bounded explicit user retries; each must retain the draft.
      // The final trace still requires the controlled 503 and a real 200.
      for (
        var retry = 0;
        retry < 3 && t.widget<FilledButton>(save).onPressed == null;
        retry++
      ) {
        expect(chosen(ids.last), findsOneWidget);
        await tap(find.text('重试读取名称'));
        await until(() {
          if (save.evaluate().length != 1) return false;
          if (t.widget<FilledButton>(save).onPressed != null) return true;
          final retry = find.widgetWithText(TextButton, '重试读取名称');
          return retry.evaluate().length == 1 &&
              t.widget<TextButton>(retry).onPressed != null;
        }, 'name resolution settled after explicit retry');
      }
      expect(t.widget<FilledButton>(save).onPressed, isNotNull);
      await text(editorInput(), '名称00');
      await tap(
        find.ancestor(
          of: find.text('名称00'),
          matching: find.bySubtype<FilterChip>(),
        ),
      );
      expect(chosen(ids.last), findsOneWidget);
      await tap(save);
      // Reopen from the same card's action menu and read back both saved choices.
      await tap(find.byTooltip('图包操作 ${pack.name}'));
      await tap(find.text('整包标签'));
      await until(
        () =>
            chosen(ids.first).evaluate().isNotEmpty &&
            chosen(ids.last).evaluate().isNotEmpty &&
            save.evaluate().length == 1 &&
            t.widget<FilledButton>(save).onPressed != null,
        'saved labels read back',
      );
      expect(chosen(ids.first), findsOneWidget);
      expect(chosen(ids.last), findsOneWidget);
      await tap(
        find.descendant(
          of: find.byType(PackTagEditor),
          matching: find.byTooltip('关闭面板'),
        ),
      );
      await until(
        () => cardText().contains('名称00') && cardText().contains('名称60'),
        'saved card names read back',
      );
      final selected = await repo.loadPacks(
        PackQuery(tags: {ids.first, ids.last}),
      );
      expect(selected.total, 1);
      expect(selected.items.single.id, pack.id);
      await shot('saved');
      await manage('名称60');
      await text(find.byKey(const Key('tag-name')), '名称60改名');
      await tap(find.byKey(const Key('tag-definition-save')));
      await library();
      await until(
        () => cardText().contains('名称60改名'),
        'renamed card refreshed',
      );
      expect(
        (await repo.loadVideoTags(search: '名称60')).items.single.name,
        '名称60',
      );
      await shot('renamed');
      await manage('名称60改名');
      await tap(find.text('移除这个标签'));
      await tap(find.text('确认移除标签'));
      await library();
      await until(
        () => cardText() == '# 名称00',
        'deleted label removed from card',
      );
      final lookup = await repo.resolvePackTags({ids.last});
      expect(lookup.missing, {ids.last});
      expect(
        (await repo.loadVideoTags(search: '名称60')).items.single.name,
        '名称60',
      );
      final trace = await fixture('/__fixture/trace', method: 'GET');
      final reads = (trace['items'] as List).cast<Map<String, dynamic>>().where(
        (row) => row['path'] == '/api/v1/pack-tags/resolve',
      );
      expect(reads.map((r) => r['status']), containsAllInOrder([503, 200]));
      await fixture('/__fixture/checkpoint/done');
    },
  );
}
