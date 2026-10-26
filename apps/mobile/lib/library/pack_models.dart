import 'models.dart';

class PackProgress {
  const PackProgress({
    required this.pageId,
    required this.offsetRatio,
    required this.completed,
    required this.revision,
    required this.updatedAt,
    this.pageIndex,
  });
  final String? pageId;
  final int? pageIndex;
  final double offsetRatio, updatedAt;
  final bool completed;
  final int revision;
}

/// A catalog item is a whole pack. Images belong to its reader, not this list.
class LibraryPack {
  LibraryPack({
    required this.id,
    required this.rootId,
    required this.path,
    required this.name,
    required this.pageCount,
    required this.readableCount,
    required this.contentVersion,
    required this.status,
    required this.createdAt,
    this.title,
    this.author,
    this.number,
    this.error,
    this.cover,
    this.progress,
    Iterable<String> tags = const [],
    Map<String, String> tagNames = const {},
  }) : tags = Set.unmodifiable(tags),
       tagNames = Map.unmodifiable(tagNames);
  final String id, rootId, path, name, status;
  final int pageCount, readableCount, contentVersion;
  final double createdAt;
  final String? title, author, number;
  String get displayTitle => title?.trim().isNotEmpty == true ? title! : name;
  String get catalogSubtitle =>
      author?.trim().isNotEmpty == true ? author! : '$readableCount 张可读';
  String get readerSubtitle => [
    if (author?.trim().isNotEmpty == true) author!,
    if (number?.trim().isNotEmpty == true) number!,
  ].join(' · ');
  final String? error;
  final MediaSource? cover;
  final PackProgress? progress;
  final Set<String> tags;
  final Map<String, String> tagNames;
  String get readingBadge {
    final value = progress;
    if (value == null) return '';
    if (value.completed) return '已读';
    final index = value.pageIndex;
    return index != null && index >= 0 && index < pageCount
        ? '在读 · ${index + 1}'
        : '在读';
  }

  PackReadState get readState => progress == null
      ? PackReadState.unread
      : progress!.completed
      ? PackReadState.completed
      : PackReadState.reading;
}

class PackTag {
  const PackTag(this.id, this.name, this.count);
  final String id, name;
  final int count;
}

class PackTagNames {
  PackTagNames({
    required Map<String, String> names,
    Iterable<String> missing = const [],
  }) : names = Map.unmodifiable(names),
       missing = Set.unmodifiable(missing);
  final Map<String, String> names;
  final Set<String> missing;
}

/// The server owns total and offset, even when only one page is cached.
class CatalogPage<T> {
  CatalogPage({
    required Iterable<T> items,
    required this.total,
    required this.offset,
    required this.limit,
    this.anchorIndex,
  }) : items = List.unmodifiable(items);
  final List<T> items;
  final int total, offset, limit;
  final int? anchorIndex;
  bool get hasMore => offset + items.length < total;
}
