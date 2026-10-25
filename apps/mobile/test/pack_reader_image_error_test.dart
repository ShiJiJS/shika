import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

class _RealHttp extends HttpOverrides {}

void main() {
  for (final sample in [
    (ReaderMode.horizontal, const Size(390, 844), 1.0, 404),
    (ReaderMode.vertical, const Size(390, 844), 1.0, 200),
    (ReaderMode.horizontal, const Size(360, 740), 2.0, 404),
    (ReaderMode.vertical, const Size(844, 390), 1.0, 200),
    (ReaderMode.horizontal, const Size(844, 390), 1.0, 404),
  ]) {
    testWidgets('last failed image can be skipped to pack end $sample', (
      t,
    ) async {
      final server = await t.runAsync(
        () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );
      final requests = <String>[];
      server!.listen((request) async {
        requests.add(request.uri.path);
        request.response.persistentConnection = false;
        request.response.statusCode = sample.$4;
        request.response.add([
          0,
          1,
          2,
          3,
        ]); // Real 200 bytes that cannot decode.
        await request.response.close();
      });
      final client = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      debugNetworkImageHttpClientProvider = () => client;
      final repo = AssetReadingLibrary();
      repo.prefs['p0'] = ReaderPreferences(mode: sample.$1);
      repo.marks['p0'] = const ReaderMark('p0-2');
      repo.pageImage = (pack, index) => index == 2
          ? MediaSource(
              'http://127.0.0.1:${server.port}/$pack/$index',
              asset: false,
            )
          : const MediaSource('assets/media/flower-portrait.jpg', asset: true);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = sample.$2;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        debugNetworkImageHttpClientProvider = null;
        client.close(force: true);
        await t.runAsync(() => server.close(force: true));
        repo.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      try {
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(sample.$3)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PackReaderPage(
                        repository: repo,
                        entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
                        editTags: (_) async {},
                      ),
                    ),
                  ),
                  child: const Text('原媒体库'),
                ),
              ),
            ),
          ),
        );
        Future<void> until(bool Function() done) async {
          for (var i = 0; i < 180; i++) {
            await t.pump(const Duration(milliseconds: 40));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 3)),
            );
            expect(t.takeException(), isNull);
            if (done()) return;
          }
          fail('Last-image failure did not reach expected user-visible state');
        }

        await t.tap(find.text('原媒体库'));
        await until(() => find.text('跳过这一张').evaluate().length == 1);
        await t.ensureVisible(find.text('跳过这一张'));
        await t.pump(const Duration(milliseconds: 250));
        expect(requests, ['/p0/2']);
        expect(repo.openedCount, 0);
        if (sample.$1 == ReaderMode.horizontal && sample.$3 == 1) {
          await t.tap(find.text('沉浸'));
          await t.pump(const Duration(milliseconds: 250));
          expect(
            t.state<PackReaderPageState>(find.byType(PackReaderPage)).controls,
            isFalse,
          );
          await until(
            () => find.text('跳过这一张').hitTestable().evaluate().length == 1,
          );
        }
        await t.tap(find.text('跳过这一张').hitTestable());
        await until(
          () => find.text('已到本包末尾').hitTestable().evaluate().length == 1,
        );
        expect(find.text('跳过这一张'), findsNothing);
        final state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
        expect(state.controls, isTrue);
        expect(state.session.range!.pack!.id, 'p0');
        expect(state.session.index, 2);
        expect(repo.openedCount, 0);
        expect(repo.marks['p0']!.completed, isFalse);
        expect(repo.revisions, isEmpty);
        expect(requests.every((v) => v == '/p0/2'), isTrue);
        await t.tap(find.text('返回最后一张').hitTestable());
        await until(() => find.text('跳过这一张').evaluate().length == 1);
        await t.tap(find.byTooltip('下一张'));
        await until(() => find.text('跳过这一张').evaluate().isEmpty);
        expect(find.text('已到本包末尾').hitTestable(), findsOneWidget);
        expect(repo.openedCount, 0);
        expect(repo.revisions, isEmpty);
        await t.tap(find.text('返回来源').hitTestable());
        await until(() => find.byType(PackReaderPage).evaluate().isEmpty);
        expect(find.text('原媒体库'), findsOneWidget);
      } finally {
        debugNetworkImageHttpClientProvider = null;
        client.close(force: true);
      }
    });
  }
}
