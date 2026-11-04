import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/reader_images.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  for (final held in [true, false]) {
    testWidgets(
      '24 overview cells ${held ? 'cancel queued and active' : 'decode within capacity'}',
      (t) async {
        final previous = HttpOverrides.current;
        HttpOverrides.global = _RealHttp();
        final server = (await t.runAsync(
          () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        ))!;
        final bytes = File('assets/media/flower-portrait.jpg')
            .readAsBytesSync();
        final requests = <String>[];
        final sockets = <Socket>[];
        var live = 0, peak = 0, cancelled = 0, rejected = 0;
        server.listen((request) async {
          requests.add(request.uri.path);
          live++;
          if (live > peak) peak = live;
          if (held) {
            request.response.headers.contentType = ContentType('image', 'jpeg');
            request.response.contentLength = bytes.length;
            final socket = await request.response.detachSocket(
              writeHeaders: true,
            );
            sockets.add(socket);
            socket.listen(
              (_) {},
              onDone: () {
                live--;
                cancelled++;
              },
              onError: (Object _) {
                live--;
                cancelled++;
              },
            );
            socket.add(bytes.take(16).toList());
            await socket.flush();
          } else {
            if (live > 3) {
              rejected++;
              request.response.statusCode = 503;
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              request.response.headers.contentType = ContentType(
                'image',
                'jpeg',
              );
              request.response.add(bytes);
            }
            await request.response.close();
            live--;
          }
        });
        final images = ReaderImages();
        var active = true;
        late StateSetter update;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          images.dispose();
          for (final socket in sockets) {
            socket.destroy();
          }
          await t.runAsync(() => server.close(force: true));
        });
        Future<void> until(bool Function() ready, String why) async {
          for (var i = 0; i < 300; i++) {
            await t.pump(const Duration(milliseconds: 20));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            expect(t.takeException(), isNull);
            if (ready()) return;
          }
          fail('$why; requests=${requests.length}, live=$live, peak=$peak');
        }

        try {
          await t.pumpWidget(
            MaterialApp(
              home: StatefulBuilder(
                builder: (context, setter) {
                  update = setter;
                  return SingleChildScrollView(
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      children: [
                        for (var i = 0; i < 24; i++)
                          ReaderImage(
                            key: ValueKey(i),
                            page: ReaderPage(
                              id: 'page-$i',
                              packId: 'pack',
                              name: '$i.jpg',
                              ordinal: i,
                              width: 400,
                              height: 600,
                              version: 1,
                              image: const MediaSource('unused'),
                              thumbnail: MediaSource(
                                'http://127.0.0.1:${server.port}/$i',
                                asset: false,
                              ),
                            ),
                            images: images,
                            viewport: const Size(110, 150),
                            thumbnail: true,
                            active: active,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
          expect(find.byType(ReaderImage), findsNWidgets(24));
          if (held) {
            await until(() => requests.length >= 3, 'first leases');
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)),
            );
            expect(
              requests.length,
              3,
              reason: 'the remaining 21 cells wait without opening sockets',
            );
            expect(find.text('重试'), findsNothing);
            expect(
              find.text('加载中'),
              findsWidgets,
              reason: 'queued and active cells are loading, not failing',
            );
            update(() => active = false);
            await until(() => cancelled == 3, 'active transfers cancelled');
            await t.pump(const Duration(seconds: 4));
            expect(
              requests.length,
              3,
              reason: 'cancelled queued cells never reach the server',
            );
          } else {
            await until(
              () =>
                  find
                      .byType(RawImage)
                      .evaluate()
                      .where((e) => (e.widget as RawImage).image != null)
                      .length ==
                  24,
              'all 24 actual decodes',
            );
            expect(requests.toSet().length, 24);
            expect(requests.length, 24);
            expect(rejected, 0);
            expect(peak, lessThanOrEqualTo(3));
          }
        } finally {
          HttpOverrides.global = previous;
        }
      },
    );
  }
}
