import 'package:flutter/material.dart';

class PaperPalette {
  const PaperPalette(this.dark);
  final bool dark;
  Color get background => dark ? const Color(0xff141914) : Paper.background;
  Color get ink => dark ? const Color(0xffe4e9df) : Paper.ink;
  Color get olive => dark ? const Color(0xffb1c5a0) : Paper.olive;
  Color get soft => dark ? const Color(0xff293329) : Paper.soft;
  Color get line => dark ? const Color(0xff354135) : Paper.line;
  Color get danger => dark ? const Color(0xffeda699) : Paper.danger;
  Color get muted => dark ? const Color(0xff9aa494) : const Color(0xff7a8172);
  Color get videoSurface => dark ? Colors.black : const Color(0xffe6e4db);
  TextStyle get title => Paper.title.copyWith(color: ink);
}

abstract final class Paper {
  static PaperPalette of(BuildContext context) =>
      PaperPalette(Theme.of(context).brightness == Brightness.dark);
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
    child: Padding(
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

Future<T?> paperSheet<T>(
  BuildContext context,
  Widget child, {
  bool dismissible = true,
}) async {
  final navigator = Navigator.of(context);
  final route = ModalBottomSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 240),
    ),
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
  });
  final String title;
  final List<Widget> children;
  final bool closeEnabled;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .88,
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
