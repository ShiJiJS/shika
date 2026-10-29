import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../library/models.dart';
import 'paper.dart';
import 'media_layout.dart';
import 'paper_icons.dart';
import 'device_controls.dart';
import 'media_poster.dart';
import 'playback_session.dart';

class MovieStage extends StatefulWidget {
  const MovieStage({
    super.key,
    required this.videos,
    required this.index,
    required this.onStep,
    this.suspended = false,
    this.footerBuilder,
    this.onUnauthorized,
    this.preloadAdjacent = true,
    this.onPlaybackFailure,
    this.session,
    this.inlineControls = false,
  });
  final List<LibraryVideo> videos;
  final int index;
  final Future<bool> Function(int) onStep;
  final bool suspended;
  final Widget Function(LibraryVideo)? footerBuilder;
  final void Function(MediaSource)? onUnauthorized;
  final bool preloadAdjacent;
  final Future<String?> Function(LibraryVideo)? onPlaybackFailure;
  final PlaybackSession? session;
  final bool inlineControls;
  @override
  State<MovieStage> createState() => _MovieStageState();
}

class _MovieStageState extends State<MovieStage> {
  late final _session = widget.session ?? PlaybackSession();
  late final PageController _pages = PageController(initialPage: widget.index);
  bool _changing = false;
  int _transition = 0;
  double _edgeDrag = 0;
  final Set<String> _posters = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefetchPosters();
  }

  void _prefetchPosters() {
    for (final video
        in widget.videos
            .skip((widget.index - 1).clamp(0, widget.videos.length))
            .take(9)) {
      if (video.poster.isEmpty || !_posters.add(video.poster)) continue;
      final ImageProvider provider = video.source.asset
          ? AssetImage(video.poster)
          : NetworkImage(video.poster, headers: video.source.headers);
      unawaited(
        precacheImage(
          provider,
          context,
          onError: (Object error, StackTrace? stack) {},
        ),
      );
    }
    if (_posters.length > 96) _posters.clear();
  }

  @override
  void didUpdateWidget(MovieStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prefetchPosters();
    final roundChanged = !listEquals(
      oldWidget.videos.map((v) => v.id).toList(),
      widget.videos.map((v) => v.id).toList(),
    );
    if (roundChanged || (!_changing && oldWidget.index != widget.index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _pages.hasClients &&
            !_pages.position.isScrollingNotifier.value &&
            (_pages.page! - widget.index).abs() > .001) {
          _pages.jumpToPage(widget.index);
        }
      });
    }
  }

  Future<void> _settle() async {
    if (!_pages.hasClients ||
        widget.suspended ||
        _pages.position.isScrollingNotifier.value) {
      return;
    }
    final target = _pages.page!.round();
    final delta = target - widget.index;
    final atEnd = _edgeDrag > 45 && target == widget.videos.length - 1;
    _edgeDrag = 0;
    if (delta == 0 && !atEnd) return;
    final transition = ++_transition;
    setState(() => _changing = true);
    try {
      await widget.onStep(delta == 0 ? 1 : delta);
      // The visible selection is published immediately; network persistence
      // and decoder initialization do not own the scroll gesture.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !_pages.hasClients ||
          transition != _transition ||
          _pages.position.isScrollingNotifier.value) {
        return;
      }
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
      if (mounted && transition == _transition) {
        setState(() => _changing = false);
      }
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
          physics: widget.suspended
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                ),
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
            prepare:
                index == widget.index ||
                (widget.preloadAdjacent && (index - widget.index).abs() <= 1),
            session: _session,
            suspended: widget.suspended,
            footer: widget.footerBuilder?.call(widget.videos[index]),
            onUnauthorized: widget.onUnauthorized,
            onPlaybackFailure: widget.onPlaybackFailure,
            inlineControls: widget.inlineControls,
          ),
        ),
      );

  @override
  void dispose() {
    _pages.dispose();
    if (widget.session == null) unawaited(_session.close());
    super.dispose();
  }
}

class _MoviePage extends StatefulWidget {
  const _MoviePage({
    super.key,
    required this.video,
    required this.active,
    required this.prepare,
    required this.session,
    required this.suspended,
    this.footer,
    this.onUnauthorized,
    this.onPlaybackFailure,
    this.inlineControls = false,
  });
  final LibraryVideo video;
  final bool active, suspended;
  final bool prepare;
  final PlaybackSession session;
  final Widget? footer;
  final void Function(MediaSource)? onUnauthorized;
  final Future<String?> Function(LibraryVideo)? onPlaybackFailure;
  final bool inlineControls;

  @override
  State<_MoviePage> createState() => _MoviePageState();
}

