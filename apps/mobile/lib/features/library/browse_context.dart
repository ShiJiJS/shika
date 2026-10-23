import 'dart:convert';

import '../../library/models.dart';

enum MediaKind { video, pack }

enum BrowseSource { library, tags, recent }

/// An entry page's selection, independent of the active viewing session.
/// Pack-specific queries will be added with the LF1 data contract.
class VideoBrowseContext {
  VideoBrowseContext({
    VideoQuery? query,
    this.search = '',
    this.source = BrowseSource.library,
    this.scrollOffset = 0,
    this.scrollAnchor,
  }) : query = query ?? VideoQuery();

  final VideoQuery query;
  final String search;
  final BrowseSource source;
  final double scrollOffset;
  final String? scrollAnchor;
  MediaKind get kind => MediaKind.video;

  String get queryKey => jsonEncode([
    source.name,
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
    double? scrollOffset,
    String? scrollAnchor,
  }) => VideoBrowseContext(
    query: query ?? this.query,
    search: search ?? this.search,
    source: source ?? this.source,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    scrollAnchor: scrollAnchor ?? this.scrollAnchor,
  );
}
