// Copyright 2014 The Flutter Authors. All rights reserved.
// Adapted button construction, menu surface and placement from Flutter.
// BSD license: ../../third_party/flutter-LICENSE.
// The route and its animation controller are owned here for live Paper motion.
import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Native menu entries and button behavior with an owned 240/160ms route.
class PaperMenuButton<T> extends PopupMenuButton<T> {
  const PaperMenuButton({
    super.key,
    required super.itemBuilder,
    super.initialValue,
    super.onOpened,
    super.onSelected,
    super.onCanceled,
    super.tooltip,
    super.padding,
    super.menuPadding,
    super.child,
    super.icon,
    super.iconSize,
    super.constraints,
    super.enabled,
    super.style,
    super.offset,
    super.position,
    super.shape,
    super.color,
    super.elevation,
    super.shadowColor,
    super.surfaceTintColor,
    super.iconColor,
    super.splashRadius,
    super.borderRadius,
    super.enableFeedback,
    super.clipBehavior,
    super.useRootNavigator,
    super.routeSettings,
    super.requestFocus,
  });

  @override
  PopupMenuButtonState<T> createState() => _PaperMenuButtonState<T>();
}

class _PaperMenuButtonState<T> extends PopupMenuButtonState<T> {
  bool expanded = false;
  @override
  void showButtonMenu() {
    if (!widget.enabled || expanded) return;
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;
    final navigator = Navigator.of(
      context,
      rootNavigator: widget.useRootNavigator,
    );
    final button = context.findRenderObject()! as RenderBox;
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    RelativeRect position() {
      final mode =
          widget.position ??
          PopupMenuTheme.of(context).position ??
          PopupMenuPosition.over;
      var offset = widget.offset;
      if (mode == PopupMenuPosition.under) {
        offset += Offset(0, button.size.height);
        if (widget.child == null) {
          offset -= Offset(0, widget.padding.vertical / 2);
        }
      }
      return RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(offset, ancestor: overlay),
          button.localToGlobal(
            button.size.bottomRight(Offset.zero) + offset,
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
    }

    var lastPosition = position();
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    final localizations = MaterialLocalizations.of(context);
    widget.onOpened?.call();
    if (!mounted) return;
    setState(() => expanded = true);
    navigator
        .push<T>(
          _PaperMenuRoute<T>(
            button: widget,
            items: items,
            themes: themes,
            barrierLabel: localizations.menuDismissLabel,
            semanticLabel: switch (defaultTargetPlatform) {
              TargetPlatform.iOS || TargetPlatform.macOS => null,
              _ => localizations.popupMenuLabel,
            },
            position: (_, _) {
              if (mounted && button.attached && overlay.attached) {
                lastPosition = position();
              }
              return lastPosition;
            },
          ),
        )
        .then((value) {
          if (!mounted) return;
          setState(() => expanded = false);
          if (value == null) {
            widget.onCanceled?.call();
          } else {
            widget.onSelected?.call(value);
          }
        });
  }

  bool get canRequestFocus =>
      switch (MediaQuery.maybeNavigationModeOf(context) ??
      NavigationMode.traditional) {
        NavigationMode.traditional => widget.enabled,
        NavigationMode.directional => true,
      };

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final theme = PopupMenuTheme.of(context);
    final feedback = widget.enableFeedback ?? theme.enableFeedback ?? true;
    if (widget.child != null) {
      final child = Tooltip(
        message:
            widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.enabled ? showButtonMenu : null,
          canRequestFocus: canRequestFocus,
          radius: widget.splashRadius,
          enableFeedback: feedback,
          child: widget.child,
        ),
      );
      if ((widget.style?.tapTargetSize ?? MaterialTapTargetSize.shrinkWrap) ==
          MaterialTapTargetSize.padded) {
        return ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinInteractiveDimension,
            minHeight: kMinInteractiveDimension,
          ),
          child: child,
        );
      }
      return Semantics(expanded: expanded, child: child);
    }
    return Semantics(
      child: IconButton(
        icon: Semantics(
          expanded: expanded,
          child: widget.icon ?? Icon(Icons.adaptive.more),
        ),
        padding: widget.padding,
        splashRadius: widget.splashRadius,
        iconSize: widget.iconSize ?? theme.iconSize ?? iconTheme.size,
        color: widget.iconColor ?? theme.iconColor ?? iconTheme.color,
        tooltip:
            widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
        onPressed: widget.enabled ? showButtonMenu : null,
        enableFeedback: feedback,
        style: widget.style,
      ),
    );
  }
}

