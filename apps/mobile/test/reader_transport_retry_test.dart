import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

class _RealHttp extends HttpOverrides {}

class _TransportClient implements HttpClient {
  _TransportClient(this.inner, this.errors);
  final HttpClient inner;
  final List<Object> errors;
  int calls = 0;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    calls++;
    if (errors.isNotEmpty) throw errors.removeAt(0);
    return inner.getUrl(url);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final scenario in ['recover', 'bounded', 'dispose']) {
    testWidgets('reader transport retry $scenario keeps the actual page', (
      t,
    ) async {
      final server = await t.runAsync(
        () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      );
      final bytes = File('assets/media/flower-portrait.jpg').readAsBytesSync();
      server!.listen((request) async {
        request.response.persistentConnection = false;
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add(bytes);
        await request.response.close();
      });
      final client = _TransportClient(
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp()),
        [
          const SocketException('Synthetic temporary connection reset'),
          if (scenario != 'dispose')
            const HttpException(
              'Connection closed before full header was received',
            ),
          if (scenario == 'bounded')
            const SocketException('Synthetic still offline'),
        ],
      );
      debugNetworkImageHttpClientProvider = () => client;
      final repo = AssetReadingLibrary();
      repo.pageImage = (_, index) => index == 0
          ? MediaSource(
              'http://127.0.0.1:${server.port}/current.jpg',
              asset: false,
            )
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
        final retry = find.byKey(const Key('reader-image-retry-p0-0'));
        Future<void> until(bool Function() ready) async {
          for (var i = 0; i < 160; i++) {
            await t.pump(const Duration(milliseconds: 40));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 4)),
            );
            expect(t.takeException(), isNull);
            if (ready()) return;
          }
          fail(
            'Transport retry did not reach expected state; calls=${client.calls}',
          );
        }

        await until(() => retry.evaluate().isNotEmpty);
        expect(client.calls, 1);
        expect(repo.openedCount, 0);
        if (scenario == 'dispose') {
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 3));
          expect(client.calls, 1);
          expect(repo.openedCount, 0);
          return;
        }
        if (scenario == 'bounded') {
          await until(() => client.calls == 3 && retry.evaluate().isNotEmpty);
          await t.pump(const Duration(seconds: 3));
          expect(client.calls, 3);
          expect(repo.openedCount, 0);
          final state = t.state<PackReaderPageState>(
            find.byType(PackReaderPage),
          );
          expect(state.session.index, 0);
          expect(state.session.opened, isFalse);
          client.errors.clear();
          await t.tap(retry);
        }
        await until(() => repo.openedCount == 1);
        expect(client.calls, scenario == 'bounded' ? 4 : 3);
        expect(retry, findsNothing);
        final state = t.state<PackReaderPageState>(find.byType(PackReaderPage));
        expect(state.session.index, 0);
        expect(state.session.currentPage!.id, 'p0-0');
        expect(state.session.opened, isTrue);
      } finally {
        debugNetworkImageHttpClientProvider = null;
        client.close(force: true);
      }
    });
  }
}
