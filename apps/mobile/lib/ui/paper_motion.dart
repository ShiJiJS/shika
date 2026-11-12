import 'package:flutter/material.dart';

/// Paper's existing native timing, shared without changing gesture physics.
abstract final class PaperMotion {
  static const press = Duration(milliseconds: 100);
  static const selection = Duration(milliseconds: 140);
  static const transition = Duration(milliseconds: 160);
  static const enter = Duration(milliseconds: 240);
  static const exit = transition;
  static const response = Curves.easeOutCubic;
}

/// Finish autonomous transitions when the system preference changes, not only
/// the next push/pop. A finger-driven route has no running simulation: leave it
/// under the user's control. Route content/controllers are never replaced.
mixin PaperRouteMotion<T> on TransitionRoute<T> {
  late final _motionObserver = _RouteMotionObserver(_finishMotion);
  bool get _reduced => MediaQuery.disableAnimationsOf(navigator!.context);
  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : PaperMotion.enter;
  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : PaperMotion.exit;

  @override
  void install() {
    super.install();
    WidgetsBinding.instance.addObserver(_motionObserver);
  }

  void _timing() {
    controller!
      ..duration = transitionDuration
      ..reverseDuration = reverseTransitionDuration;
  }

  void _finishMotion() {
    if (!WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      return;
    }
    final motion = controller;
    if (motion == null || !motion.isAnimating) return;
    if (motion.status == AnimationStatus.forward) {
      motion.value = 1;
    } else if (motion.status == AnimationStatus.reverse) {
      motion.value = 0;
    }
  }

  @override
  TickerFuture didPush() {
    _timing();
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    _timing();
    return super.didPop(result);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_motionObserver);
    super.dispose();
  }
}

class _RouteMotionObserver extends WidgetsBindingObserver {
  _RouteMotionObserver(this.finish);
  final VoidCallback finish;
  @override
  void didChangeAccessibilityFeatures() => finish();
}

/// Unlike changing an implicit animation's duration, this also completes a
/// fade already in flight when reduced motion is enabled. Keep child identity.
class PaperAnimatedOpacity extends ImplicitlyAnimatedWidget {
  const PaperAnimatedOpacity({
    super.key,
    required this.opacity,
    required this.child,
    required super.duration,
    super.curve = PaperMotion.response,
  });
  final double opacity;
  final Widget child;
  @override
  ImplicitlyAnimatedWidgetState<PaperAnimatedOpacity> createState() =>
      _PaperOpacityState();
}

class _PaperOpacityState
    extends ImplicitlyAnimatedWidgetState<PaperAnimatedOpacity> {
  Tween<double>? _opacity;
  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _opacity = visitor(
      _opacity,
      widget.opacity,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;
  }

  @override
  void didUpdateWidget(PaperAnimatedOpacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MediaQuery.disableAnimationsOf(context)) controller.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) controller.value = 1;
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity!.animate(animation),
    child: widget.child,
  );
}
