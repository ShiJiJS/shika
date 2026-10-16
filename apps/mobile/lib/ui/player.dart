import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../library/models.dart';
import 'paper.dart';

class MovieStage extends StatefulWidget {
  const MovieStage({
    super.key,
    required this.videos,
    required this.index,
    required this.onStep,
    this.suspended = false,
  });
  final List<LibraryVideo> videos;
  final int index;
  final Future<bool> Function(int) onStep;
  final bool suspended;
  @override
  State<MovieStage> createState() => _MovieStageState();
}

class _MovieStageState extends State<MovieStage> {
  late final PageController _pages = PageController(initialPage: widget.index);
  bool _changing = false;
  double _edgeDrag = 0;

  @override
  void didUpdateWidget(MovieStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roundChanged = !listEquals(
      oldWidget.videos.map((v) => v.id).toList(),
      widget.videos.map((v) => v.id).toList(),
    );
    if (roundChanged || (!_changing && oldWidget.index != widget.index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(widget.index);
      });
    }
  }

  Future<void> _settle() async {
    if (_changing ||
        !_pages.hasClients ||
        widget.suspended ||
        _pages.position.isScrollingNotifier.value) {
      return;
    }
    final target = _pages.page!.round();
    final delta = target - widget.index;
    final atEnd = _edgeDrag > 45 && target == widget.videos.length - 1;
    _edgeDrag = 0;
    if (delta == 0 && !atEnd) return;
    setState(() => _changing = true);
    try {
      await widget.onStep(delta == 0 ? 1 : delta);
      // The repository publishes only after saving. A failed save must slide
      // back to the original video rather than leave the visible page ahead.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_pages.hasClients) return;
      if ((_pages.page! - widget.index).abs() > .001) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _pages.jumpToPage(widget.index);
        } else {
          await _pages.animateToPage(
            widget.index,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification) _edgeDrag = 0;
          if (notification is OverscrollNotification &&
              notification.dragDetails != null) {
            _edgeDrag += notification.overscroll;
          }
          if (notification is ScrollEndNotification) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_settle());
            });
          }
          return false;
        },
        child: PageView.builder(
          key: const Key('video-stage'),
          controller: _pages,
          scrollDirection: Axis.vertical,
          allowImplicitScrolling: true,
          physics: _changing || widget.suspended
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(parent: ClampingScrollPhysics()),
          itemCount: widget.videos.length,
          findChildIndexCallback: (key) {
            final index = widget.videos.indexWhere(
              (v) => ValueKey(v.id) == key,
            );
            return index < 0 ? null : index;
          },
          itemBuilder: (context, index) => _MoviePage(
            key: ValueKey(widget.videos[index].id),
            video: widget.videos[index],
            active: index == widget.index,
            suspended: widget.suspended,
          ),
        ),
      );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }
}

class _MoviePage extends StatefulWidget {
  const _MoviePage({
    super.key,
    required this.video,
    required this.active,
    required this.suspended,
  });
  final LibraryVideo video;
  final bool active, suspended;

  @override
  State<_MoviePage> createState() => _MoviePageState();
}

class _MoviePageState extends State<_MoviePage> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  int _generation = 0;
  String? _error;
  bool _wide = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_MoviePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      unawaited(_load());
    } else if (!widget.active || widget.suspended) {
      unawaited(_controller?.pause());
    } else if (!oldWidget.active &&
        widget.active &&
        _controller?.value.isInitialized == true) {
      unawaited(_controller?.seekTo(Duration.zero));
      unawaited(_controller?.play());
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
      if (widget.active && !widget.suspended) await next.play();
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
    setState(() => _wide = true);
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
      if (mounted) setState(() => _wide = false);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xffe6e4db),
    child: Stack(
      children: [
        Positioned.fill(
          child: !widget.active
              ? Image.asset(widget.video.poster, fit: BoxFit.contain)
              : _error != null
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
                  interactionsEnabled: !widget.suspended && !_wide,
                ),
        ),
        if (widget.active &&
            !widget.video.portrait &&
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

class PlayerSurface extends StatefulWidget {
  const PlayerSurface({
    super.key,
    required this.controller,
    required this.name,
    this.interactionsEnabled = true,
  });
  final VideoPlayerController controller;
  final String name;
  final bool interactionsEnabled;
  @override
  State<PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<PlayerSurface>
    with WidgetsBindingObserver {
  double? _previousSpeed;
  Future<void> _speedChanges = Future.value();
  VideoPlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _setSpeed(double speed) {
    final player = controller;
    _speedChanges = _speedChanges
        .then((_) async {
          if (player.value.isInitialized) await player.setPlaybackSpeed(speed);
        })
        .catchError((Object _) {
          // Leaving a page can dispose the native player before a queued restore.
        });
  }

  void _startBoost() {
    if (!widget.interactionsEnabled ||
        !controller.value.isPlaying ||
        _previousSpeed != null) {
      return;
    }
    setState(() => _previousSpeed = controller.value.playbackSpeed);
    _setSpeed(2);
  }

  void _endBoost() {
    final previous = _previousSpeed;
    if (previous == null) return;
    _previousSpeed = null;
    _setSpeed(previous);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.interactionsEnabled) _endBoost();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _endBoost();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final previous = _previousSpeed;
    if (previous != null) _setSpeed(previous);
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, v, _) {
      if (v.hasError) return const EmptyView('视频播放失败，可上下滑动继续查看');
      return Semantics(
        label: widget.name,
        value: '${v.isPlaying ? '正在播放' : '已暂停'}，${v.playbackSpeed}倍速',
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerCancel: (_) => _endBoost(),
                child: GestureDetector(
                  key: const Key('video-gesture-surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: !widget.interactionsEnabled
                      ? null
                      : () => v.isPlaying
                            ? controller.pause()
                            : controller.play(),
                  onLongPressStart: !widget.interactionsEnabled
                      ? null
                      : (_) => _startBoost(),
                  onLongPressEnd: (_) => _endBoost(),
                  onLongPressCancel: _endBoost,
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
            ),
            if (_previousSpeed != null)
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      key: const Key('hold-speed-hint'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xa6132217),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '2× 快进中',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
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
