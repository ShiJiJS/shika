import 'dart:convert';

import '../../library/models.dart';

export '../../library/models.dart' show MediaKind, BrowseSource, VideoSort;

/// An entry page's selection, independent of the active viewing session.
/// Pack-specific queries will be added with the LF1 data contract.
class VideoBrowseContext {
  VideoBrowseContext({
    VideoQuery? query,
    this.search = '',
    this.source = BrowseSource.library,
    this.sort = VideoSort.path,
    this.scrollOffset = 0,
    this.scrollAnchor,
    this.scrollIndex = 0,
    this.scrollInset = 0,
  }) : query = query ?? VideoQuery();

  final VideoQuery query;
  final String search;
  final BrowseSource source;
  final VideoSort sort;
  VideoEntryScope get entry =>
      VideoEntryScope(query: query, search: search, source: source, sort: sort);
  final double scrollOffset;
  final String? scrollAnchor;
  final int scrollIndex;
  final double scrollInset;
  MediaKind get kind => MediaKind.video;

  String get queryKey => jsonEncode([
    source.name,
    sort.name,
    query.folder,
    query.tags.toList()..sort(),
    query.orientation,
    query.duration,
    query.type,
    search,
  ]);

  VideoBrowseContext copyWith({
    VideoQuery? query,
    String? search,
    BrowseSource? source,
    VideoSort? sort,
    double? scrollOffset,
    String? scrollAnchor,
    int? scrollIndex,
    double? scrollInset,
  }) => VideoBrowseContext(
    query: query ?? this.query,
    search: search ?? this.search,
    source: source ?? this.source,
    sort: sort ?? this.sort,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    scrollAnchor: scrollAnchor ?? this.scrollAnchor,
    scrollIndex: scrollIndex ?? this.scrollIndex,
    scrollInset: scrollInset ?? this.scrollInset,
  );
}

/// A pack entry page keeps its own filters and return position.
class PackBrowseContext {
  PackBrowseContext({
    PackQuery? query,
    this.source = BrowseSource.library,
    this.scrollOffset = 0,
    this.scrollAnchor,
    this.scrollIndex = 0,
    this.scrollInset = 0,
  }) : query = query ?? PackQuery();
  final PackQuery query;
  final BrowseSource source;
  final double scrollOffset;
  final String? scrollAnchor;
  final int scrollIndex;
  final double scrollInset;
  MediaKind get kind => MediaKind.pack;
  String get queryKey => jsonEncode([source.name, query.toJson()]);
  PackBrowseContext copyWith({
    PackQuery? query,
    BrowseSource? source,
    double? scrollOffset,
    String? scrollAnchor,
    int? scrollIndex,
    double? scrollInset,
  }) => PackBrowseContext(
    query: query ?? this.query,
    source: source ?? this.source,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    scrollAnchor: scrollAnchor ?? this.scrollAnchor,
    scrollIndex: scrollIndex ?? this.scrollIndex,
    scrollInset: scrollInset ?? this.scrollInset,
  );
}
