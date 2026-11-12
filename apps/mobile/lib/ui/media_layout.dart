import 'package:flutter/material.dart';

import 'dart:math';

import 'paper.dart';

/// Library geometry, excluding the platform's safe areas.
abstract final class MediaLayout {
  static const header = 52.0, navigation = 65.0, kindBar = 48.0;
  // The caption retains a 48dp menu target; subtract its extra 10dp from
  // the row gap so the cover-to-cover rhythm matches the 38dp HTML caption.
  static const side = 16.0, columnGap = 12.0, rowGap = 8.0;
  static double headerExtent(BuildContext context) =>
      max(header, MediaQuery.textScalerOf(context).scale(24) * 1.25 + 12);
  static double kindExtent(BuildContext context) =>
      max(kindBar, MediaQuery.textScalerOf(context).scale(17) * 1.5 + 16);
  static double cover(double width) => width < 375 ? 192 : 211;
  static final cardTitle = Paper.title.copyWith(fontSize: 16, height: 1.5);
  static const cardTags = TextStyle(fontSize: 13, height: 1.6);
  static const cardMeta = TextStyle(fontSize: 12, height: 1.5);
  static final historyTitle = Paper.title.copyWith(fontSize: 18);
  static const historyMeta = TextStyle(fontSize: 13);
  static double historyRow(
    BuildContext context, {
    Iterable<({String title, String subtitle})> items = const [],
  }) {
    // Fallback glyph metrics differ even within Chinese. Measure the actual
    // bounded window, not one sample that can miss a taller title or numeral.
    var title = line(context, '最近 Aa', historyTitle);
    var subtitle = line(context, '第 3 / 6 张', historyMeta);
    for (final item in items) {
      title = max(title, line(context, item.title, historyTitle));
      subtitle = max(subtitle, line(context, item.subtitle, historyMeta));
    }
    return max(78, title + 8 + subtitle) + 33;
  }

  static double historyHeader(BuildContext context) =>
      line(context, '最近预览的视频 Aa', historyMeta) + 32;
  static double line(BuildContext context, String text, TextStyle style) {
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
    final result = painter.height;
    painter.dispose();
    return result;
  }

  static double tile(BuildContext context, double width) =>
      cover(width) + 8 + line(context, '标题 Aa', cardTitle) + meta(context);
  static int columns(BuildContext context) {
    // Keyboard insets must not turn a portrait grid into a landscape grid.
    final media = MediaQuery.of(context);
    final width = media.size.width - media.viewPadding.horizontal;
    final height = media.size.height - media.viewPadding.vertical;
    return width > height && height <= 500 ? 4 : 2;
  }

  static double meta(BuildContext context) => max(
    48,
    line(context, '信息 Aa', cardMeta) + 4 + line(context, '标签 Aa', cardTags),
  );
  static double search(BuildContext context) =>
      max(56, MediaQuery.textScalerOf(context).scale(16) * 1.5 + 32);
  static double scope(BuildContext context) =>
      max(48, MediaQuery.textScalerOf(context).scale(12) * 3.4);
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
      : 52;
  static Duration motion(BuildContext context, int milliseconds) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

/// Last-rendered geometry also owns the index/pixel conversion during reflow.
class MediaGridGeometry {
  const MediaGridGeometry(this.columns, this.stride, this.header);
  final int columns;
  final double stride, header;
  bool reflows(MediaGridGeometry next) =>
      columns != next.columns || stride != next.stride;
}

/// A retained list failure uses the same readable gutter and retry treatment.
class MediaCatalogFailure extends StatelessWidget {
  const MediaCatalogFailure({
    super.key,
    required this.message,
    required this.retryKey,
    required this.onRetry,
    this.side = 16,
  });
  final String message;
  final Key retryKey;
  final VoidCallback? onRetry;
  final double side;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: side, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '当前列表已保留：$message',
            style: TextStyle(fontSize: 12, color: Paper.of(context).danger),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(key: retryKey, onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                style: const TextStyle(fontSize: 16, height: 1.5),
                decoration: InputDecoration(
                  hintText: hint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                  hintStyle: TextStyle(color: p.muted, fontSize: 14),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    maxWidth: 40,
                    minHeight: 40,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: p.soft.withValues(alpha: .45),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: p.olive, width: 1),
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: max(
                60,
                MediaQuery.textScalerOf(context).scale(14) * 2 + 29,
              ),
              child: Tooltip(
                message: filterLabel,
                child: MediaCatalogAction(
                  key: ValueKey(filterLabel),
                  onPressed: onFilter,
                  icon: Icons.filter_list,
                  label: '筛选',
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keep metadata, tags and the action target in one compact caption row.
class MediaCardCaption extends StatelessWidget {
  const MediaCardCaption({
    super.key,
    required this.tagKey,
    required this.tags,
    required this.menuLabel,
    this.metadata = '',
    this.onMenu,
  });
  final Key tagKey;
  final String metadata, tags, menuLabel;
  final VoidCallback? onMenu;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaLayout.meta(context),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (metadata.isNotEmpty)
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MediaLayout.cardMeta.copyWith(
                    color: Paper.of(context).catalogMeta,
                  ),
                ),
              if (metadata.isNotEmpty && tags.isNotEmpty)
                const SizedBox(height: 4),
              Text(
                tags,
                key: tagKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MediaLayout.cardTags.copyWith(
                  color: Paper.of(context).olive,
                ),
              ),
            ],
          ),
        ),
        if (onMenu != null)
          IconButton(
            tooltip: menuLabel,
            onPressed: onMenu,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: const Icon(Icons.more_horiz),
          ),
      ],
    ),
  );
}

