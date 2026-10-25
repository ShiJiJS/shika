import 'package:flutter/material.dart';

import 'paper.dart';

/// A compact visible switch with a full-row pointer/keyboard/semantic action.
/// Text keeps the system scale and determines the row height.
class PaperPreferenceSwitch extends StatelessWidget {
  const PaperPreferenceSwitch({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    void toggle() => onChanged?.call(!value);
    return Semantics(
      label: subtitle.isEmpty ? title : '$title，$subtitle',
      toggled: value,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : toggle,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onChanged == null ? null : toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 15, height: 23 / 15),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.7,
                              color: p.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 13),
                  SizedBox(
                    width: 48,
                    height: 40,
                    child: ExcludeFocus(
                      child: Transform.scale(
                        scale: 10 / 13,
                        alignment: Alignment.centerRight,
                        child: Switch(
                          value: value,
                          onChanged: onChanged,
                          thumbColor: WidgetStatePropertyAll(p.background),
                          trackColor: WidgetStatePropertyAll(
                            value ? p.olive : p.line,
                          ),
                          trackOutlineColor: WidgetStatePropertyAll(
                            value ? p.olive : p.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
