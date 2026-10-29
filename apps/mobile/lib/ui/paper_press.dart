import 'package:flutter/material.dart';

/// A still, clipped state layer; InkWell continues to own all gestures.
class PaperPressFactory extends InteractiveInkFeatureFactory {
  const PaperPressFactory(this.reduced);
  final ValueNotifier<bool> reduced;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) => PaperPressInk(
    controller: controller,
    referenceBox: referenceBox,
    color: color,
    textDirection: textDirection,
    rect: rectCallback ?? () => Offset.zero & referenceBox.size,
    borderRadius: borderRadius ?? BorderRadius.zero,
    customBorder: customBorder,
    reduced: reduced,
    onRemoved: onRemoved,
  );
}

class PaperPressInk extends InteractiveInkFeature {
  PaperPressInk({
    required super.controller,
    required super.referenceBox,
    required super.color,
    required this.textDirection,
    required this.rect,
    required this.borderRadius,
    required this.reduced,
    super.customBorder,
    super.onRemoved,
  }) {
    _animation = AnimationController(
      duration: const Duration(milliseconds: 100),
      animationBehavior: AnimationBehavior.preserve,
      vsync: controller.vsync,
    )..addListener(controller.markNeedsPaint);
    _animation.addStatusListener((status) {
      if (_closing && status == AnimationStatus.dismissed) dispose();
    });
    controller.addInkFeature(this);
    reduced.addListener(_preference);
    if (reduced.value) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  final TextDirection textDirection;
  final RectCallback rect;
  final BorderRadius borderRadius;
  final ValueNotifier<bool> reduced;
  late final AnimationController _animation;
  bool _closing = false, _disposed = false;

  /// Read-only observation of the actual paint animation, also used by native
  /// interaction checks; callers cannot advance or replace the controller.
  Animation<double> get animation => _animation.view;

  void _preference() {
    if (_disposed || !reduced.value) return;
    _animation.value = _closing ? 0 : 1;
    if (_closing) dispose();
  }

  void _close() {
    if (_disposed || _closing) return;
    _closing = true;
    if (reduced.value || _animation.value == 0) {
      dispose();
    } else {
      _animation.reverse();
    }
  }

  @override
  void confirm() => _close();
  @override
  void cancel() => _close();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    reduced.removeListener(_preference);
    _animation.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    canvas.save();
    canvas.transform(transform.storage);
    final bounds = rect();
    final path = customBorder?.getOuterPath(
      bounds,
      textDirection: textDirection,
    );
    if (path != null) {
      canvas.clipPath(path);
    } else {
      canvas.clipRRect(borderRadius.toRRect(bounds));
    }
    canvas.drawRect(
      bounds,
      Paint()..color = color.withValues(alpha: color.a * _animation.value),
    );
    canvas.restore();
  }
}
