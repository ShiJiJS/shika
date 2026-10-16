import 'package:flutter/material.dart';

abstract final class Paper {
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
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: olive,
      primary: olive,
      surface: background,
      error: danger,
    ),
    dividerColor: line,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, color: ink),
      bodySmall: TextStyle(fontSize: 12, color: olive),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    iconTheme: const IconThemeData(color: olive, size: 22),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: .55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xffbac5af)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: olive,
        foregroundColor: background,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: Color(0xffbac5af)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: ink,
      actionTextColor: soft,
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: background,
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(21)),
      ),
    ),
  );
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
Widget note(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Text(
    text,
    style: const TextStyle(fontSize: 12, height: 1.7, color: Paper.olive),
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

Future<T?> paperSheet<T>(BuildContext context, Widget child) async {
  final navigator = Navigator.of(context);
  final route = ModalBottomSheetRoute<T>(
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    isScrollControlled: true,
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
  const SheetFrame({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;
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
                  child: Text(title, style: Paper.title.copyWith(fontSize: 21)),
                ),
                iconAction('关闭面板', Icons.close, () => Navigator.pop(context)),
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
