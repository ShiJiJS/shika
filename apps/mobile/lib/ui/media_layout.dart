import 'package:flutter/material.dart';

import 'dart:math';

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
      max(52, MediaQuery.textScalerOf(context).scale(14) * 1.5 + 26);
  static double scope(BuildContext context) =>
      max(44, MediaQuery.textScalerOf(context).scale(12) * 3.4);
  static bool largeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(13) > 17;
  static double toolbar(BuildContext context) => largeText(context)
      ? max(44, MediaQuery.textScalerOf(context).scale(13) * 1.5 + 16) * 2 + 16
      : 58;
  static Duration motion(BuildContext context, int milliseconds) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
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
      padding: const EdgeInsets.fromLTRB(16, 2, 12, 14),
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
