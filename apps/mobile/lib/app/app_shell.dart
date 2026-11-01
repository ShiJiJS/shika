import 'package:flutter/material.dart';

import 'dart:math';

import '../ui/paper.dart';
import '../ui/paper_icons.dart';

/// Shared safe areas and navigation. LF0 retains the legacy destinations;
/// LF4 supplies the approved library/tags/recent/settings destinations.
class AppDestination {
  const AppDestination(this.id, this.label, this.icon, {this.glyph});
  final String id, label;
  final IconData icon;
  final PaperGlyph? glyph;
}

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.header,
    required this.content,
    required this.destinations,
    required this.selected,
    required this.onNavigate,
    required this.showNavigation,
    this.navigationEnabled = true,
    this.navigationExtent = 52,
    this.navigationWidth = 300,
  });

  final Widget header, content;
  final List<AppDestination> destinations;
  final String selected;
  final ValueChanged<String> onNavigate;
  final bool showNavigation, navigationEnabled;
  final double navigationExtent, navigationWidth;

  @override
  Widget build(BuildContext context) {
    final navigationVisible =
        showNavigation && MediaQuery.viewInsetsOf(context).bottom == 0;
    return Scaffold(
      key: const Key('app-shell'),
      bottomNavigationBar: navigationVisible
          ? SafeArea(top: false, child: _navigation(context))
          : null,
      body: SafeArea(
        bottom: !navigationVisible,
        child: Column(
          children: [
            header,
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _navigation(BuildContext context) => Container(
    key: const Key('app-navigation'),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Paper.of(context).line)),
    ),
    child: Center(
      heightFactor: 1,
      child: SizedBox(
        width: navigationWidth,
        height: max(
          navigationExtent,
          MediaQuery.textScalerOf(context).scale(10) * 1.6 + 26,
        ),
        child: Row(
          children: [
            for (final tab in destinations)
              Expanded(
                child: InkWell(
                  key: Key('nav-${tab.id}'),
                  onTap: navigationEnabled ? () => onNavigate(tab.id) : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (tab.glyph != null)
                        PaperIcon(
                          tab.glyph!,
                          size: 18,
                          color: selected == tab.id
                              ? Paper.of(context).olive
                              : Paper.of(context).muted,
                        )
                      else
                        Icon(
                          tab.icon,
                          size: 19,
                          color: selected == tab.id
                              ? Paper.of(context).olive
                              : Paper.of(context).muted,
                        ),
                      const SizedBox(height: 2),
                      Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected == tab.id
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected == tab.id
                              ? Paper.of(context).olive
                              : Paper.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