class _MoviePageState extends State<_MoviePage> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  int _generation = 0;
  String? _error;
  bool _wide = false;
  bool _resumeAfterSuspension = false;
  bool _foreground = true;
  bool _loading = false;
  bool _playRequested = false;
  bool? _orientationPlayIntent;
  double _baseSpeed = 1;
  final _screenRevision = ValueNotifier(0);
  PaperPageRoute<void>? _fullscreenRoute;
  NavigatorState? _fullscreenNavigator;
  Completer<void>? _initializationCancelled;

  void _cancelInitialization() {
    final pending = _initializationCancelled;
    _initializationCancelled = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<void> _initialize(
    VideoPlayerController controller,
    Duration limit,
  ) async {
    final cancelled = _initializationCancelled = Completer<void>();
    final expired = Completer<void>();
    final timer = Timer(
      limit,
      () => expired.completeError(
        TimeoutException('Video initialization timed out', limit),
      ),
    );
    try {
      await Future.any([
        controller.initialize(),
        cancelled.future,
        expired.future,
      ]);
    } finally {
      timer.cancel();
      if (identical(_initializationCancelled, cancelled)) {
        _initializationCancelled = null;
      }
    }
  }

  void _repaint() {
    if (!mounted) return;
    setState(() {});
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _screenRevision.value++;
      });
    } else {
      _screenRevision.value++;
    }
  }

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_MoviePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id ||
        oldWidget.video.source.location != widget.video.source.location ||
        !mapEquals(
          oldWidget.video.source.headers,
          widget.video.source.headers,
        )) {
      unawaited(_load());
    } else if (!widget.prepare) {
      _unload();
    } else if (!oldWidget.prepare ||
        (!oldWidget.active && widget.active && _error != null) ||
        (!_loading &&
            _error == null &&
            (_controller == null ||
                (widget.active && !widget.session.contains(_controller!))))) {
      unawaited(_load());
    } else if (!widget.active || widget.suspended) {
      if (widget.active &&
          widget.suspended &&
          (!oldWidget.active || !oldWidget.suspended)) {
        // Picking another item while a queue covers the stage requests play
        // once it closes; reopening the current item preserves its pause.
        _resumeAfterSuspension = !oldWidget.active || _playRequested;
      }
      _playRequested = false;
      unawaited(widget.session.silence(_controller));
    } else if ((!oldWidget.active ||
            (oldWidget.suspended && _resumeAfterSuspension)) &&
        _controller?.value.isInitialized == true) {
      unawaited(_activate(rewind: !oldWidget.active));
      _resumeAfterSuspension = false;
    }
  }

  Future<void> _activate({required bool rewind, bool play = true}) async {
    final player = _controller, generation = _generation;
    if (player == null) return;
    _playRequested = play;
    _loading = true;
    _repaint();
    try {
      await widget.session.select(
        player,
        valid: () =>
            mounted &&
            generation == _generation &&
            widget.active &&
            !widget.suspended &&
            _foreground,
        rewind: rewind,
        play: play,
      );
    } finally {
      if (mounted && generation == _generation) {
        _loading = false;
        _repaint();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _orientationPlayIntent = null;
    }
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _resumeAfterSuspension = false;
      // Rotation can briefly remove focus. Keep its decoder and timeline until
      // a real hidden/paused transition requires network resource release.
      if (widget.video.source.asset ||
          (state == AppLifecycleState.inactive &&
              _orientationPlayIntent != null)) {
        _playRequested = false;
        unawaited(widget.session.silence(_controller));
        _repaint();
      } else {
        _unload();
      }
    } else {
      final playing = _orientationPlayIntent ?? false;
      _orientationPlayIntent = null;
      if (_controller == null && widget.prepare) {
        unawaited(_load(autoplay: playing));
      } else if (widget.active && !widget.suspended && _controller != null) {
        unawaited(_activate(rewind: false, play: playing));
      }
    }
  }

  void _unload() {
    _cancelInitialization();
    ++_generation;
    _loading = false;
    _playRequested = false;
    final old = _controller;
    _controller = null;
    unawaited(widget.session.release(old));
    _repaint();
  }

  Future<void> _load({
    bool autoplay = true,
    int emptyTrackRetry = 0,
    int transientRetry = 0,
  }) async {
    _cancelInitialization();
    final generation = ++_generation;
    _loading = true;
    _playRequested = autoplay && widget.active && !widget.suspended;
    _resumeAfterSuspension = autoplay && widget.active && widget.suspended;
    final old = _controller;
    _controller = null;
    _error = null;
    _repaint();
    await widget.session.release(old);
    if (!mounted ||
        generation != _generation ||
        !widget.prepare ||
        !_foreground) {
      if (generation == _generation) _loading = false;
      return;
    }
    final source = widget.video.source;
    // This page owns lifecycle handling; the plugin must not resume independently.
    final options = VideoPlayerOptions(allowBackgroundPlayback: true);
    final next = source.asset
        ? VideoPlayerController.asset(
            source.location,
            videoPlayerOptions: options,
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(source.location),
            httpHeaders: source.headers,
            videoPlayerOptions: options,
          );
    _controller = next;
    var initialized = false, failureHandled = false;
    next.addListener(() {
      if (initialized &&
          !failureHandled &&
          next.value.hasError &&
          mounted &&
          generation == _generation) {
        failureHandled = true;
        unawaited(
          _failure(next, generation, failure: next.value.errorDescription),
        );
      }
    });
    try {
      if (!await widget.session.attach(next, current: widget.active)) return;
      if (!mounted ||
          generation != _generation ||
          !widget.session.contains(next)) {
        await widget.session.release(next);
        return;
      }
      await _initialize(next, Duration(seconds: widget.active ? 30 : 20));
      if (!mounted ||
          generation != _generation ||
          !widget.session.contains(next)) {
        return;
      }
      if (next.value.size.isEmpty) {
        // A native ready event can still have no video dimensions. Recreate
        // once, releasing this decoder first; audio-only success is not video.
        if (emptyTrackRetry == 0 && widget.prepare && _foreground) {
          await _load(
            autoplay: autoplay,
            emptyTrackRetry: 1,
            transientRetry: transientRetry,
          );
          return;
        }
        throw UnsupportedError('No decoded video track');
      }
      initialized = true;
      await next.setVolume(0);
      await next.setLooping(true);
      await next.setPlaybackSpeed(_baseSpeed);
      await next.seekTo(Duration.zero);
      if (widget.active && !widget.suspended) {
        await widget.session.select(
          next,
          valid: () =>
              mounted &&
              generation == _generation &&
              widget.active &&
              !widget.suspended &&
              _foreground,
          play: autoplay,
        );
      }
    } catch (error) {
      final description = error.toString().toLowerCase();
      final transient =
          error is TimeoutException ||
          [
            'source error',
            '503',
            '502',
            '504',
            'socketexception',
            'connection reset',
            'connection timed out',
          ].any(description.contains);
      if (!failureHandled &&
          transient &&
          transientRetry == 0 &&
          mounted &&
          generation == _generation &&
          widget.active &&
          widget.prepare &&
          _foreground) {
        // A NAS may still be reading ahead or releasing an older HTTP Range.
        // Release before one bounded retry; stale pages never start a decoder.
        _controller = null;
        await widget.session.release(next);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted &&
            generation == _generation &&
            widget.active &&
            widget.prepare &&
            _foreground) {
          await _load(
            autoplay: autoplay,
            emptyTrackRetry: emptyTrackRetry,
            transientRetry: 1,
          );
        }
        return;
      }
      if (!failureHandled) {
        failureHandled = true;
        await _failure(next, generation, failure: error);
      }
    } finally {
      if (generation == _generation) {
        _loading = false;
        _repaint();
      }
    }
  }

  Future<void> _failure(
    VideoPlayerController player,
    int generation, {
    Object? failure,
  }) async {
    if (mounted && generation == _generation) {
      _controller = null;
      _loading = false;
      _playRequested = false;
      _error = failure is TimeoutException
          ? '视频加载较慢，请重试或上下滑动继续查看'
          : failure is UnsupportedError
          ? '当前设备无法解码这段视频，可上下滑动继续查看'
          : '这段视频暂时无法播放，可上下滑动继续查看';
      _repaint();
    }
    await widget.session.release(player);
    String? message;
    if (mounted && generation == _generation && widget.active) {
      try {
        message = await widget.onPlaybackFailure?.call(widget.video);
      } catch (_) {
        // A superseded probe must not change the new page or session.
      }
    }
    if (failure is TimeoutException && message == null) {
      message = '视频加载较慢，请重试或上下滑动继续查看';
    }
    if (failure is UnsupportedError && message == null) {
      message = '当前设备无法解码这段视频，可上下滑动继续查看';
    }
    if (mounted && generation == _generation) {
      _playRequested = false;
      _error = message ?? _error;
      _repaint();
    }
  }

  Future<void> _fullscreen() async {
    final player = _controller;
    if (player == null || !player.value.isInitialized || _wide) return;
    _orientationPlayIntent = _playRequested;
    setState(() => _wide = true);
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      final navigator = _fullscreenNavigator = Navigator.of(context);
      final route = _fullscreenRoute = PaperPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: widget.inlineControls
              ? const Color(0xff111612)
              : Colors.black,
          body: ValueListenableBuilder<int>(
            valueListenable: _screenRevision,
            builder: (context, _, _) {
              final current = _controller;
              if (_error == null &&
                  current != null &&
                  widget.session.contains(current) &&
                  current.value.isInitialized &&
                  !current.value.size.isEmpty &&
                  !_loading) {
                return PlayerSurface(
                  controller: current,
                  name: widget.video.name,
                  fullscreen: true,
                  inlineControls: widget.inlineControls,
                  onExit: () {
                    _orientationPlayIntent = _playRequested;
                    Navigator.pop(context);
                  },
                  onSpeedChanged: (speed) => _baseSpeed = speed,
                  isPlayRequested: () => _playRequested,
                  onPlayRequested: _changePlayRequest,
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  MediaPoster(
                    video: widget.video,
                    fit: BoxFit.contain,
                    onUnauthorized: () =>
                        widget.onUnauthorized?.call(widget.video.source),
                  ),
                  Center(
                    child: _error == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              TextButton(
                                onPressed: _load,
                                child: const Text(
                                  '重试',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Positioned(
                    top: 6,
                    left: 8,
                    child: SafeArea(
                      bottom: false,
                      child: IconButton(
                        key: const Key('fullscreen-exit'),
                        tooltip: '退出全屏',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await navigator.push(route);
    } finally {
      _orientationPlayIntent ??= _playRequested;
      if (mounted) setState(() => _wide = false);
      _fullscreenRoute = null;
      _fullscreenNavigator = null;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.inlineControls
        ? const Color(0xff111612)
        : Paper.of(context).videoSurface,
    child: Stack(
      children: [
        Positioned.fill(
          child: !widget.active
              ? MediaPoster(
                  video: widget.video,
                  fit: BoxFit.contain,
                  onUnauthorized: () =>
                      widget.onUnauthorized?.call(widget.video.source),
                )
              : _error != null
              ? EmptyView(
                  _error!,
                  action: OutlinedButton(
                    onPressed: _load,
                    child: const Text('重试'),
                  ),
                )
              : _controller == null ||
                    !widget.session.contains(_controller!) ||
                    !_controller!.value.isInitialized ||
                    _controller!.value.size.isEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaPoster(
                      video: widget.video,
                      fit: BoxFit.contain,
                      onUnauthorized: () =>
                          widget.onUnauthorized?.call(widget.video.source),
                    ),
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                )
              : PlayerSurface(
                  controller: _controller!,
                  name: widget.video.name,
                  interactionsEnabled: !widget.suspended && !_wide && !_loading,
                  inlineControls: widget.inlineControls,
                  footer: widget.footer,
                  onFullscreen: widget.video.portrait ? null : _fullscreen,
                  onSpeedChanged: (speed) => _baseSpeed = speed,
                  isPlayRequested: () => _playRequested,
                  onPlayRequested: _changePlayRequest,
                ),
        ),
      ],
    ),
  );
  void _changePlayRequest(bool playing) {
    _orientationPlayIntent = null;
    _playRequested = playing;
    _repaint();
  }

  @override
  void dispose() {
    ++_generation;
    _cancelInitialization();
    final route = _fullscreenRoute, navigator = _fullscreenNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
    _screenRevision.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.session.release(_controller));
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
    this.fullscreen = false,
    this.onExit,
    this.onFullscreen,
    this.footer,
    this.onSpeedChanged,
    this.isPlayRequested,
    this.onPlayRequested,
    this.inlineControls = false,
  });
  final VideoPlayerController controller;
  final String name;
  final bool interactionsEnabled, fullscreen;
  final VoidCallback? onExit, onFullscreen;
  final Widget? footer;
  final ValueChanged<double>? onSpeedChanged;
  final bool Function()? isPlayRequested;
  final ValueChanged<bool>? onPlayRequested;
  final bool inlineControls;
  @override
  State<PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<PlayerSurface>
    with WidgetsBindingObserver {
  final _device = PlaybackDeviceControls();
  double? _previousSpeed;
  Future<void> _speedChanges = Future.value();
  Timer? _hideTimer, _feedbackTimer;
  late bool _controls = widget.fullscreen || widget.inlineControls;
  bool _seeking = false, _resumeAfterSeek = false, _deviceEnabled = true;
  double _seekStart = 0, _seekMs = 0, _seekDx = 0;
  Map<String, double>? _levels;
  String? _levelKind, _feedback;
  double _levelStart = 0, _levelDy = 0;
  double? _pendingLevel;
  bool _writingLevel = false;
  VideoPlayerController get controller => widget.controller;
  bool get _playRequested =>
      widget.isPlayRequested?.call() ?? controller.value.isPlaying;

  void _togglePlayback() {
    final playing = !_playRequested;
    widget.onPlayRequested?.call(playing);
    if (!playing) _endBoost();
    unawaited(playing ? controller.play() : controller.pause());
    if (widget.inlineControls) {
      setState(() => _controls = true);
      if (playing) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.fullscreen) {
      unawaited(_readLevels());
    }
    if (widget.fullscreen || widget.inlineControls) _scheduleHide();
  }

  Future<void> _readLevels() async {
    try {
      final levels = await _device.levels();
      if (mounted) _levels = levels;
    } on PlatformException {
      if (mounted) _message('无法读取音量或亮度');
    } on MissingPluginException {
      if (mounted) _message('此设备暂不支持音量和亮度手势');
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_seeking && (_playRequested || !widget.inlineControls)) {
        setState(() => _controls = false);
      }
    });
  }

  void _message(String text) {
    _feedbackTimer?.cancel();
    if (mounted) setState(() => _feedback = text);
    _feedbackTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _setSpeed(double speed) {
    final player = controller;
    _speedChanges = _speedChanges
        .then((_) async {
          if (player.value.isInitialized) await player.setPlaybackSpeed(speed);
          if (mounted &&
              widget.interactionsEnabled &&
              _deviceEnabled &&
              !_seeking &&
              _playRequested &&
              player.value.isInitialized) {
            await player.play();
          }
        })
        .catchError((Object _) {});
  }

  void _startBoost() {
    if (!widget.interactionsEnabled ||
        !_playRequested ||
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

  void _startSeek() {
    if (!widget.interactionsEnabled || _seeking) return;
    _endBoost();
    _hideTimer?.cancel();
    _seekStart = controller.value.position.inMilliseconds.toDouble();
    _seekDx = 0;
    _resumeAfterSeek = _playRequested;
    unawaited(controller.pause());
    setState(() {
      _seeking = true;
      _controls = true;
      _seekMs = _seekStart;
    });
  }

  void _moveSeek(
    DragUpdateDetails details, {
    bool track = false,
    double? trackWidth,
  }) {
    if (!_seeking) return;
    final duration = controller.value.duration.inMilliseconds.toDouble();
    final width = trackWidth ?? context.size!.width;
    _seekDx += details.delta.dx;
    setState(
      () => _seekMs = track
          ? ((details.localPosition.dx - 16) / (width - 32) * duration).clamp(
              0,
              duration,
            )
          : (_seekStart + _seekDx / width * duration.clamp(0, 120000)).clamp(
              0,
              duration,
            ),
    );
  }

  Future<void> _finishSeek({bool cancel = false}) async {
    if (!_seeking) return;
    final resume = _resumeAfterSeek;
    final target = cancel ? _seekStart : _seekMs;
    _resumeAfterSeek = false;
    setState(() => _seeking = false);
    try {
      await controller.seekTo(Duration(milliseconds: target.round()));
      if (mounted && widget.interactionsEnabled && _deviceEnabled && resume) {
        await controller.play();
      }
    } catch (_) {
      if (mounted) _message('调整进度失败，请重试');
    }
    if (mounted) _scheduleHide();
  }

  void _startLevel(DragStartDetails details) {
    if (!widget.fullscreen || !widget.interactionsEnabled) return;
    _endBoost();
    _feedbackTimer?.cancel();
    _levelKind = details.localPosition.dx < context.size!.width / 2
        ? 'brightness'
        : 'volume';
    _levelStart = _levels?[_levelKind] ?? .5;
    _levelDy = 0;
    if (_levels == null) unawaited(_readLevels());
  }

  void _moveLevel(DragUpdateDetails details) {
    if (_levelKind == null) return;
    _levelDy -= details.delta.dy;
    final value = (_levelStart + _levelDy / (context.size!.height * .7)).clamp(
      0.0,
      1.0,
    );
    setState(
      () => _feedback =
          '${_levelKind == 'brightness' ? '亮度' : '音量'} ${(value * 100).round()}%',
    );
    _pendingLevel = value;
    unawaited(_writeLevel());
  }

  Future<void> _writeLevel() async {
    if (_writingLevel) return;
    _writingLevel = true;
    try {
      while (_pendingLevel != null && mounted && _deviceEnabled) {
        final value = _pendingLevel!;
        final kind = _levelKind;
        _pendingLevel = null;
        if (kind == null) break;
        _levels = kind == 'brightness'
            ? await _device.setBrightness(value)
            : await _device.setVolume(value);
      }
    } on PlatformException {
      if (mounted) _message('无法调整${_levelKind == 'brightness' ? '亮度' : '音量'}');
    } on MissingPluginException {
      if (mounted) _message('此设备暂不支持这项手势');
    } finally {
      _writingLevel = false;
    }
  }

  void _finishLevel() {
    if (_feedback != null) _message(_feedback!);
    if (_controls) _scheduleHide();
  }

  ({bool stacked, bool separateSpeed, double height}) _inlineLayout(
    VideoPlayerValue value,
    Duration position,
    double width,
  ) {
    final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 12);
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    final timeWidth = measure(
      '${timeLabel(position)} / ${timeLabel(value.duration)}',
    );
    // Reserve the widest speed label so selecting a speed does not move the track.
    final speedWidth = measure('1.5×') + 35;
    final toggleWidth = (measure('暂停') + 12).clamp(40.0, double.infinity);
    final innerWidth = width - 32;
    final stacked = toggleWidth + 88 + timeWidth + speedWidth > innerWidth;
    final separateSpeed = stacked && timeWidth + 8 + speedWidth > innerWidth;
    return (
      stacked: stacked,
      separateSpeed: separateSpeed,
      height: 48.0 * (stacked ? (separateSpeed ? 3 : 2) : 1),
    );
  }

  Widget _inlineControlBar(
    VideoPlayerValue value,
    Duration position,
    ({bool stacked, bool separateSpeed, double height}) layout,
  ) {
    final toggle = TextButton(
      onPressed: widget.interactionsEnabled ? _togglePlayback : null,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(40, 44),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(_playRequested ? '暂停' : '播放'),
    );
    final track = Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          key: const Key('video-progress-touch'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: !widget.interactionsEnabled
              ? null
              : (_) => _startSeek(),
          onHorizontalDragUpdate: (details) =>
              _moveSeek(details, track: true, trackWidth: constraints.maxWidth),
          onHorizontalDragEnd: (_) => unawaited(_finishSeek()),
          onHorizontalDragCancel: () => unawaited(_finishSeek(cancel: true)),
          child: SizedBox(
            height: 48,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: IgnorePointer(
                child: Slider(
                  key: const Key('video-progress'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  activeColor: const Color(0xffb9cba9),
                  inactiveColor: Colors.white38,
                  min: 0,
                  max: value.duration.inMilliseconds > 0
                      ? value.duration.inMilliseconds.toDouble()
                      : 1,
                  value: position.inMilliseconds.toDouble().clamp(
                    0,
                    value.duration.inMilliseconds > 0
                        ? value.duration.inMilliseconds.toDouble()
                        : 1,
                  ),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final time = Text(
      '${timeLabel(position)} / ${timeLabel(value.duration)}',
      key: const Key('playback-time'),
      style: const TextStyle(color: Colors.white, fontSize: 12),
    );
    final speed = PopupMenuButton<double>(
      tooltip: '播放速度',
      enabled: widget.interactionsEnabled,
      initialValue: value.playbackSpeed,
      onOpened: () => _hideTimer?.cancel(),
      onCanceled: _scheduleHide,
      onSelected: (speed) {
        widget.onSpeedChanged?.call(speed);
        _setSpeed(speed);
        _scheduleHide();
      },
      itemBuilder: (_) => [.5, 1.0, 1.5, 2.0]
          .map((speed) => PopupMenuItem(value: speed, child: Text('$speed×')))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 4),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.playbackSpeed.toString().replaceFirst(RegExp(r'\.0$'), '')}×',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 17, color: Colors.white),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      // Keep the speed popup independent of hints appearing above the bar.
      key: const Key('playback-controls-layer'),
      left: 10,
      right: 10,
      bottom: 12,
      height: layout.height,
      child: IgnorePointer(
        ignoring: !_controls,
        child: AnimatedOpacity(
          opacity: _controls ? 1 : 0,
          duration: MediaLayout.motion(context, 160),
          child: Container(
            key: const Key('playback-controls'),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xff0d110e).withValues(alpha: .94),
              borderRadius: BorderRadius.circular(4),
            ),
            child: layout.stacked
                ? Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(children: [toggle, track]),
                      ),
                      if (layout.separateSpeed) ...[
                        SizedBox(
                          height: 48,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: time,
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: speed,
                          ),
                        ),
                      ] else
                        SizedBox(
                          height: 48,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [time, speed],
                          ),
                        ),
                    ],
                  )
                : Row(children: [toggle, track, time, speed]),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(PlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.interactionsEnabled) {
      _endBoost();
      if (_seeking) unawaited(_finishSeek(cancel: true));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _deviceEnabled = state == AppLifecycleState.resumed;
    if (!_deviceEnabled) {
      _endBoost();
      if (_seeking) unawaited(_finishSeek(cancel: true));
      _pendingLevel = null;
      if (widget.fullscreen) unawaited(_device.restoreBrightness());
    } else if (widget.fullscreen) {
      unawaited(_readLevels());
    }
  }

  @override
  void dispose() {
    _deviceEnabled = false;
    _pendingLevel = null;
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_previousSpeed != null) _setSpeed(_previousSpeed!);
    if (widget.fullscreen) unawaited(_device.restoreBrightness());
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, v, _) {
      if (v.hasError) return const EmptyView('视频播放失败，可上下滑动继续查看');
      final position = Duration(
        milliseconds: (_seeking ? _seekMs : v.position.inMilliseconds).round(),
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final inlineLayout = widget.inlineControls
              ? _inlineLayout(v, position, constraints.maxWidth)
              : (stacked: false, separateSpeed: false, height: 48.0);
          return Semantics(
            label: widget.name,
            value: '${_playRequested ? '正在播放' : '已暂停'}，${v.playbackSpeed}倍速',
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerCancel: (_) {
                      _endBoost();
                      if (_seeking) unawaited(_finishSeek(cancel: true));
                      _finishLevel();
                    },
                    child: GestureDetector(
                      key: const Key('video-gesture-surface'),
                      behavior: HitTestBehavior.opaque,
                      onTap: !widget.interactionsEnabled
                          ? null
                          : () {
                              if (widget.fullscreen) {
                                setState(() => _controls = !_controls);
                                if (_controls) _scheduleHide();
                              } else {
                                _togglePlayback();
                              }
                            },
                      onLongPressStart: !widget.interactionsEnabled
                          ? null
                          : (_) => _startBoost(),
                      onLongPressEnd: (_) => _endBoost(),
                      onLongPressCancel: _endBoost,
                      onHorizontalDragStart: !widget.interactionsEnabled
                          ? null
                          : (_) => _startSeek(),
                      onHorizontalDragUpdate: _moveSeek,
                      onHorizontalDragEnd: (_) => unawaited(_finishSeek()),
                      onHorizontalDragCancel: () =>
                          unawaited(_finishSeek(cancel: true)),
                      onVerticalDragStart: widget.fullscreen
                          ? _startLevel
                          : null,
                      onVerticalDragUpdate: widget.fullscreen
                          ? _moveLevel
                          : null,
                      onVerticalDragEnd: widget.fullscreen
                          ? (_) => _finishLevel()
                          : null,
                      onVerticalDragCancel: widget.fullscreen
                          ? _finishLevel
                          : null,
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
                if (widget.inlineControls &&
                    !_playRequested &&
                    (!_controls ||
                        constraints.maxHeight - inlineLayout.height - 12 >= 60))
                  Positioned.fill(
                    bottom:
                        _controls &&
                            constraints.maxHeight <
                                2 * (inlineLayout.height + 42)
                        ? inlineLayout.height + 12
                        : 0,
                    child: Center(
                      child: IconButton(
                        key: const Key('inline-play'),
                        tooltip: '播放视频',
                        style: IconButton.styleFrom(
                          backgroundColor: Paper.background.withValues(
                            alpha: .94,
                          ),
                          foregroundColor: Paper.olive,
                          minimumSize: const Size(60, 60),
                          shape: const CircleBorder(),
                        ),
                        onPressed: widget.interactionsEnabled
                            ? _togglePlayback
                            : null,
                        icon: const PaperIcon(
                          PaperGlyph.play,
                          size: 28,
                          color: Paper.olive,
                        ),
                      ),
                    ),
                  ),
                if (widget.footer != null)
                  AnimatedPositioned(
                    duration: MediaLayout.motion(context, 160),
                    left: 16,
                    right: widget.onFullscreen == null ? 16 : 82,
                    bottom: _controls ? 62 : 28,
                    child: widget.footer!,
                  ),
                if (_previousSpeed != null || _feedback != null)
                  Positioned(
                    top: widget.fullscreen ? 60 : 18,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          key: Key(
                            _previousSpeed != null
                                ? 'hold-speed-hint'
                                : 'device-level-hint',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _previousSpeed != null ? '2× 快进中' : _feedback!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.onFullscreen != null)
                  Positioned(
                    right: 12,
                    bottom: _controls
                        ? (widget.inlineControls
                              ? inlineLayout.height + 18
                              : 66)
                        : 32,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            (widget.inlineControls
                                    ? Paper.background
                                    : Paper.of(context).background)
                                .withValues(alpha: .9),
                        foregroundColor: widget.inlineControls
                            ? Paper.olive
                            : Paper.of(context).ink,
                        shape: widget.inlineControls
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              )
                            : const StadiumBorder(),
                        minimumSize: const Size(74, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                      ),
                      onPressed: widget.onFullscreen,
                      icon: const Icon(Icons.fullscreen, size: 19),
                      label: Text(widget.inlineControls ? '横向全屏' : '横屏'),
                    ),
                  ),
                if (widget.fullscreen)
                  Positioned(
                    top: 6,
                    left: 8,
                    right: 12,
                    child: SafeArea(
                      bottom: false,
                      child: IgnorePointer(
                        ignoring: !_controls,
                        child: AnimatedOpacity(
                          opacity: _controls ? 1 : 0,
                          duration: MediaLayout.motion(context, 160),
                          child: Row(
                            children: [
                              IconButton(
                                key: const Key('fullscreen-exit'),
                                tooltip: '退出全屏',
                                onPressed: widget.onExit,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.inlineControls)
                  _inlineControlBar(v, position, inlineLayout)
                else
                  Positioned(
                    key: const Key('playback-controls-layer'),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _controls ? 56 : 26,
                    child: GestureDetector(
                      key: const Key('video-progress-touch'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: !widget.interactionsEnabled
                          ? null
                          : (_) => _startSeek(),
                      onHorizontalDragUpdate: (d) => _moveSeek(d, track: true),
                      onHorizontalDragEnd: (_) => unawaited(_finishSeek()),
                      onHorizontalDragCancel: () =>
                          unawaited(_finishSeek(cancel: true)),
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.bottomCenter,
                          minHeight: 56,
                          maxHeight: 56,
                          child: IgnorePointer(
                            ignoring: !_controls,
                            child: AnimatedOpacity(
                              opacity: _controls ? 1 : 0,
                              duration: MediaLayout.motion(context, 160),
                              child: Container(
                                key: const Key('playback-controls'),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0x75000000),
                                    ],
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 28,
                                      child: Row(
                                        children: [
                                          if (widget.fullscreen ||
                                              widget.inlineControls)
                                            IconButton(
                                              tooltip: _playRequested
                                                  ? '暂停'
                                                  : '播放',
                                              constraints: const BoxConstraints(
                                                minWidth: 30,
                                                minHeight: 28,
                                              ),
                                              padding: EdgeInsets.zero,
                                              onPressed: () {
                                                _togglePlayback();
                                                _scheduleHide();
                                              },
                                              icon: Icon(
                                                _playRequested
                                                    ? Icons.pause
                                                    : Icons.play_arrow,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              '${timeLabel(position)} / ${timeLabel(v.duration)}',
                                              key: const Key('playback-time'),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<double>(
                                            tooltip: '播放速度',
                                            initialValue: v.playbackSpeed,
                                            onOpened: () =>
                                                _hideTimer?.cancel(),
                                            onCanceled: _scheduleHide,
                                            onSelected: (speed) {
                                              widget.onSpeedChanged?.call(
                                                speed,
                                              );
                                              _setSpeed(speed);
                                              _scheduleHide();
                                            },
                                            itemBuilder: (_) =>
                                                [.5, 1.0, 1.5, 2.0]
                                                    .map(
                                                      (speed) => PopupMenuItem(
                                                        value: speed,
                                                        child: Text('$speed×'),
                                                      ),
                                                    )
                                                    .toList(),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                  ),
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
                                    ),
                                    SizedBox(
                                      height: 28,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 4,
                                              ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 8,
                                              ),
                                        ),
                                        child: IgnorePointer(
                                          child: Slider(
                                            key: const Key('video-progress'),
                                            activeColor: Colors.white,
                                            inactiveColor: Colors.white38,
                                            min: 0,
                                            max: v.duration.inMilliseconds > 0
                                                ? v.duration.inMilliseconds
                                                      .toDouble()
                                                : 1,
                                            value: position.inMilliseconds
                                                .toDouble()
                                                .clamp(
                                                  0,
                                                  v.duration.inMilliseconds > 0
                                                      ? v
                                                            .duration
                                                            .inMilliseconds
                                                            .toDouble()
                                                      : 1,
                                                ),
                                            onChangeStart: (_) => _startSeek(),
                                            onChanged: (value) {
                                              if (_seeking) {
                                                setState(() => _seekMs = value);
                                              } else {
                                                unawaited(
                                                  controller.seekTo(
                                                    Duration(
                                                      milliseconds: value
                                                          .round(),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            onChangeEnd: (_) =>
                                                unawaited(_finishSeek()),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}
