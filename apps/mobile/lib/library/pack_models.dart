import 'models.dart';

class PackProgress {
  const PackProgress({
    required this.pageId,
    required this.offsetRatio,
    required this.completed,
    required this.revision,
    required this.updatedAt,
  });
  final String? pageId;
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
    this.error,
    this.cover,
    this.progress,
    Iterable<String> tags = const [],
  }) : tags = Set.unmodifiable(tags);
  final String id, rootId, path, name, status;
  final int pageCount, readableCount, contentVersion;
  final double createdAt;
  final String? error;
  final MediaSource? cover;
  final PackProgress? progress;
  final Set<String> tags;
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

/// The server owns total and offset, even when only one page is cached.
class CatalogPage<T> {
  CatalogPage({
    required Iterable<T> items,
    required this.total,
    required this.offset,
    required this.limit,
  }) : items = List.unmodifiable(items);
  final List<T> items;
  final int total, offset, limit;
  bool get hasMore => offset + items.length < total;
}
