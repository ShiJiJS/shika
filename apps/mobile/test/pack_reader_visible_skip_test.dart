import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

class _VisibleHttp extends HttpOverrides {}

void main() {
  testWidgets(
    'visible failed last image skips while viewport remains on previous page',
    (t) async {
      final server = await t.runAsync(
        () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );
      server!.listen((request) async {
        request.response.statusCode = 404;
        request.response.persistentConnection = false;
        await request.response.close();
      });
      final client = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _VisibleHttp(),
      );
      debugNetworkImageHttpClientProvider = () => client;
      final repo = AssetReadingLibrary();
      repo.prefs['p0'] = const ReaderPreferences(mode: ReaderMode.vertical);
      repo.marks['p0'] = const ReaderMark('p0-1', offsetRatio: .8);
      repo.pageImage = (_, index) => index == 2
          ? MediaSource('http://127.0.0.1:${server.port}/last', asset: false)
          : const MediaSource('assets/media/flower-portrait.jpg', asset: true);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
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
            home: PackReaderPage(
              repository: repo,
              entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
              editTags: (_) async {},
            ),
          ),
        );
        final state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
        Future<void> until(bool Function() done) async {
          for (var i = 0; i < 180; i++) {
            await t.pump(const Duration(milliseconds: 40));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 3)),
            );
            expect(t.takeException(), isNull);
            if (done()) return;
          }
          fail(
            'Partial visible image did not reach expected state: index=${state.session.index}',
          );
        }

        final skip = find.byKey(const Key('reader-image-skip-p0-2'));
        await until(
          () =>
              state.session.opened &&
              !state.session.busy &&
              skip.hitTestable().evaluate().length == 1,
        );
        expect(state.session.index, 1);
        expect(state.session.offsetRatio, greaterThan(.7));
        await state.session.flush();
        final before = repo.marks['p0']!;
        final revision = Map<String, int>.of(repo.revisions);
        expect(before.pageId, 'p0-1');
        // Directly press the already visible last-image action. Do not scroll it.
        await t.tap(skip.hitTestable());
        await until(() => find.text('跳过这一张').evaluate().isEmpty);
        await t.pump(const Duration(seconds: 1));
        expect(find.text('已到本包末尾').hitTestable(), findsOneWidget);
        expect(state.session.index, 2);
        expect(state.session.range!.pack!.id, 'p0');
        expect(repo.marks['p0']!.pageId, before.pageId);
        expect(repo.marks['p0']!.offsetRatio, before.offsetRatio);
        expect(repo.marks['p0']!.completed, isFalse);
        expect(repo.revisions, revision);
        await t.tap(find.text('返回最后一张').hitTestable());
        await until(() => skip.hitTestable().evaluate().length == 1);
        expect(state.session.index, 2);
        expect(repo.marks['p0']!.pageId, 'p0-1');
      } finally {
        debugNetworkImageHttpClientProvider = null;
        client.close(force: true);
      }
    },
  );
}