class _MenuMotionObserver extends WidgetsBindingObserver {
  _MenuMotionObserver(this.onChange);
  final VoidCallback onChange;
  @override
  void didChangeAccessibilityFeatures() => onChange();
}

class _PaperMenuRoute<T> extends PopupRoute<T> {
  _PaperMenuRoute({
    required this.button,
    required this.items,
    required this.themes,
    required this.position,
    required this.barrierLabel,
    required this.semanticLabel,
  }) : keys = List.generate(items.length, (_) => GlobalKey()),
       sizes = List.filled(items.length, null),
       super(
         settings: button.routeSettings,
         requestFocus: button.requestFocus,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );
  final PopupMenuButton<T> button;
  final List<PopupMenuEntry<T>> items;
  final CapturedThemes themes;
  final PopupMenuPositionBuilder position;
  final List<GlobalKey> keys;
  final List<Size?> sizes;
  final String? semanticLabel;
  late final motionObserver = _MenuMotionObserver(finishMotion);
  @override
  final String barrierLabel;
  bool get reduced => MediaQuery.disableAnimationsOf(navigator!.context);
  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : const Duration(milliseconds: 240);
  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : const Duration(milliseconds: 160);
  @override
  bool get barrierDismissible => true;
  @override
  Color? get barrierColor => null;
  @override
  void install() {
    super.install();
    WidgetsBinding.instance.addObserver(motionObserver);
  }

  void timing() {
    controller!
      ..duration = transitionDuration
      ..reverseDuration = reverseTransitionDuration;
  }

  @override
  TickerFuture didPush() {
    timing();
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    timing();
    return super.didPop(result);
  }

  void finishMotion() {
    if (!WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      return;
    }
    final c = controller;
    if (c?.status == AnimationStatus.forward) {
      c!.value = 1;
    } else if (c?.status == AnimationStatus.reverse) {
      c!.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(motionObserver);
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    int? selected;
    for (var i = 0; i < items.length; i++) {
      if (button.initialValue != null &&
          items[i].represents(button.initialValue)) {
        selected = i;
        break;
      }
    }
    if (selected != null) {
      final key = keys[selected];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = key.currentContext;
        if (c != null && c.mounted) Scrollable.ensureVisible(c);
      });
    }
    final query = MediaQuery.of(context);
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: LayoutBuilder(
        builder: (context, constraints) => CustomSingleChildLayout(
          delegate: _PaperMenuLayout(
            position(context, constraints),
            sizes,
            selected,
            Directionality.of(context),
            query.padding,
            DisplayFeatureSubScreen.avoidBounds(query).toSet(),
          ),
          child: themes.wrap(
            AnimatedBuilder(
              animation: animation,
              builder: (context, _) => surface(context, animation.value),
            ),
          ),
        ),
      ),
    );
  }

  Widget surface(BuildContext context, double progress) {
    final theme = Theme.of(context), menu = PopupMenuTheme.of(context);
    final unit = 1 / (items.length + 1.5);
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      Widget item = items[i];
      if (button.initialValue != null &&
          items[i].represents(button.initialValue)) {
        item = ColoredBox(color: theme.highlightColor, child: item);
      }
      final start = (i + 1) * unit, end = ((i + 2.5) * unit).clamp(0.0, 1.0);
      children.add(
        Opacity(
          key: keys[i],
          opacity: Interval(start, end).transform(progress),
          child: item,
        ),
      );
    }
    final content = ConstrainedBox(
      constraints:
          button.constraints ??
          const BoxConstraints(minWidth: 112, maxWidth: 280),
      child: IntrinsicWidth(
        stepWidth: 56,
        child: Semantics(
          role: SemanticsRole.menu,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: semanticLabel,
          child: SingleChildScrollView(
            padding:
                button.menuPadding ??
                menu.menuPadding ??
                const EdgeInsets.symmetric(vertical: 8),
            child: ListBody(children: children),
          ),
        ),
      ),
    );
    return Opacity(
      opacity: const Interval(0, 1 / 3).transform(progress),
      child: Material(
        shape:
            button.shape ??
            menu.shape ??
            (theme.useMaterial3
                ? const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  )
                : null),
        color:
            button.color ??
            menu.color ??
            (theme.useMaterial3 ? theme.colorScheme.surfaceContainer : null),
        clipBehavior: button.clipBehavior,
        type: MaterialType.card,
        elevation:
            button.elevation ?? menu.elevation ?? (theme.useMaterial3 ? 3 : 8),
        shadowColor:
            button.shadowColor ??
            menu.shadowColor ??
            (theme.useMaterial3 ? theme.colorScheme.shadow : null),
        surfaceTintColor:
            button.surfaceTintColor ??
            menu.surfaceTintColor ??
            (theme.useMaterial3 ? Colors.transparent : null),
        child: Align(
          alignment: AlignmentDirectional.topEnd,
          widthFactor: Interval(0, unit).transform(progress),
          heightFactor: Interval(0, unit * items.length).transform(progress),
          child: content,
        ),
      ),
    );
  }
}

