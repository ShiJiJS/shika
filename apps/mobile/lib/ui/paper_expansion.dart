// Copyright 2014 The Flutter Authors. All rights reserved.
// Rendering and semantics adapted from Flutter 3.47.7 ExpansionTile/Expansible.
// BSD license: ../../third_party/flutter-LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// The scan summary's existing ExpansionTile presentation with owned motion.
/// Only the three arguments used by the scan page are supported; this is not a
/// replacement for ExpansionTile's controller or its other parameter interfaces.
class PaperExpansionTile extends StatefulWidget {
  const PaperExpansionTile({
    super.key,
    required this.title,
    required this.children,
    this.tilePadding,
  });

  final Widget title;
  final List<Widget> children;
  final EdgeInsetsGeometry? tilePadding;

  @override
  State<PaperExpansionTile> createState() => _PaperExpansionTileState();
}

class _PaperExpansionTileState extends State<PaperExpansionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  late final CurvedAnimation _height;
  late final Animation<double> _turns;
  bool _expanded = false, _initialized = false, _reduced = false;
  Timer? _announcement;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      duration: const Duration(milliseconds: 160),
      vsync: this,
    )..addStatusListener(_finished);
    _height = CurvedAnimation(parent: _motion, curve: Curves.easeIn);
    _turns = _motion.drive(
      Tween<double>(begin: 0, end: .5).chain(CurveTween(curve: Curves.easeIn)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _expanded =
          PageStorage.maybeOf(context)?.readState(context) as bool? ?? false;
      _motion.value = _expanded ? 1 : 0;
      _initialized = true;
    }
    _reduced = MediaQuery.disableAnimationsOf(context);
    _motion.duration = _reduced
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final style = ExpansionTileTheme.of(context).expansionAnimationStyle;
    _height.curve = style?.curve ?? Curves.easeIn;
    _height.reverseCurve = style?.reverseCurve;
    if (_reduced) _motion.value = _expanded ? 1 : 0;
  }

  void _finished(AnimationStatus status) {
    if (_initialized &&
        mounted &&
        !_expanded &&
        status == AnimationStatus.dismissed) {
      // Match the existing non-maintained body lifetime after collapse.
      setState(() {});
    }
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_reduced) {
        _motion.value = _expanded ? 1 : 0;
      } else if (_expanded) {
        _motion.forward();
      } else {
        _motion.reverse();
      }
    });
    PageStorage.maybeOf(context)?.writeState(context, _expanded);
    _announce();
  }

  void _announce() {
    if (defaultTargetPlatform == TargetPlatform.android) return;
    final localizations = MaterialLocalizations.of(context);
    final hint = _expanded
        ? localizations.collapsedHint
        : localizations.expandedHint;
    final direction = WidgetsLocalizations.of(context).textDirection;
    void send() {
      SemanticsService.sendAnnouncement(
        View.of(context),
        hint,
        direction,
      ).catchError(
        (Object error, StackTrace stack) => FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'material library',
            context: ErrorDescription('while sending semantics announcement'),
          ),
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _announcement?.cancel();
      _announcement = Timer(const Duration(seconds: 1), send);
    } else {
      send();
    }
  }

  Widget _header(ThemeData theme, ExpansionTileThemeData tileTheme) {
    final defaults = theme.useMaterial3;
    final t = Curves.easeIn.transform(_motion.value);
    final iconColor = Color.lerp(
      tileTheme.collapsedIconColor ??
          (defaults
              ? theme.colorScheme.onSurfaceVariant
              : theme.unselectedWidgetColor),
      tileTheme.iconColor ?? theme.colorScheme.primary,
      t,
    );
    final textColor = Color.lerp(
      tileTheme.collapsedTextColor ??
          (defaults
              ? theme.colorScheme.onSurface
              : theme.textTheme.titleMedium!.color),
      tileTheme.textColor ??
          (defaults ? theme.colorScheme.onSurface : theme.colorScheme.primary),
      t,
    );
    final arrow = RotationTransition(
      turns: _turns,
      child: const Icon(Icons.expand_more),
    );
    final leading =
        ListTileTheme.of(context).controlAffinity ==
        ListTileControlAffinity.leading;
    final child = ListTileTheme.merge(
      iconColor: iconColor,
      textColor: textColor,
      child: ListTile(
        onTap: _toggle,
        enableFeedback: true,
        internalAddSemanticForOnTap: false,
        contentPadding: widget.tilePadding ?? tileTheme.tilePadding,
        leading: leading ? arrow : null,
        trailing: leading ? null : arrow,
        title: widget.title,
      ),
    );
    final localizations = MaterialLocalizations.of(context);
    final onTapHint = _expanded
        ? localizations.expansionTileExpandedTapHint
        : localizations.expansionTileCollapsedTapHint;
    final hint = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS =>
        _expanded
            ? '${localizations.collapsedHint}\n ${localizations.expansionTileExpandedHint}'
            : '${localizations.expandedHint}\n ${localizations.expansionTileCollapsedHint}',
      _ => _expanded ? localizations.collapsedHint : localizations.expandedHint,
    };
    final semantics = Semantics(hint: hint, onTapHint: onTapHint, child: child);
    return defaultTargetPlatform == TargetPlatform.android
        ? Semantics(
            label: hint,
            liveRegion: true,
            accessibilityFocusBlockType: AccessibilityFocusBlockType.blockNode,
            child: semantics,
          )
        : semantics;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tileTheme = ExpansionTileTheme.of(context);
    final closed = !_expanded && _motion.isDismissed;
    final content = closed
        ? null
        : Offstage(
            offstage: closed,
            child: TickerMode(
              enabled: !closed,
              child: Align(
                alignment: tileTheme.expandedAlignment ?? Alignment.center,
                child: Padding(
                  padding: tileTheme.childrenPadding ?? EdgeInsets.zero,
                  child: Column(children: widget.children),
                ),
              ),
            ),
          );
    return AnimatedBuilder(
      animation: _motion,
      child: content,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_motion.value);
        final background =
            Color.lerp(
              tileTheme.collapsedBackgroundColor,
              tileTheme.backgroundColor,
              t,
            ) ??
            tileTheme.backgroundColor ??
            Colors.transparent;
        final border = ShapeBorder.lerp(
          tileTheme.collapsedShape ??
              const Border(
                top: BorderSide(color: Colors.transparent),
                bottom: BorderSide(color: Colors.transparent),
              ),
          tileTheme.shape ??
              Border(
                top: BorderSide(color: theme.dividerColor),
                bottom: BorderSide(color: theme.dividerColor),
              ),
          t,
        )!;
        final decoration = ShapeDecoration(color: background, shape: border);
        Widget tile = Padding(
          padding: decoration.padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(theme, tileTheme),
              ClipRect(
                child: Align(heightFactor: _height.value, child: child),
              ),
            ],
          ),
        );
        if (tileTheme.shape != null || tileTheme.collapsedShape != null) {
          return Material(
            clipBehavior: tileTheme.clipBehavior ?? Clip.antiAlias,
            color: background,
            shape: border,
            child: tile,
          );
        }
        if (background.a > 0) {
          tile = Material(type: MaterialType.transparency, child: tile);
        }
        return DecoratedBox(decoration: decoration, child: tile);
      },
    );
  }

  @override
  void dispose() {
    _announcement?.cancel();
    _motion.removeStatusListener(_finished);
    _height.dispose();
    _motion.dispose();
    super.dispose();
  }
}
