import 'package:flutter/material.dart';

import '../ui/paper.dart';

/// Shared safe areas and navigation. LF0 retains the legacy destinations;
/// LF4 supplies the approved library/tags/recent/settings destinations.
class AppDestination {
  const AppDestination(this.id, this.label, this.icon);
  final String id, label;
  final IconData icon;
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
  });

  final Widget header, content;
  final List<AppDestination> destinations;
  final String selected;
  final ValueChanged<String> onNavigate;
  final bool showNavigation, navigationEnabled;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('app-shell'),
    bottomNavigationBar: showNavigation
        ? SafeArea(top: false, child: _navigation(context))
        : null,
    body: SafeArea(
      bottom: !showNavigation,
      child: Column(
        children: [
          header,
          Expanded(child: content),
        ],
      ),
    ),
  );

  Widget _navigation(BuildContext context) => Container(
    key: const Key('app-navigation'),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Paper.of(context).line)),
    ),
    child: Center(
      heightFactor: 1,
      child: SizedBox(
        width: 300,
        height: 52,
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
                        style: TextStyle(
                          fontSize: 10,
                          color: selected == tab.id
                              ? Paper.of(context).olive
                              : Paper.of(context).muted,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(top: 3),
                        width: 18,
                        height: 2,
                        color: selected == tab.id
                            ? Paper.of(context).olive
                            : Colors.transparent,
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
