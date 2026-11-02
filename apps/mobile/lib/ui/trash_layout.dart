import 'package:flutter/material.dart';

import 'media_layout.dart';
import 'paper.dart';

/// Both trash types share one scroll surface and the same action hierarchy.
class TrashLayout extends StatelessWidget {
  const TrashLayout({
    super.key,
    required this.listKey,
    required this.children,
    required this.actions,
    required this.onRefresh,
    this.controller,
    this.loading = false,
    this.topInset = 0,
  });
  final Key listKey;
  final List<Widget> children;
  final Widget actions;
  final Future<void> Function() onRefresh;
  final ScrollController? controller;
  final bool loading;
  final double topInset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final pinned =
          MediaQuery.viewInsetsOf(context).bottom == 0 &&
          constraints.maxHeight >= (MediaLayout.largeText(context) ? 360 : 220);
      return Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          Flexible(
            key: const ValueKey('trash-content'),
            fit: pinned ? FlexFit.loose : FlexFit.tight,
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                key: listKey,
                controller: controller,
                // A short result keeps its actions directly after the rows;
                // a full, bounded page uses the available height and pins them.
                // Keep the viewport type stable as the IME changes the dock;
                // replacing it would dispose the focused search field.
                shrinkWrap: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, topInset, 20, pinned ? 0 : 22),
                children: [...children, if (!pinned) actions],
              ),
            ),
          ),
          if (pinned)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: actions,
            ),
        ],
      );
    },
  );
}

class TrashActions extends StatelessWidget {
  const TrashActions({
    super.key,
    required this.count,
    required this.onRestore,
    required this.onPermanent,
    required this.restoreKey,
    required this.permanentKey,
    this.restoring = false,
    this.selectionLabel,
    this.showPermanent = true,
    this.children = const [],
  });
  final int count;
  final String? selectionLabel;
  final VoidCallback? onRestore, onPermanent;
  final Key restoreKey, permanentKey;
  final bool restoring;
  final bool showPermanent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Paper.of(context).line)),
    ),
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (MediaLayout.largeText(context))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              selectionLabel ?? '已选 $count',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!MediaLayout.largeText(context))
              Text(
                selectionLabel ?? '已选 $count',
                style: const TextStyle(fontSize: 13),
              ),
            OutlinedButton(
              key: restoreKey,
              onPressed: onRestore,
              child: Text(restoring ? '恢复中…' : '恢复所选'),
            ),
            if (showPermanent)
              TextButton(
                key: permanentKey,
                style: TextButton.styleFrom(
                  foregroundColor: Paper.of(context).danger,
                  textStyle: const TextStyle(fontWeight: FontWeight.normal),
                ),
                onPressed: onPermanent,
                child: const Text('永久删除'),
              ),
          ],
        ),
        ...children,
      ],
    ),
  );
}

class TrashEntryRow extends StatelessWidget {
  const TrashEntryRow({
    super.key,
    required this.title,
    required this.path,
    required this.selected,
    required this.onToggle,
    required this.onRestore,
    required this.restoreKey,
    this.details = const [],
  });
  final String title, path;
  final bool selected;
  final VoidCallback? onToggle, onRestore;
  final Key restoreKey;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    final restore = TextButton(
      key: restoreKey,
      onPressed: onRestore,
      child: const Text('恢复'),
    );
    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: '选择回收内容 $title',
              child: SizedBox(
                width: 32,
                height: 44,
                child: PaperCheckbox(
                  value: selected,
                  onChanged: onToggle == null ? null : (_) => onToggle!(),
                  side: BorderSide(color: p.olive),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: p.title.copyWith(fontSize: 15, height: 1.6),
                  ),
                  Text(
                    path,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.7,
                      color: p.catalogMeta,
                    ),
                  ),
                  ...details,
                  if (MediaLayout.largeText(context))
                    Align(alignment: Alignment.centerRight, child: restore),
                ],
              ),
            ),
            if (!MediaLayout.largeText(context)) restore,
          ],
        ),
      ),
    );
  }
}
