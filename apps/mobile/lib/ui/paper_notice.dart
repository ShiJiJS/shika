import 'dart:async';

import 'package:flutter/material.dart';

import 'paper_motion.dart';

/// Keep ScaffoldMessenger's queue, timeout, actions and close reasons intact.
/// Its public withAnimation hook supplies the shared controller before paint;
/// this widget borrows that controller and never owns or disposes it.
class PaperSnackBar extends SnackBar {
  PaperSnackBar({
    required BuildContext context,
    required super.content,
    super.key,
    super.action,
    super.duration,
    super.margin,
    super.persist,
  }) : _source = context,
       _body = content;

  final BuildContext _source;
  final Widget _body;
  final _timing = _NoticeTiming();

  @override
  Widget get content => _NoticePreference(timing: _timing, child: _body);

  @override
  SnackBar withAnimation(Animation<double> newAnimation, {Key? fallbackKey}) {
    if (newAnimation is AnimationController) {
      _timing.controller = newAnimation;
      final reduced = _source.mounted
          ? MediaQuery.disableAnimationsOf(_source)
          : WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations;
      _timing.update(reduced);
      // ScaffoldMessenger starts forward before invoking this hook. Rebase the
      // initial simulation before its first frame, without replacing the
      // shared controller (which may also have queued notices attached).
      if (newAnimation.status == AnimationStatus.forward) {
        if (reduced) {
          newAnimation.value = 1;
        } else if (newAnimation.value == 0) {
          newAnimation.forward();
        }
      }
    }
    return super.withAnimation(newAnimation, fallbackKey: fallbackKey);
  }
}

class _NoticeTiming {
  AnimationController? controller;

  void update(bool reduced) {
    final value = controller;
    if (value == null) return;
    value
      ..duration = PaperMotion.transition
      ..reverseDuration = reduced ? Duration.zero : PaperMotion.transition;
  }
}

class _NoticePreference extends StatefulWidget {
  const _NoticePreference({required this.timing, required this.child});
  final _NoticeTiming timing;
  final Widget child;

  @override
  State<_NoticePreference> createState() => _NoticePreferenceState();
}

class _NoticePreferenceState extends State<_NoticePreference> {
  AnimationController? _controller;
  bool _reduced = false, _entryScheduled = false;

  void _listen() {
    final next = widget.timing.controller;
    if (next == _controller) return;
    _controller?.removeStatusListener(_status);
    _controller = next;
    next?.addStatusListener(_status);
  }

  void _status(AnimationStatus status) {
    if (!_reduced ||
        (status != AnimationStatus.forward &&
            status != AnimationStatus.reverse) ||
        _entryScheduled) {
      return;
    }
    _entryScheduled = true;
    // A zero-duration return starts the next queued entry inside the SDK's
    // dismissal callback, before it has cleared the old timeout. Complete the
    // entry after that synchronous callback, still before the next paint.
    scheduleMicrotask(() {
      _entryScheduled = false;
      final value = _controller;
      if (!mounted || !_reduced || value == null) return;
      if (value.status == AnimationStatus.forward) {
        value.value = 1;
      } else if (value.status == AnimationStatus.reverse) {
        // ScaffoldMessenger awaits this reverse TickerFuture to complete the
        // close reason. Complete it before snapping, rather than cancel it.
        value.stop(canceled: false);
        value.value = 0;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    widget.timing.update(_reduced);
    _listen();
    if (_controller != null) _status(_controller!.status);
  }

  @override
  void didUpdateWidget(_NoticePreference oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.timing.update(_reduced);
    _listen();
  }

  @override
  void dispose() {
    _controller?.removeStatusListener(_status);
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