class MediaSelectionMark extends StatelessWidget {
  const MediaSelectionMark(this.selected, {super.key});
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? Paper.of(context).olive : Paper.of(context).background,
      border: Border.all(color: Paper.of(context).background, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
    ),
    child: selected
        ? Icon(Icons.check, size: 16, color: Paper.of(context).background)
        : null,
  );
}

/// Filters describe the current result and can be removed independently.
/// The fixed-height horizontal row also keeps catalogue return geometry stable.
class MediaFilterSummary extends StatelessWidget {
  const MediaFilterSummary({
    super.key,
    required this.filters,
    required this.clear,
  });
  final List<({String id, String label, VoidCallback remove})> filters;
  final VoidCallback clear;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaLayout.scope(context),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final filter in filters)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                key: ValueKey(filter.id),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                backgroundColor: Paper.of(context).soft,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                label: Text(filter.label),
                onDeleted: filter.remove,
                deleteButtonTooltipMessage: '取消${filter.label}',
              ),
            ),
          TextButton(onPressed: clear, child: const Text('清除全部')),
        ],
      ),
    ),
  );
}

class MediaSortLabel extends StatelessWidget {
  const MediaSortLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more, size: 18),
      ],
    ),
  );
}

/// Compact visual controls retain a full Android touch target without a frame.
class MediaCatalogAction extends StatelessWidget {
  const MediaCatalogAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.fontSize = 13,
  });
  final String label;
  final double fontSize;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      textStyle: TextStyle(fontSize: fontSize),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

/// Assignment and filter sheets share a quiet, explicit checkbox treatment.
class MediaTagChoice extends StatelessWidget {
  const MediaTagChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  @override
  Widget build(BuildContext context) => PaperFilterChip(
    label: Text(
      label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    ),
    selected: selected,
    onSelected: onSelected,
    showCheckmark: false,
    avatar: Icon(
      selected ? Icons.check_box : Icons.check_box_outline_blank,
      size: 18,
      color: Paper.of(context).olive,
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    backgroundColor: Colors.transparent,
    selectedColor: Paper.of(context).soft,
    side: BorderSide.none,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  );
}

/// Regular checkbox columns at ordinary sizes, fewer columns for large text.
class MediaTagChoices extends StatelessWidget {
  const MediaTagChoices({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (constraints.maxWidth / (100 * scale)).floor().clamp(
        1,
        6,
      );
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
        ],
      );
    },
  );
}

/// Batch actions replace navigation while selecting, with identical geometry
/// for videos and packs. The selected IDs remain owned by each catalogue.
class MediaSelectionActions extends StatelessWidget {
  const MediaSelectionActions({
    super.key,
    required this.kind,
    required this.addTags,
    required this.trash,
    this.canTrash = true,
  });
  final String kind;
  final VoidCallback? addTags, trash;
  final bool canTrash;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Paper.of(context).line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              key: ValueKey('$kind-add-selected-tags'),
              onPressed: addTags,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('添加标签', textAlign: TextAlign.center),
            ),
          ),
          if (canTrash) ...[
            SizedBox(
              width: 1,
              height: 20,
              child: ColoredBox(color: Paper.of(context).line),
            ),
            Expanded(
              child: TextButton.icon(
                key: ValueKey('$kind-delete-selected'),
                onPressed: trash,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: Paper.of(context).danger,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('移入回收站', textAlign: TextAlign.center),
              ),
            ),
          ],
        ],
      ),
    ),
  );
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: children.skip(1).toList(),
                      ),
                    ),
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
