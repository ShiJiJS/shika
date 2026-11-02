import 'package:flutter/material.dart';

import 'media_layout.dart';
import 'paper.dart';

class MediaHistoryEmpty extends StatelessWidget {
  const MediaHistoryEmpty({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 48),
    child: Text(
      '还没有观看记录',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        height: 1.8,
        color: Paper.of(context).muted,
      ),
    ),
  );
}

/// Shared history presentation; the owning catalog retains its source/query.
class MediaHistoryHeader extends StatelessWidget {
  const MediaHistoryHeader({
    super.key,
    required this.label,
    required this.count,
  });
  final String label, count;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaLayout.historyHeader(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MediaLayout.historyMeta.copyWith(
                color: Paper.of(context).catalogMeta,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count,
            style: MediaLayout.historyMeta.copyWith(
              color: Paper.of(context).catalogMeta,
            ),
          ),
        ],
      ),
    ),
  );
}

class MediaHistoryRow extends StatelessWidget {
  const MediaHistoryRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.cover,
    required this.onTap,
    this.subtitleKey,
    this.selecting = false,
    this.selected = false,
  });
  final String title, subtitle;
  final Widget cover;
  final VoidCallback? onTap;
  final Key? subtitleKey;
  final bool selecting, selected;
  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    return Semantics(
      button: true,
      selected: selecting ? selected : null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.line)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              SizedBox(width: 64, height: 78, child: cover),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MediaLayout.historyTitle.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      key: subtitleKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MediaLayout.historyMeta.copyWith(
                        color: p.catalogMeta,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selecting
                    ? selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked
                    : Icons.chevron_right,
                size: selecting ? 22 : 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
