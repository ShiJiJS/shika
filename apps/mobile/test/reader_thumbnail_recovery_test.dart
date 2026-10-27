import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/features/packs/reader_images.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'pack_reader_widget_test.dart' show AssetReadingLibrary;

class _RealHttp extends HttpOverrides {}

void main() {
  identityTests();
  for (final scenario in [
    'recover',
    'bounded',
    'close-timer',
    'close-request',
    'manual',
    'unauthorized',
  ]) {
    testWidgets(
      'overview thumbnail $scenario preserves reader and cancels work',
      (t) async {
        final server = (await t.runAsync(
          () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        ))!;
        final bytes = File('assets/media/flower-portrait.jpg')
            .readAsBytesSync();
        final client = HttpOverrides.runWithHttpOverrides(
          () => HttpClient(),
          _RealHttp(),
        );
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = _RealHttp();
        debugNetworkImageHttpClientProvider = () => client;
        final requests = <String>[];
        final held = Completer<void>();
        var disconnected = false, healthy = false;
        server.listen((request) async {
          requests.add(request.uri.path);
          final n = requests.length;
          request.response.persistentConnection = false;
          if (scenario == 'close-request') {
            request.response.headers.contentType = ContentType('image', 'jpeg');
            request.response.contentLength = bytes.length;
            final socket = await request.response.detachSocket(
              writeHeaders: true,
            );
            socket.listen(
              (_) {},
              onDone: () {
                disconnected = true;
              },
              onError: (Object _) {
                disconnected = true;
              },
            );
            socket.add(bytes.take(16).toList());
            await socket.flush();
            await held.future;
            socket.destroy();
            return;
          }
          request.response.statusCode = scenario == 'unauthorized'
              ? 401
              : healthy || (scenario == 'recover' && n >= 3)
              ? 200
              : 503;
          if (request.response.statusCode == 200) {
            request.response.headers.contentType = ContentType('image', 'jpeg');
            request.response.add(bytes);
          }
          await request.response.close();
        });
        final repo = AssetReadingLibrary();
        repo.pageThumbnail = (_, index) => index == 0
            ? MediaSource('http://127.0.0.1:${server.port}/thumb', asset: false)
            : const MediaSource(
                'assets/media/flower-portrait.jpg',
                asset: true,
              );
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(390, 844);
        addTearDown(() async {
          if (!held.isCompleted) held.complete();
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
          Future<void> until(bool Function() ready, String why) async {
            for (var i = 0; i < 250; i++) {
              await t.pump(const Duration(milliseconds: 20));
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 4)),
              );
              expect(t.takeException(), isNull);
              if (ready()) return;
            }
            fail('$why; requests=$requests');
          }

          final state = t.state<PackReaderPageState>(
            find.byType(PackReaderPage),
          );
          await until(() => state.session.opened, 'main image opens');
          await t.pumpAndSettle();
          final marks = Map.of(repo.marks),
              revisions = Map.of(repo.revisions),
              opened = repo.openedCount;
          final range = state.session.range!.id,
              page = state.session.currentPage!.id,
              mode = state.session.preferences.mode;
          unawaited(state.overview());
          final sheet = find.byKey(const Key('reader-overview-sheet'));
          final retry = find.descendant(
            of: sheet,
            matching: find.byKey(const Key('reader-image-retry-p0-0')),
          );
          await until(
            () =>
                requests.isNotEmpty &&
                (scenario == 'close-request' || retry.evaluate().isNotEmpty),
            'first failure/request',
          );
          if (scenario.startsWith('close-')) {
            Navigator.of(t.element(sheet)).pop();
            await t.pump(const Duration(milliseconds: 10));
            if (scenario == 'close-request') {
              await until(
                () => disconnected,
                'in-flight thumbnail socket cancelled while body pending',
              );
            }
            await t.pumpAndSettle();
            await t.pump(const Duration(seconds: 3));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            expect(requests.length, 1);
          } else if (scenario == 'unauthorized') {
            await t.pump(const Duration(seconds: 5));
            expect(requests.length, 1);
          } else {
            if (scenario == 'manual') {
              healthy = true;
              await t.tap(retry);
              await until(
                () => retry.evaluate().isEmpty && requests.length == 2,
                'manual retry succeeds',
              );
              await t.pump(const Duration(seconds: 3));
              expect(
                requests.length,
                2,
                reason: 'manual retry consumes the pending automatic timer',
              );
            } else {
              await until(() => requests.length == 3, 'two bounded retries');
              if (scenario == 'bounded') {
                await until(
                  () => retry.evaluate().isNotEmpty,
                  'exhausted retry visible',
                );
                await t.pump(const Duration(seconds: 5));
                expect(requests.length, 3);
                healthy = true;
                await t.tap(retry);
                await until(
                  () => requests.length == 4 && retry.evaluate().isEmpty,
                  'manual recovery after exhaustion',
                );
              } else {
                await until(
                  () => retry.evaluate().isEmpty,
                  'automatic recovery',
                );
              }
            }
            await until(
              () =>
                  find
                      .descendant(of: sheet, matching: find.byType(RawImage))
                      .evaluate()
                      .where((e) => (e.widget as RawImage).image != null)
                      .length ==
                  3,
              'three actual decoded thumbnails',
            );
          }
          expect(state.session.range!.id, range);
          expect(state.session.currentPage!.id, page);
          expect(state.session.preferences.mode, mode);
          expect(repo.openedCount, opened);
          expect(repo.marks, marks);
          expect(repo.revisions, revisions);
        } finally {
          debugNetworkImageHttpClientProvider = null;
          HttpOverrides.global = previousOverrides;
        }
      },
    );
  }
}

