import 'package:flutter/material.dart';

/// Pointer surface for PaperPreferenceSwitch. Its row owns keyboard/focus and
/// accessibility, so the thumb never becomes a second activation target.
class PaperToggle extends StatefulWidget {
  const PaperToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.thumb,
    required this.track,
    required this.outline,
    required this.inactiveTrack,
    required this.inactiveOutline,
    required this.reaction,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color thumb, track, outline, inactiveTrack, inactiveOutline, reaction;

  @override
  State<PaperToggle> createState() => _PaperToggleState();
}

class _PaperToggleState extends State<PaperToggle>
    with TickerProviderStateMixin {
  late final position = AnimationController(
    value: widget.value ? 1 : 0,
    duration: const Duration(milliseconds: 140),
    animationBehavior: AnimationBehavior.preserve,
    vsync: this,
  );
  late final reaction = AnimationController(
    duration: const Duration(milliseconds: 100),
    animationBehavior: AnimationBehavior.preserve,
    vsync: this,
  );
  bool reduced = false, dragging = false, pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      if (!dragging) position.value = widget.value ? 1 : 0;
      reaction.value = pressed ? 1 : 0;
    }
  }

  void settle() {
    final target = widget.value ? 1.0 : 0.0;
    if (reduced) {
      position.value = target;
    } else {
      position.animateTo(target, curve: Curves.fastOutSlowIn);
    }
  }

  void press(bool value, {bool acknowledge = false}) {
    pressed = value;
    if (reduced) {
      reaction.value = value ? 1 : 0;
    } else if (value) {
      reaction.forward();
    } else {
      if (acknowledge) reaction.value = 1;
      reaction.reverse();
    }
  }

  void tap() {
    if (widget.onChanged == null) return;
    press(false, acknowledge: true);
    widget.onChanged!(!widget.value);
  }

  @override
  void didUpdateWidget(PaperToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null && oldWidget.onChanged != null) {
      dragging = false;
      press(false);
      settle();
    } else if (!dragging && oldWidget.value != widget.value) {
      settle();
    }
  }

  void endDrag({bool cancel = false}) {
    if (!dragging) return;
    dragging = false;
    final next = position.value >= .5;
    press(false);
    if (!cancel && widget.onChanged != null && next != widget.value) {
      widget.onChanged!(next);
    }
    // The parent is authoritative, including failed/asynchronous persistence.
    settle();
  }

  @override
  void dispose() {
    position.dispose();
    reaction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final direction = Directionality.of(context);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Listener(
        onPointerCancel: (_) => endDrag(cancel: true),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: enabled ? tap : null,
          onTapDown: enabled ? (_) => press(true) : null,
          onTapUp: enabled ? (_) => press(false) : null,
          onTapCancel: enabled ? () => press(dragging) : null,
          onHorizontalDragStart: enabled
              ? (_) {
                  dragging = true;
                  position.stop();
                  press(true);
                }
              : null,
          onHorizontalDragUpdate: enabled
              ? (details) {
                  final delta = details.primaryDelta! / 20;
                  position.value =
                      (position.value +
                              (direction == TextDirection.rtl ? -delta : delta))
                          .clamp(0.0, 1.0);
                }
              : null,
          onHorizontalDragEnd: enabled ? (_) => endDrag() : null,
          onHorizontalDragCancel: enabled ? () => endDrag(cancel: true) : null,
          child: SizedBox(
            width: 52,
            height: 48,
            child: AnimatedBuilder(
              animation: Listenable.merge([position, reaction]),
              builder: (context, _) => CustomPaint(
                painter: PaperTogglePainter(
                  position: position.value,
                  reaction: reaction.value,
                  direction: direction,
                  thumb: widget.thumb,
                  track: Color.lerp(
                    widget.inactiveTrack,
                    widget.track,
                    position.value,
                  )!,
                  outline: Color.lerp(
                    widget.inactiveOutline,
                    widget.outline,
                    position.value,
                  )!,
                  reactionColor: widget.reaction,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retain the compact row's existing Material 3 resting geometry (52×32 track,
/// 8/12 radius thumb); animate only our owned progress, never SDK private state.
class PaperTogglePainter extends CustomPainter {
  const PaperTogglePainter({
    required this.position,
    required this.reaction,
    required this.direction,
    required this.thumb,
    required this.track,
    required this.outline,
    required this.reactionColor,
  });
  final double position, reaction;
  final TextDirection direction;
  final Color thumb, track, outline, reactionColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final bounds = Rect.fromCenter(center: center, width: 52, height: 32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(16)),
      Paint()..color = track,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(1), const Radius.circular(16)),
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final visual = direction == TextDirection.rtl ? 1 - position : position;
    final origin = Offset(center.dx - 10 + 20 * visual, center.dy);
    if (reaction > 0) {
      canvas.drawCircle(
        origin,
        20,
        Paint()..color = reactionColor.withValues(alpha: .12 * reaction),
      );
    }
    final radius = (8 + 4 * position) * (1 - reaction) + 14 * reaction;
    canvas.drawCircle(origin, radius, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(PaperTogglePainter old) =>
      old.position != position ||
      old.reaction != reaction ||
      old.direction != direction ||
      old.thumb != thumb ||
      old.track != track ||
      old.outline != outline ||
      old.reactionColor != reactionColor;
}
