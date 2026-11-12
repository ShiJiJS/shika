import 'package:flutter/material.dart';

import 'paper_motion.dart';

/// Keep the same Theme/child elements while completing live reduced motion.
class PaperAppearanceTheme extends ImplicitlyAnimatedWidget {
  const PaperAppearanceTheme({
    super.key,
    required this.data,
    required this.reduced,
    required this.child,
  }) : super(duration: reduced ? Duration.zero : PaperMotion.selection);

  final ThemeData data;
  final bool reduced;
  final Widget child;

  @override
  AnimatedWidgetBaseState<PaperAppearanceTheme> createState() =>
      _PaperAppearanceThemeState();
}

class _PaperAppearanceThemeState
    extends AnimatedWidgetBaseState<PaperAppearanceTheme> {
  ThemeDataTween? _data;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _data = visitor(
      _data,
      widget.data,
      (value) => ThemeDataTween(begin: value as ThemeData),
    ) as ThemeDataTween?;
  }

  @override
  void didUpdateWidget(PaperAppearanceTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changing duration alone does not finish an existing simulation.
    if (widget.reduced) controller.value = 1;
  }

  @override
  Widget build(BuildContext context) =>
      Theme(data: _data!.evaluate(animation), child: widget.child);
}
