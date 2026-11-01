import 'package:flutter/material.dart';

import 'media_layout.dart';
import 'paper.dart';

/// Settings inputs share the frozen reference's persistent labels and surfaces.
class PaperField extends StatefulWidget {
  const PaperField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  State<PaperField> createState() => _PaperFieldState();
}

class _PaperFieldState extends State<PaperField> with WidgetsBindingObserver {
  bool focused = false;
  final inputAnchor = GlobalKey();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final input = inputAnchor.currentContext;
      if (mounted && focused && input != null) {
        Scrollable.ensureVisible(input, alignment: .5);
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (focused) reveal();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Paper.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: BorderSide(color: palette.line),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) {
        focused = value;
        if (value) reveal();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 12, height: 1.7),
            ),
          ),
          const SizedBox(height: 7),
          Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: InputDecorationTheme(
                isDense: true,
                filled: true,
                fillColor: palette.inputSurface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: palette.olive),
                ),
              ),
            ),
            child: Semantics(
              key: inputAnchor,
              label: widget.label,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Readable values on the open Paper canvas, separate from text entry.
class PaperSettingRow extends StatelessWidget {
  const PaperSettingRow({super.key, required this.label, required this.child});
  final String label;
  final Widget child;
  static const decoration = InputDecoration(
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
  );
  @override
  Widget build(BuildContext context) {
    final large = MediaLayout.largeText(context);
    final labelWidget = Text(label, style: const TextStyle(fontSize: 14));
    final control = Semantics(
      label: label,
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.copyWith(
            titleMedium: TextStyle(
              fontSize: 14,
              color: Paper.of(context).olive,
            ),
          ),
        ),
        child: child,
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 55),
      padding: EdgeInsets.symmetric(vertical: large ? 8 : 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Paper.of(context).line)),
      ),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [labelWidget, const SizedBox(height: 4), control],
            )
          : Row(
              children: [
                Expanded(child: labelWidget),
                const SizedBox(width: 12),
                SizedBox(width: 155, child: control),
              ],
            ),
    );
  }
}
