import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/ui/paper.dart';
import 'package:video_viewer/features/packs/pack_file_action.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/pack_files.dart';
import 'package:video_viewer/library/state_store.dart';

import 'pack_files_test.dart' show FilesFixture;

SnackBar notice(BuildContext context, String label, VoidCallback undo) =>
    PaperSnackBar(
      context: context,
      content: Text(label),
      duration: const Duration(seconds: 8),
      margin: const EdgeInsets.all(12),
      action: SnackBarAction(label: 'undo', onPressed: undo),
    );

void main() {
  for (final entryReduced in [false, true]) {
    for (final exitReduced in [false, true]) {
      for (final action in [false, true]) {
        testWidgets(
          'notice entry=$entryReduced exit=$exitReduced action=$action preserves undo and close reason',
          (t) async {
            t.platformDispatcher.accessibilityFeaturesTestValue =
                FakeAccessibilityFeatures(disableAnimations: entryReduced);
            addTearDown(
              t.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
            late BuildContext context;
            var undoCount = 0;
            await t.pumpWidget(
              MaterialApp(
                theme: Paper.theme,
                home: Builder(
                  builder: (value) {
                    context = value;
                    return const Scaffold(body: Text('source'));
                  },
                ),
              ),
            );
            SnackBarClosedReason? closed;
            final messenger = ScaffoldMessenger.of(context);
            final feature = messenger.showSnackBar(
              notice(context, 'kept message', () => undoCount++),
            );
            unawaited(feature.closed.then((value) => closed = value));
            await t.pump();
            final bar = t.widget<SnackBar>(find.byType(SnackBar));
            final controller = bar.animation! as AnimationController;
            expect(controller.duration, const Duration(milliseconds: 160));
            expect(controller.value, entryReduced ? 1 : 0);
            expect(bar.duration, const Duration(seconds: 8));
            expect(bar.margin, const EdgeInsets.all(12));
            if (!entryReduced) {
              await t.pump(const Duration(milliseconds: 80));
              expect(controller.value, inExclusiveRange(0, 1));
              await t.pump(const Duration(milliseconds: 96));
            }
            t.platformDispatcher.accessibilityFeaturesTestValue =
                FakeAccessibilityFeatures(disableAnimations: exitReduced);
            await t.pump();
            expect(
              controller.reverseDuration,
              Duration(milliseconds: exitReduced ? 0 : 160),
            );
            if (action) {
              await t.tap(find.text('undo'));
              expect(undoCount, 1);
            } else {
              messenger.hideCurrentSnackBar();
              expect(undoCount, 0);
            }
            expect(controller.value, exitReduced ? 0 : 1);
            await t.pump();
            if (!exitReduced) {
              await t.pump(const Duration(milliseconds: 80));
              expect(controller.value, inExclusiveRange(0, 1));
              await t.pump(const Duration(milliseconds: 96));
            }
            await t.pump();
            expect(
              closed,
              action ? SnackBarClosedReason.action : SnackBarClosedReason.hide,
            );
            expect(find.text('kept message'), findsNothing);
            expect(find.text('source'), findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  for (final initialReduced in [false, true]) {
    testWidgets(
      'queued notices keep their controller when preference changes from $initialReduced',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: initialReduced);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        late BuildContext context;
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Builder(
              builder: (value) {
                context = value;
                return const Scaffold(body: Text('source'));
              },
            ),
          ),
        );
        final messenger = ScaffoldMessenger.of(context);
        final first = messenger.showSnackBar(
          PaperSnackBar(
            context: context,
            content: const Text('first notice'),
            duration: const Duration(seconds: 8),
          ),
        );
        await t.pump();
        if (!initialReduced) await t.pump(const Duration(milliseconds: 176));
        final shared = t.widget<SnackBar>(find.byType(SnackBar)).animation!;
        final second = messenger.showSnackBar(
          PaperSnackBar(
            context: context,
            content: const Text('second notice'),
            duration: const Duration(seconds: 8),
          ),
        );
        t.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: !initialReduced);
        await t.pump();
        messenger.hideCurrentSnackBar();
        await t.pump();
        if (initialReduced) {
          await t.pump(const Duration(milliseconds: 176));
          await t.pump(const Duration(milliseconds: 176));
        }
        expect(find.text('first notice'), findsNothing);
        expect(find.text('second notice'), findsOneWidget);
        expect(
          t.widget<SnackBar>(find.byType(SnackBar)).animation,
          same(shared),
        );
        expect(await first.closed, SnackBarClosedReason.hide);
        messenger.removeCurrentSnackBar();
        await t.pump();
        expect(await second.closed, SnackBarClosedReason.remove);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'actual whole-pack undo notice expires after its configured display duration without invoking undo',
    (t) async {
      final repo = DemoLibraryRepository(MemoryStateStore());
      addTearDown(repo.dispose);
      var commands = 0;
      final files = PackFiles(
        journal: PackFileJournal(MemoryFileCommandStore()),
        scope: 'fixture',
        isCurrent: () => true,
        call: (method, path, {body}) async {
          commands++;
          throw StateError('unexpected undo');
        },
      );
      final command = PackFileCommand.trash('deadline', ['p0']);
      final task = PackFileTask.fromJson(
        FilesFixture().task('deadline-task', 'trash', ['p0']),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPackUndo(
                  context,
                  repo,
                  PackFileOutcome(files, command, task),
                ),
                child: const Text('show undo'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('show undo'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 176));
      expect(find.text('已移入回收站，源文件保留'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);
      await t.pump(const Duration(seconds: 9));
      await t.pump(const Duration(milliseconds: 176));
      expect(find.text('已移入回收站，源文件保留'), findsNothing);
      expect(find.text('撤销'), findsNothing);
      expect(commands, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
}
