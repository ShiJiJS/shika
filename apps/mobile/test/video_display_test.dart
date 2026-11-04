import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/models.dart';

void main() {
  LibraryVideo video(String name, [int seconds = 5]) => LibraryVideo(
    id: 'stable-id',
    path: '/media/$name',
    rootId: 'root',
    portrait: false,
    source: const MediaSource('assets/media/flower-landscape.mp4'),
    poster: '',
    seconds: seconds,
  );
  test('display caption hides only a known final video extension without changing identity', () {
    for (final name in ['风里的花园.mp4', '风里的花园.MOV', '风里的花园.webm']) {
      final v = video(name);
      expect(v.displayTitle, '风里的花园');
      expect(v.name, name);
      expect(v.path, '/media/$name');
      expect(LibraryVideo.fromJson(v.toJson()).path, v.path);
      expect(v.id, 'stable-id');
    }
    expect(video('一.二.mp4').displayTitle, '一.二');
    for (final name in ['.mp4', '未知.mpeg', '无扩展名', '风里的花园.mp4.bak']) {
      expect(video(name).displayTitle, name);
    }
  });
  test('duration caption uses the same whole seconds as the player', () {
    expect(video('a.mp4', 0).durationLabel, '0:00');
    expect(video('a.mp4', 5).durationLabel, '0:05');
    expect(video('a.mp4', 65).durationLabel, '1:05');
    expect(video('a.mp4', 3605).durationLabel, '60:05');
  });
}
