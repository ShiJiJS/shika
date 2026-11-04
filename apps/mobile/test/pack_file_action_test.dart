import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_file_action.dart';
import 'package:shika/library/file_command_store.dart';
import 'package:shika/library/pack_files.dart';
import 'package:shika/library/server_api.dart';
import 'package:shika/ui/paper.dart';

import 'pack_files_test.dart' show FilesFixture;

typedef Json = Map<String, dynamic>;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontPath = Platform.environment['LF6_CJK_FONT'];
    if (fontPath != null) {
      final bytes = ByteData.sublistView(await File(fontPath).readAsBytes());
      final body = FontLoader('Roboto')..addFont(Future.value(bytes));
      final title = FontLoader('PaperSerif')
        ..addFont(rootBundle.load('assets/fonts/PaperSerif.ttf'))
        ..addFont(Future.value(bytes));
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await Future.wait([body.load(), title.load(), icons.load()]);
    }
  });
  final boundary = GlobalKey();
  Future<void> host(
    WidgetTester tester,
    PackFiles files,
    PackFileCommand command,
    void Function(PackFileOutcome?) receive, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: Paper.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  receive(
                    await showPackFileAction(
                      context,
                      files: files,
                      command: command,
                      title: '移入回收站？',
                      description: '夏日海边与城市散步的完整图包 · 500 张',
                    ),
                  );
                },
                child: const Text('打开操作'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开操作'));
    await tester.pumpAndSettle();
  }

  for (final size in [
    (width: 320.0, scale: 1.0),
    (width: 360.0, scale: 2.0),
    (width: 390.0, scale: 1.0),
  ]) {
    testWidgets(
      'whole-pack confirmation at ${size.width} / ${size.scale} is explicit and fits',
      (tester) async {
        var posts = 0;
        PackFileOutcome? outcome;
        final files = PackFiles(
          journal: PackFileJournal(MemoryFileCommandStore()),
          scope: 'fixture',
          isCurrent: () => true,
          call: (method, path, {body}) async {
            posts++;
            return FilesFixture().task('op-once', 'trash', ['p0']);
          },
        );
        await host(
          tester,
          files,
          PackFileCommand.trash('once', ['p0']),
          (v) => outcome = v,
          width: size.width,
          scale: size.scale,
        );
        expect(posts, 0);
        expect(find.textContaining('500 张'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['LF6_WIDGET_SHOTS'];
        if (directory != null) {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/confirmation-${size.width.toInt()}-${size.scale.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
        await tester.pumpAndSettle();
        expect(posts, 1);
        expect(outcome!.task.result!.succeeded, 1);
        expect((await files.pending()).length, 1);
        await files.acknowledge(outcome!.command);
        expect(await files.pending(), isEmpty);
      },
    );
  }
  testWidgets(
    'failed response and unknown receipt stay on same object without automatic POST replay',
    (tester) async {
      var posts = 0, gets = 0;
      PackFileOutcome? outcome;
      final store = MemoryFileCommandStore();
      final files = PackFiles(
        journal: PackFileJournal(store),
        scope: 'fixture',
        isCurrent: () => true,
        call: (method, path, {body}) async {
          if (method == 'POST') {
            posts++;
            throw const ApiFailure('网络暂不可用', code: 'reply_lost', status: 503);
          }
          gets++;
          throw const ApiFailure('未找到原请求', code: 'not_found', status: 404);
        },
      );
      await host(
        tester,
        files,
        PackFileCommand.trash('lost', ['p0']),
        (v) => outcome = v,
      );
      await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.byKey(const Key('pack-operation-error')), findsOneWidget);
      expect(find.textContaining('500 张'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '查询原结果'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(gets, 1);
      expect(find.text('重新提交原请求'), findsOneWidget);
      await tester.tap(find.text('稍后处理'));
      await tester.pumpAndSettle();
      expect(outcome, isNull);
      expect((await files.pending()).single.requestId, 'lost');
    },
  );
  testWidgets(
    'reopening a pack adopts the saved original request and only reads its receipt',
    (tester) async {
      var posts = 0, gets = 0;
      PackFileOutcome? outcome;
      final journal = PackFileJournal(MemoryFileCommandStore());
      final old = PackFileCommand.trash('original', ['p0']);
      await journal.remember('fixture', old);
      final files = PackFiles(
        journal: journal,
        scope: 'fixture',
        isCurrent: () => true,
        call: (method, path, {body}) async {
          if (method == 'POST') {
            posts++;
          } else {
            gets++;
          }
          expect(path, '/api/v1/pack-file-requests/original');
          return FilesFixture().task('original-task', 'trash', ['p0']);
        },
      );
      await host(
        tester,
        files,
        PackFileCommand.trash('new-intent', ['p0']),
        (v) => outcome = v,
      );
      expect(posts, 0);
      expect(gets, 1);
      expect(outcome!.command.requestId, 'original');
      expect((await files.pending()).single.requestId, 'original');
    },
  );
  testWidgets(
    'closing while service is working leaves a durable request and ignores the late UI result',
    (tester) async {
      final response = Completer<Json>();
      PackFileOutcome? outcome;
      var returned = false;
      final files = PackFiles(
        journal: PackFileJournal(MemoryFileCommandStore()),
        scope: 'fixture',
        isCurrent: () => true,
        call: (method, path, {body}) => response.future,
      );
      await host(tester, files, PackFileCommand.trash('inflight', ['p0']), (v) {
        outcome = v;
        returned = true;
      });
      await tester.tap(find.widgetWithText(FilledButton, '移入回收站'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text('稍后处理'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(outcome, isNull);
      response.complete(FilesFixture().task('op-inflight', 'trash', ['p0']));
      await tester.pump();
      expect((await files.pending()).single.requestId, 'inflight');
      expect(tester.takeException(), isNull);
    },
  );
}
