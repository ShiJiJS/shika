import 'dart:async';
import 'dart:convert';
import 'dart:io';

const fixtureBase = 'http://10.0.2.2:8761';
const fixturePassword = 'video-viewer-emulator-fixture-only';
const fixtureKey = 'isolated-emulator-control';

Future<Map<String, dynamic>> fixture(
  String path, {
  String method = 'POST',
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    return await (() async {
      final request = await client.openUrl(
        method,
        Uri.parse('$fixtureBase$path'),
      );
      request.headers.set('X-Fixture-Key', fixtureKey);
      final response = await request.close();
      final value = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw StateError('Fixture ${response.statusCode}');
      }
      return jsonDecode(value) as Map<String, dynamic>;
    })().timeout(const Duration(seconds: 15));
  } on TimeoutException {
    throw const SocketException('Fixture response timed out');
  } finally {
    client.close(force: true);
  }
}
