import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../library/models.dart';
import 'paper.dart';

class MovieStage extends StatefulWidget {
  const MovieStage({
    super.key,
    required this.video,
    required this.onStep,
    this.suspended = false,
  });
  final LibraryVideo video;
  final void Function(int) onStep;
  final bool suspended;
  @override
  State<MovieStage> createState() => _MovieStageState();
}

class _MovieStageState extends State<MovieStage> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  int _generation = 0;
  String? _error;
  double _drag = 0;
  bool _wide = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MovieStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      unawaited(_load());
    } else if (widget.suspended && !oldWidget.suspended) {
      unawaited(_controller?.pause());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller?.pause());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final old = _controller;
    _controller = null;
    _error = null;
    if (mounted) setState(() {});
    await old?.dispose();
    if (!mounted || generation != _generation) return;
    final source = widget.video.source;
    final next = source.asset
        ? VideoPlayerController.asset(source.location)
        : VideoPlayerController.networkUrl(
            Uri.parse(source.location),
            httpHeaders: source.headers,
          );
    _controller = next;
    try {
      await next.initialize();
      if (!mounted || generation != _generation) return;
      await next.setLooping(true);
      await next.seekTo(Duration.zero);
      if (!widget.suspended) await next.play();
      if (mounted && generation == _generation) setState(() {});
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '这段视频暂时无法播放');
      }
    }
  }

  Future<void> _fullscreen() async {
    final player = _controller;
    if (player == null || !player.value.isInitialized || _wide) return;
    _wide = true;
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(
                  child: PlayerSurface(
                    controller: player,
                    name: widget.video.name,
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.fullscreen_exit),
                        label: const Text('返回'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _wide = false;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('video-stage'),
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: (_) => _drag = 0,
    onVerticalDragUpdate: (d) => _drag += d.delta.dy,
    onVerticalDragEnd: (_) {
      if (_drag.abs() > 45) widget.onStep(_drag < 0 ? 1 : -1);
    },
    child: ColoredBox(
      color: const Color(0xffe6e4db),
      child: Stack(
        children: [
          Positioned.fill(
            child: _error != null
                ? EmptyView(
                    _error!,
                    action: OutlinedButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  )
                : _controller == null || !_controller!.value.isInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(widget.video.poster, fit: BoxFit.contain),
                      const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  )
                : PlayerSurface(
                    controller: _controller!,
                    name: widget.video.name,
                  ),
          ),
          if (!widget.video.portrait &&
              _controller?.value.isInitialized == true)
            Positioned(
              right: 14,
              bottom: 76,
              child: FilledButton.tonalIcon(
                onPressed: _fullscreen,
                icon: const Icon(Icons.screen_rotation, size: 17),
                label: const Text('横屏'),
              ),
            ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }
}

String timeLabel(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class PlayerSurface extends StatelessWidget {
  const PlayerSurface({
    super.key,
    required this.controller,
    required this.name,
  });
  final VideoPlayerController controller;
  final String name;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, v, _) {
      if (v.hasError) return const EmptyView('视频播放失败，可上下滑动继续查看');
      return Semantics(
        label: name,
        value: v.isPlaying ? '正在播放' : '已暂停',
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () =>
                    v.isPlaying ? controller.pause() : controller.play(),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: v.aspectRatio,
                    child: VideoPlayer(
                      controller,
                      key: const Key('actual-video'),
                    ),
                  ),
                ),
              ),
            ),
            if (!v.isPlaying)
              Center(
                child: IgnorePointer(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x8017221c),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 31,
                    ),
                  ),
                ),
              ),
            if (!v.isPlaying)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 3),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xa6132217)],
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${timeLabel(v.position)} / ${timeLabel(v.duration)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontFamily: 'serif',
                            ),
                          ),
                          PopupMenuButton<double>(
                            tooltip: '播放速度',
                            initialValue: v.playbackSpeed,
                            onSelected: controller.setPlaybackSpeed,
                            itemBuilder: (_) => [.5, 1.0, 1.5, 2.0]
                                .map(
                                  (s) => PopupMenuItem(
                                    value: s,
                                    child: Text('$s×'),
                                  ),
                                )
                                .toList(),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                '${v.playbackSpeed}×',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 4,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                        ),
                        child: Slider(
                          key: const Key('video-progress'),
                          activeColor: Paper.background,
                          inactiveColor: Colors.white54,
                          min: 0,
                          max: maxDuration(v.duration),
                          value: v.position.inMilliseconds.toDouble().clamp(
                            0,
                            maxDuration(v.duration),
                          ),
                          onChanged: (x) => controller.seekTo(
                            Duration(milliseconds: x.round()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
  double maxDuration(Duration d) =>
      d.inMilliseconds > 0 ? d.inMilliseconds.toDouble() : 1;
}
