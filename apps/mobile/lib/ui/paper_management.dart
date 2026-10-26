import 'package:flutter/material.dart';

import 'media_layout.dart';
import 'paper.dart';

/// Management pages share the frozen full-height Paper heading.
class PaperManagementHeader extends StatelessWidget {
  const PaperManagementHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.closeLabel = '返回设置',
    this.actions = const [],
  });
  final String title, closeLabel;
  final VoidCallback? onClose;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Container(
    height: MediaLayout.headerExtent(context),
    padding: const EdgeInsets.only(left: 20, right: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Paper.of(context).line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Paper.of(context).title,
          ),
        ),
        ...actions,
        iconAction(closeLabel, Icons.close, onClose),
      ],
    ),
  );
}

/// Open actions and task rows keep their labels on the content's left edge.
class PaperActionRow extends StatelessWidget {
  const PaperActionRow({
    super.key,
    required this.title,
    required this.onTap,
    this.details = const [],
    this.trailing,
  });
  final String title;
  final VoidCallback? onTap;
  final List<Widget> details;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 65),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: onTap == null ? p.catalogMeta : p.ink,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      ...details,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A long form retains one viewport when its actions move above a real IME.
class PaperManagementForm extends StatelessWidget {
  const PaperManagementForm({
    super.key,
    required this.children,
    required this.footer,
    this.controller,
  });
  final List<Widget> children;
  final Widget footer;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inline =
          MediaQuery.viewInsetsOf(context).bottom > 0 ||
          constraints.maxHeight < 220;
      return Column(
        children: [
          Expanded(
            child: ListView(
              key: const PageStorageKey('management-form-content'),
              controller: controller,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              children: [
                ...children,
                if (inline)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: footer,
                  ),
              ],
            ),
          ),
          if (!inline)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: footer,
            ),
        ],
      );
    },
  );
}
