import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

/// Native progress geometry with a still busy marker when motion is reduced.
class PaperLinearProgressIndicator extends StatelessWidget {
  const PaperLinearProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.minHeight,
    this.borderRadius,
  });

  final double? value;
  final Color? color, backgroundColor;
  final double? minHeight;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final still = value == null && MediaQuery.disableAnimationsOf(context);
    final indicator = LinearProgressIndicator(
      value: still ? .35 : value,
      color: color,
      backgroundColor: backgroundColor,
      minHeight: minHeight,
      borderRadius: borderRadius,
    );
    return still ? _StillBusy(child: indicator) : indicator;
  }
}

/// Known progress stays determinate; unknown work never announces a percentage.
class PaperCircularProgressIndicator extends StatelessWidget {
  const PaperCircularProgressIndicator({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.strokeWidth,
  });

  final double? value;
  final Color? color, backgroundColor;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final still = value == null && MediaQuery.disableAnimationsOf(context);
    final indicator = CircularProgressIndicator(
      value: still ? .35 : value,
      color: color,
      backgroundColor: backgroundColor,
      strokeWidth: strokeWidth,
    );
    return still ? _StillBusy(child: indicator) : indicator;
  }
}

class _StillBusy extends StatelessWidget {
  const _StillBusy({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticsRole.loadingSpinner,
    label: '正在加载',
    // The partial native shape is a decorative busy marker, not known progress.
    // Exclude its determinate semantics so no invented percentage is exposed.
    child: ExcludeSemantics(child: child),
  );
}

/// Keep native pull thresholds and refresh lifetime, with a still status hint
/// instead of the native spinner when the system asks for reduced motion.
class PaperRefreshIndicator extends StatefulWidget {
  const PaperRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  State<PaperRefreshIndicator> createState() => _PaperRefreshIndicatorState();
}

class _PaperRefreshIndicatorState extends State<PaperRefreshIndicator> {
  RefreshIndicatorStatus? _status;
  bool _refreshing = false;

  void _changed(RefreshIndicatorStatus? status) {
    if (_status != status) setState(() => _status = status);
  }

  Future<void> _refresh() async {
    // The SDK status callback reports drag/armed/snap/done/canceled, but does
    // not report refresh or its final null state. The callback owns that span.
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final label = _refreshing || _status == RefreshIndicatorStatus.snap
        ? '正在刷新'
        : switch (_status) {
            RefreshIndicatorStatus.drag => '下拉刷新',
            RefreshIndicatorStatus.armed => '松开刷新',
            _ => null,
          };
    // Both constructors produce the same widget type and native State. Keep
    // the Stack and its first child in place so a live preference change never
    // remounts the viewport or resets a gesture/pending refresh.
    return Stack(
      children: [
        if (reduced)
          _RefreshSurface.still(
            onRefresh: _refresh,
            statusChanged: _changed,
            child: widget.child,
          )
        else
          _RefreshSurface(
            onRefresh: _refresh,
            statusChanged: _changed,
            child: widget.child,
          ),
        if (reduced && label != null)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(label),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Observe the same public status callback in both native presentations. The
/// standard constructor does not expose it as an argument, so override only
/// that public property; all gestures and animation controllers stay native.
class _RefreshSurface extends RefreshIndicator {
  const _RefreshSurface({
    required super.onRefresh,
    required super.child,
    required this.statusChanged,
  });

  const _RefreshSurface.still({
    required super.onRefresh,
    required super.child,
    required this.statusChanged,
  }) : super.noSpinner();

  final ValueChanged<RefreshIndicatorStatus?> statusChanged;

  @override
  ValueChanged<RefreshIndicatorStatus?> get onStatusChange => statusChanged;
}
