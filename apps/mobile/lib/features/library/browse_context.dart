import 'dart:convert';

import '../../library/models.dart';

export '../../library/models.dart' show MediaKind, BrowseSource, VideoSort;

/// An entry page's selection, independent of the active viewing session.
/// Scroll anchors belong to the view, not query identity: returning to a card
/// must not create a new playback range or record another open.
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
/// Pack and video tag IDs are separate namespaces, even for equal names;
/// switching media kind must not reuse the other kind's query or selection.
class PackBrowseContext {
  PackBrowseContext({
    PackQuery? query,
    BrowseSource? source,
    this.scrollOffset = 0,
    this.scrollAnchor,
    this.scrollIndex = 0,
    this.scrollInset = 0,
  }) : query = source == null
           ? query ?? PackQuery()
           : (query ?? PackQuery()).copy(source: source);
  final PackQuery query;
  BrowseSource get source => query.source;
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
