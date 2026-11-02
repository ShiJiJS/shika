import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

Future<Map<String, dynamic>> probeControl(
  String path, {
  bool post = false,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      post ? 'POST' : 'GET',
      Uri.parse('http://10.0.2.2:8770$path'),
    );
    request.headers.set('X-Fixture-Key', 'owned-public-render-probe');
    final response = await request.close();
    expect(response.statusCode, 200);
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('same public asset through minimal video_player views', (
    t,
  ) async {
    VideoPlayerController? controller;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await controller?.dispose();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
    Future<void> until(
      FutureOr<bool> Function() condition,
      String reason,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while (!await condition()) {
        if (DateTime.now().isAfter(deadline)) fail('Render probe: $reason');
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
    }

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    for (final type in [
      VideoViewType.textureView,
      VideoViewType.platformView,
    ]) {
      final current = controller = VideoPlayerController.asset(
        'assets/media/flower-landscape.mp4',
        viewType: type,
      );
      await current.initialize();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: AspectRatio(
                aspectRatio: current.value.aspectRatio,
                child: VideoPlayer(current),
              ),
            ),
          ),
        ),
      );
      await until(
        () => t.view.physicalSize.width > t.view.physicalSize.height,
        'actual landscape',
      );
      await current.setLooping(false);
      await current.play();
      await current.seekTo(const Duration(seconds: 3));
      await until(
        () =>
            current.value.position.inMilliseconds >= 3000 &&
            current.value.isPlaying,
        'native time/playing',
      );
      await t.pump(const Duration(milliseconds: 300));
      await current.pause();
      await until(() => !current.value.isPlaying, 'native paused');
      await t.pump(const Duration(milliseconds: 300));
      debugPrint(
        'RENDER_PROBE:${jsonEncode({
          'view': type.name,
          'source': current.dataSource,
          'initialized': current.value.isInitialized,
          'position_ms': current.value.position.inMilliseconds,
          'playing': current.value.isPlaying,
          'size': [current.value.size.width, current.value.size.height],
          'physical': [t.view.physicalSize.width, t.view.physicalSize.height],
        })}',
      );
      await probeControl('/checkpoint/${type.name}', post: true);
      await until(
        () async => (await probeControl('/state'))['ack'] == true,
        'host screenshot ${type.name}',
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await current.dispose();
      controller = null;
    }
    debugPrint('RENDER_PROBE_VERIFIED');
  });
}
