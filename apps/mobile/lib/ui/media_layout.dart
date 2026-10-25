import 'package:flutter/material.dart';

import 'dart:math';

import 'paper.dart';

/// Frozen library-first P2 dimensions, excluding the platform's safe areas.
abstract final class MediaLayout {
  static const header = 52.0, navigation = 49.0, kindBar = 40.0;
  static const side = 16.0, columnGap = 12.0, rowGap = 18.0;
  static double headerExtent(BuildContext context) =>
      max(header, MediaQuery.textScalerOf(context).scale(24) * 1.25 + 12);
  static double kindExtent(BuildContext context) =>
      max(kindBar, MediaQuery.textScalerOf(context).scale(15) * 1.5 + 16);
  static double cover(double width) => width <= 380 ? 185 : 211;
  static double tile(
    double width, {
    TextScaler scaler = TextScaler.noScaling,
  }) =>
      cover(width) +
      79 +
      max(0, scaler.scale(16) - 16) * 1.5 +
      max(0, scaler.scale(12) * 1.5 - 28) +
      max(0, scaler.scale(11) - 11) * 1.4;
  static double meta(BuildContext context) =>
      max(28, MediaQuery.textScalerOf(context).scale(12) * 1.5);
  static double search(BuildContext context) =>
      max(55, MediaQuery.textScalerOf(context).scale(16) * 1.5 + 31);
  static double scope(BuildContext context) =>
      max(44, MediaQuery.textScalerOf(context).scale(12) * 3.4);
  static const continuationMeta = TextStyle(fontSize: 12, height: 1.5);
  static final continuationTitle = Paper.title.copyWith(
    fontSize: 16,
    height: 1.5,
  );
  static double continuation(
    BuildContext context, {
    required String title,
    required String position,
  }) {
    // Native fallback fonts can exceed fontSize * height. Measure the same
    // styles/text as the row instead of guessing or clipping enlarged text.
    double line(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return max(
      85,
      line('继续阅读', continuationMeta) +
          line(title, continuationTitle) +
          line(position, continuationMeta) +
          25, // 17 padding, two 3dp gaps, 2dp progress line.
    );
  }

  static bool largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(13) > 17;
  static double toolbar(BuildContext context) => largeText(context)
      ? max(44, MediaQuery.textScalerOf(context).scale(13) * 1.5 + 16) * 2 + 16
      : 60;
  static Duration motion(BuildContext context, int milliseconds) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

/// Both media catalogs use the same reference search geometry. Taller system
/// text grows the field rather than clipping or reducing its type size.
class MediaCatalogSearch extends StatelessWidget {
  const MediaCatalogSearch({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.hint,
    required this.filterLabel,
    required this.onFilter,
    required this.onChanged,
  });
  final Key fieldKey;
  final TextEditingController controller;
  final String hint, filterLabel;
  final VoidCallback onFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    return SizedBox(
      height: MediaLayout.search(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 44,
              child: iconAction(filterLabel, Icons.filter_list, onFilter),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                style: const TextStyle(fontSize: 16, height: 1.5),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: p.muted),
                  isDense: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: p.line),
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps P2's compact row at ordinary type sizes and gives controls their own
/// row when system text scaling would crowd the count or truncate actions.
class MediaCatalogToolbar extends StatelessWidget {
  const MediaCatalogToolbar({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaLayout.toolbar(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: MediaLayout.largeText(context)
          ? Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: children.first,
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: children.skip(1).toList(),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: children.first),
                ...children.skip(1),
              ],
            ),
    ),
  );
}
