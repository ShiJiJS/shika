import 'dart:async';

import 'package:flutter/material.dart';

export 'paper_notice.dart';
export 'paper_controls.dart';
export 'paper_appearance.dart';
export 'paper_menu.dart';
export 'paper_dropdown.dart';

/// Keep failures visible when a form's submit action is outside its scroll body.
void revealFormError(GlobalKey anchor) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = anchor.currentContext;
    if (context == null || !context.mounted) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: .5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
      ),
    );
  });
}

class PaperPalette extends ThemeExtension<PaperPalette> {
  const PaperPalette(bool dark) : _blend = dark ? 1 : 0;
  const PaperPalette._(this._blend);
  final double _blend;
  bool get dark => _blend >= .5;
  Color _color(Color light, Color dark) => Color.lerp(light, dark, _blend)!;
  Color get background => _color(Paper.background, const Color(0xff141914));
  Color get ink => _color(Paper.ink, const Color(0xffe4e9df));
  Color get olive => _color(Paper.olive, const Color(0xffb1c5a0));
  Color get soft => _color(Paper.soft, const Color(0xff293329));
  Color get line => _color(Paper.line, const Color(0xff354135));
  Color get danger => _color(Paper.danger, const Color(0xffeda699));
  Color get muted => _color(const Color(0xff7a8172), const Color(0xff9aa494));
  Color get catalogMeta =>
      _color(const Color(0xff626e59), const Color(0xff9aa494));
  Color get videoSurface => _color(const Color(0xffe6e4db), Colors.black);
  Color get inputSurface =>
      _color(Colors.white.withValues(alpha: .7), const Color(0xff141914));
  TextStyle get title => Paper.title.copyWith(color: ink);

  @override
  PaperPalette copyWith({bool? dark}) =>
      dark == null ? this : PaperPalette(dark);

  @override
  PaperPalette lerp(covariant PaperPalette? other, double t) => other == null
      ? this
      : PaperPalette._(_blend + (other._blend - _blend) * t);

  @override
  bool operator ==(Object other) =>
      other is PaperPalette && other._blend == _blend;

  @override
  int get hashCode => _blend.hashCode;
}

abstract final class Paper {
  static PaperPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<PaperPalette>() ??
        PaperPalette(theme.brightness == Brightness.dark);
  }

  static const background = Color(0xfffaf8f3),
      ink = Color(0xff29332a),
      olive = Color(0xff53664a),
      soft = Color(0xffe8eddf),
      line = Color(0xffdce0d4),
      danger = Color(0xff924f46);
  static const title = TextStyle(
    fontFamily: 'PaperSerif',
    fontWeight: FontWeight.w400,
    fontSize: 23,
    color: ink,
  );
  static ThemeData get theme => _theme(false);
  static ThemeData get darkTheme => _theme(true);
  static ThemeData _theme(bool dark) {
    final p = PaperPalette(dark);
    return ThemeData(
      useMaterial3: true,
      extensions: [p],
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: p.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: olive,
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: p.olive,
        surface: p.background,
        error: p.danger,
        onSurface: p.ink,
        onSurfaceVariant: p.olive,
        outline: p.line,
        surfaceContainerHighest: p.soft,
      ),
      dividerColor: p.line,
      textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: 14, color: p.ink),
        bodySmall: TextStyle(fontSize: 12, color: p.olive),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      iconTheme: IconThemeData(color: p.olive, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: p.soft.withValues(alpha: .55),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: p.olive.withValues(alpha: .5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.olive,
          foregroundColor: p.background,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: p.olive.withValues(alpha: .5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? p.soft : ink,
        contentTextStyle: const TextStyle(color: Color(0xfff0f3eb)),
        actionTextColor: dark ? p.olive : soft,
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.background,
        constraints: const BoxConstraints(maxWidth: double.infinity),
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(21)),
        ),
      ),
    );
  }
}

Widget iconAction(String label, IconData icon, VoidCallback? onTap) =>
    IconButton(
      tooltip: label,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      icon: Icon(icon),
    );