class _PaperMenuLayout extends SingleChildLayoutDelegate {
  _PaperMenuLayout(
    this.position,
    this.itemSizes,
    this.selectedItemIndex,
    this.textDirection,
    this.padding,
    this.avoidBounds,
  );

  // Rectangle of underlying button, relative to the overlay's dimensions.
  final RelativeRect position;

  // The sizes of each item are computed when the menu is laid out, and before
  // the route is laid out.
  List<Size?> itemSizes;

  // The index of the selected item, or null if PopupMenuButton.initialValue
  // was not specified.
  final int? selectedItemIndex;

  // Whether to prefer going to the left or to the right.
  final TextDirection textDirection;

  // The padding of unsafe area.
  EdgeInsets padding;

  // List of rectangles that we should avoid overlapping. Unusable screen area.
  final Set<Rect> avoidBounds;

  // We put the child wherever position specifies, so long as it will fit within
  // the specified parent size padded (inset) by 8. If necessary, we adjust the
  // child's position so that it fits.

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // The menu can be at most the size of the overlay minus 8.0 pixels in each
    // direction.
    return BoxConstraints.loose(constraints.biggest)
        .deflate(const EdgeInsets.all(8.0) + padding);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double y = position.top;

    // Find the ideal horizontal position.
    // size: The size of the overlay.
    // childSize: The size of the menu, when fully open, as determined by
    // getConstraintsForChild.
    double x;
    if (position.left > position.right) {
      // Menu button is closer to the right edge, so grow to the left, aligned to the right edge.
      x = size.width - position.right - childSize.width;
    } else if (position.left < position.right) {
      // Menu button is closer to the left edge, so grow to the right, aligned to the left edge.
      x = position.left;
    } else {
      // Menu button is equidistant from both edges, so grow in reading direction.
      x = switch (textDirection) {
        TextDirection.rtl => size.width - position.right - childSize.width,
        TextDirection.ltr => position.left,
      };
    }
    final wantedPosition = Offset(x, y);
    final Offset originCenter = position.toRect(Offset.zero & size).center;
    final Iterable<Rect> subScreens =
        DisplayFeatureSubScreen.subScreensInBounds(
          Offset.zero & size,
          avoidBounds,
        );
    final Rect subScreen = _closestScreen(subScreens, originCenter);
    return _fitInsideScreen(subScreen, childSize, wantedPosition);
  }

  Rect _closestScreen(Iterable<Rect> screens, Offset point) {
    Rect closest = screens.first;
    for (final screen in screens) {
      if ((screen.center - point).distance <
          (closest.center - point).distance) {
        closest = screen;
      }
    }
    return closest;
  }

  Offset _fitInsideScreen(Rect screen, Size childSize, Offset wantedPosition) {
    double x = wantedPosition.dx;
    double y = wantedPosition.dy;
    // Avoid going outside an area defined as the rectangle 8.0 pixels from the
    // edge of the screen in every direction.
    if (x < screen.left + 8.0 + padding.left) {
      x = screen.left + 8.0 + padding.left;
    } else if (x + childSize.width > screen.right - 8.0 - padding.right) {
      x = screen.right - childSize.width - 8.0 - padding.right;
    }
    if (y < screen.top + 8.0 + padding.top) {
      y = 8.0 + padding.top;
    } else if (y + childSize.height > screen.bottom - 8.0 - padding.bottom) {
      y = screen.bottom - childSize.height - 8.0 - padding.bottom;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PaperMenuLayout oldDelegate) {
    // If called when the old and new itemSizes have been initialized then
    // we expect them to have the same length because there's no practical
    // way to change length of the items list once the menu has been shown.
    assert(itemSizes.length == oldDelegate.itemSizes.length);

    return position != oldDelegate.position ||
        selectedItemIndex != oldDelegate.selectedItemIndex ||
        textDirection != oldDelegate.textDirection ||
        !listEquals(itemSizes, oldDelegate.itemSizes) ||
        padding != oldDelegate.padding ||
        !setEquals(avoidBounds, oldDelegate.avoidBounds);
  }
}
