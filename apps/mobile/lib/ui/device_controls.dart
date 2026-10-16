import 'package:flutter/services.dart';

class PlaybackDeviceControls {
  static const _channel = MethodChannel('video_viewer/playback');
  Future<Map<String, double>> levels() => _call('levels');
  Future<Map<String, double>> setBrightness(double value) =>
      _call('brightness', value);
  Future<Map<String, double>> setVolume(double value) => _call('volume', value);
  Future<void> restoreBrightness() =>
      _channel.invokeMethod('restoreBrightness');
  Future<Map<String, double>> _call(String method, [double? value]) async {
    final result = await _channel.invokeMapMethod<String, num>(
      method,
      value == null ? null : {'value': value},
    );
    return result!.map((key, value) => MapEntry(key, value.toDouble()));
  }
}