Widget actionLabel(IconData icon, String label) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [Icon(icon, size: 18), const SizedBox(width: 7), Text(label)],
);
Widget note(String text) => Builder(
  builder: (context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.7,
        color: Paper.of(context).olive,
      ),
    ),
  ),
);

class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined, size: 35),
          const SizedBox(height: 15),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 15), action!],
        ],
      ),
    ),
  );
}

/// Shared page timing; read the current preference again when navigating back.
class PaperPageRoute<T> extends MaterialPageRoute<T> {
  PaperPageRoute({required super.builder, super.settings}) : _fade = false;
  PaperPageRoute.fade({required super.builder, super.settings}) : _fade = true;

  final bool _fade;
  bool get _reduced => MediaQuery.disableAnimationsOf(navigator!.context);

  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : const Duration(milliseconds: 240);
  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : const Duration(milliseconds: 160);

  // Video previews previously used a standalone fade. Keep that page from
  // acquiring the platform's coordinated outgoing-page zoom/slide as well.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      !_fade && super.canTransitionFrom(previousRoute);
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      !_fade && super.canTransitionTo(nextRoute);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : _fade
      ? FadeTransition(opacity: animation, child: child)
      : super.buildTransitions(context, animation, secondaryAnimation, child);
}

// Popup routes keep their own controller. Refresh it before either direction,
// including when the system preference changed while the popup was open.
mixin _PaperPopupMotion<T> on TransitionRoute<T> {
  bool get _reduced => MediaQuery.disableAnimationsOf(navigator!.context);

  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : const Duration(milliseconds: 240);
  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : const Duration(milliseconds: 160);

  void _updateTiming() {
    controller!
      ..duration = transitionDuration
      ..reverseDuration = reverseTransitionDuration;
  }

  @override
  TickerFuture didPush() {
    _updateTiming();
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    _updateTiming();
    return super.didPop(result);
  }
}

class _PaperSheetRoute<T> extends ModalBottomSheetRoute<T>
    with _PaperPopupMotion<T> {
  _PaperSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.constraints,
    super.isDismissible,
    super.enableDrag,
  }) : super(
         isScrollControlled: true,
         useSafeArea: true,
         sheetAnimationStyle: const AnimationStyle(
           duration: Duration(milliseconds: 240),
           reverseDuration: Duration(milliseconds: 160),
         ),
       );
}

class _PaperDialogRoute<T> extends DialogRoute<T> with _PaperPopupMotion<T> {
  _PaperDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
  }) : super(
         barrierColor:
             DialogTheme.of(context).barrierColor ??
             Theme.of(context).dialogTheme.barrierColor ??
             Colors.black54,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );
}

Future<T?> paperDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _PaperDialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

Future<T?> paperSheet<T>(
  BuildContext context,
  Widget child, {
  bool dismissible = true,
  BoxConstraints? constraints,
}) async {
  final navigator = Navigator.of(context);
  final route = _PaperSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    constraints: constraints,
    isDismissible: dismissible,
    enableDrag: dismissible,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    ),
  );
  final result = await navigator.push(route);
  // Form-owned controllers must outlive the sheet's closing animation.
  await route.completed;
  return result;
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.children,
    this.closeEnabled = true,
    this.footer,
  });
  final String title;
  final List<Widget> children;
  final bool closeEnabled;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .88,
    ),
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A landscape IME can leave only about 114dp above the keyboard.
          // Keep the focused fields mounted and let actions scroll with them.
          final compact = constraints.maxHeight < 180;
          final actions = footer == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(width: double.infinity, child: footer),
                );
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              compact ? 4 : 10,
              20,
              compact ? 8 : 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Paper.of(context).title.copyWith(fontSize: 21),
                      ),
                    ),
                    iconAction(
                      '关闭面板',
                      Icons.close,
                      closeEnabled ? () => Navigator.pop(context) : null,
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...children,
                        if (compact && actions != null) actions,
                      ],
                    ),
                  ),
                ),
                if (!compact && actions != null) actions,
              ],
            ),
          );
        },
      ),
    ),
  );
}