void identityTests() {
  for (final change in ['url', 'headers', 'version', 'pack']) {
    testWidgets(
      'overview replaces in-flight $change identity without stale pixels',
      (t) async {
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = _RealHttp();
        final server = (await t.runAsync(
          () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        ))!;
        final bytes = File('assets/media/flower-portrait.jpg')
            .readAsBytesSync();
        final requests = <(String, String?)>[];
        var disconnected = false;
        final held = Completer<void>();
        server.listen((request) async {
          requests.add((
            request.uri.path,
            request.headers.value('Authorization'),
          ));
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.contentLength = bytes.length;
          if (requests.length == 1) {
            final socket = await request.response.detachSocket(
              writeHeaders: true,
            );
            socket.listen(
              (_) {},
              onDone: () {
                disconnected = true;
              },
              onError: (Object _) {
                disconnected = true;
              },
            );
            socket.add(bytes.take(16).toList());
            await socket.flush();
            await held.future;
            socket.destroy();
          } else {
            request.response.add(bytes);
            await request.response.close();
          }
        });
        final images = ReaderImages();
        var next = false;
        late StateSetter update;
        ReaderPage page() => ReaderPage(
          id: 'same-page',
          packId: next && change == 'pack' ? 'new-pack' : 'old-pack',
          name: '1.jpg',
          ordinal: 0,
          width: 400,
          height: 600,
          version: next && change == 'version' ? 2 : 1,
          image: const MediaSource('assets/media/flower-portrait.jpg'),
          thumbnail: MediaSource(
            'http://127.0.0.1:${server.port}/${next && change == 'url' ? 'new' : 'old'}',
            asset: false,
            headers: {
              'Authorization': next && change == 'headers'
                  ? 'Bearer new'
                  : 'Bearer old',
            },
          ),
        );
        addTearDown(() async {
          if (!held.isCompleted) held.complete();
          await t.pumpWidget(const SizedBox());
          await t.pump();
          images.dispose();
          await t.runAsync(() => server.close(force: true));
        });
        Future<void> until(bool Function() ready, String why) async {
          for (var i = 0; i < 250; i++) {
            await t.pump(const Duration(milliseconds: 20));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 4)),
            );
            expect(t.takeException(), isNull);
            if (ready()) return;
          }
          fail('$why; requests=$requests');
        }

        try {
          await t.pumpWidget(
            MaterialApp(
              home: StatefulBuilder(
                builder: (context, setter) {
                  update = setter;
                  return Center(
                    child: SizedBox(
                      width: 110,
                      height: 150,
                      child: ReaderImage(
                        key: const Key('same-cell'),
                        page: page(),
                        images: images,
                        viewport: const Size(110, 150),
                        thumbnail: true,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await until(() => requests.length == 1, 'first pending response');
          update(() => next = true);
          await until(
            () =>
                disconnected &&
                requests.length == 2 &&
                find
                    .byType(RawImage)
                    .evaluate()
                    .any((e) => (e.widget as RawImage).image != null),
            'old response cancelled and replacement decoded',
          );
          expect(requests[1], (
            change == 'url' ? '/new' : '/old',
            change == 'headers' ? 'Bearer new' : 'Bearer old',
          ));
          await t.pump(const Duration(seconds: 5));
          expect(requests.length, 2);
        } finally {
          HttpOverrides.global = previousOverrides;
        }
      },
    );
  }
}
