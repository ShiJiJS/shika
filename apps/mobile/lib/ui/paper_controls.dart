import 'package:flutter/material.dart';

import 'paper_press.dart';

/// Read the live system preference below MaterialApp's MediaQuery. Keep the
/// existing button styles and native gestures; use a still 100ms press layer.
class PaperControlTheme extends StatefulWidget {
  const PaperControlTheme({super.key, required this.child});
  final Widget child;

  @override
  State<PaperControlTheme> createState() => _PaperControlThemeState();
}

class _PaperControlThemeState extends State<PaperControlTheme> {
  final reduced = ValueNotifier(false);
  late final factory = PaperPressFactory(reduced);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced.value = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    reduced.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 100);
    ButtonStyle style(ButtonStyle? original) =>
        (original ?? const ButtonStyle()).copyWith(animationDuration: duration);
    return Theme(
      data: theme.copyWith(
        splashFactory: factory,
        highlightColor: Colors.transparent,
        filledButtonTheme: FilledButtonThemeData(
          style: style(theme.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: style(theme.outlinedButtonTheme.style),
        ),
        textButtonTheme: TextButtonThemeData(
          style: style(theme.textButtonTheme.style),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: style(theme.elevatedButtonTheme.style),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: style(theme.iconButtonTheme.style),
        ),
      ),
      child: widget.child,
    );
  }
}

class PaperChoiceChip extends ChoiceChip {
  const PaperChoiceChip({
    super.key,
    required super.label,
    required super.selected,
    super.onSelected,
    super.labelStyle,
    super.selectedColor,
    super.backgroundColor,
    super.side,
    super.shape,
    super.padding,
    super.showCheckmark,
    super.focusNode,
  });

  @override
  Widget build(BuildContext context) =>
      _feedback(context, super.build(context) as RawChip);
}

class PaperFilterChip extends FilterChip {
  const PaperFilterChip({
    super.key,
    required super.label,
    required super.selected,
    super.onSelected,
    super.backgroundColor,
    super.side,
    super.focusNode,
  });

  @override
  Widget build(BuildContext context) =>
      _feedback(context, super.build(context) as RawChip);
}

Widget _feedback(BuildContext context, RawChip chip) {
  final theme = ChipTheme.of(context);
  final states = <WidgetState>{
    if (chip.selected) WidgetState.selected,
    if (!chip.isEnabled) WidgetState.disabled,
  };
  final custom = chip.color ?? theme.color;
  final Color? override;
  if (chip.selected) {
    override = chip.selectedColor ?? theme.selectedColor;
  } else if (!chip.isEnabled) {
    override = chip.disabledColor ?? theme.disabledColor;
  } else {
    override = chip.backgroundColor ?? theme.backgroundColor;
  }
  final fill =
      custom?.resolve(states) ??
      (custom == null ? override : null) ??
      chip.defaultProperties?.color?.resolve(states);
  return _ChipFill(
    chip: chip,
    fill: fill,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140),
  );
}

/// Own just the selection fill tween. RawChip keeps its native focus, hit
/// testing, semantics, callbacks and layout, with its internal tweens always
/// zero. This avoids SDK controllers that ignore style changes after mounting.
class _ChipFill extends ImplicitlyAnimatedWidget {
  const _ChipFill({
    required this.chip,
    required this.fill,
    required super.duration,
  }) : super(curve: Curves.fastOutSlowIn);
  final RawChip chip;
  final Color? fill;
  @override
  AnimatedWidgetBaseState<_ChipFill> createState() => _ChipFillState();
}

class _ChipFillState extends AnimatedWidgetBaseState<_ChipFill> {
  ColorTween? _fill;
  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _fill = visitor(
      _fill,
      widget.fill,
      (value) => ColorTween(begin: value as Color?),
    ) as ColorTween?;
  }

  @override
  void didUpdateWidget(_ChipFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    final inheritedColorChanged =
        widget.fill != oldWidget.fill &&
        widget.chip.selected == oldWidget.chip.selected &&
        widget.chip.isEnabled == oldWidget.chip.isEnabled;
    // Follow a parent's appearance transition without retargeting a second
    // selection tween. An unrelated rebuild with the same fill keeps running.
    if (widget.duration == Duration.zero || inheritedColorChanged) {
      controller.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chip;
    final fill = _fill?.evaluate(animation);
    return RawChip(
      defaultProperties: c.defaultProperties,
      label: c.label,
      labelStyle: c.labelStyle,
      labelPadding: c.labelPadding,
      padding: c.padding,
      visualDensity: c.visualDensity,
      onSelected: c.onSelected,
      pressElevation: c.pressElevation,
      selected: c.selected,
      isEnabled: c.isEnabled,
      disabledColor: fill,
      selectedColor: fill,
      backgroundColor: fill,
      color: c.color == null ? null : WidgetStatePropertyAll(fill),
      tooltip: c.tooltip,
      side: c.side,
      shape: c.shape,
      clipBehavior: c.clipBehavior,
      focusNode: c.focusNode,
      autofocus: c.autofocus,
      materialTapTargetSize: c.materialTapTargetSize,
      elevation: c.elevation,
      shadowColor: c.shadowColor,
      surfaceTintColor: c.surfaceTintColor,
      iconTheme: c.iconTheme,
      selectedShadowColor: c.selectedShadowColor,
      showCheckmark: c.showCheckmark,
      checkmarkColor: c.checkmarkColor,
      avatarBorder: c.avatarBorder,
      avatarBoxConstraints: c.avatarBoxConstraints,
      chipAnimationStyle: ChipAnimationStyle(
        selectAnimation: AnimationStyle.noAnimation,
        enableAnimation: AnimationStyle.noAnimation,
        avatarDrawerAnimation: AnimationStyle.noAnimation,
        deleteDrawerAnimation: AnimationStyle.noAnimation,
      ),
      mouseCursor: c.mouseCursor,
    );
  }
}
