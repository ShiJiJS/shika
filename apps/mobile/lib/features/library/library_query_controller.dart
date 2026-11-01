import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import 'browse_context.dart';

class VideoLibraryState {
  VideoLibraryState({
    required this.context,
    Iterable<LibraryVideo> items = const [],
    this.total = 0,
    this.loading = false,
    this.error = '',
    this.offset = 0,
    this.anchorIndex,
    this.beforeFailure = false,
    this.retryRestore = false,
  }) : items = List.unmodifiable(items);

  final VideoBrowseContext context;
  final List<LibraryVideo> items;
  final int total;
  final bool loading;
  final String error;
  final int offset;
  final int? anchorIndex;
  final bool beforeFailure;
  final bool retryRestore;
  bool get hasBefore => offset > 0;
  bool get hasAfter => offset + items.length < total;
}

/// Owns pagination, cancellation and stale responses behind one read interface.
/// Loading a page never changes the repository's active playback round.
class LibraryQueryController extends ChangeNotifier {
  LibraryQueryController(this.repository)
    : _state = VideoLibraryState(context: VideoBrowseContext());

  final LibraryRepository repository;
  static const pageSize = 24, maximumItems = 120;
  VideoLibraryState _state;
  VideoLibraryState get state => _state;
  int _generation = 0;
  bool _disposed = false;

  void _publish(VideoLibraryState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<void> load(
    VideoBrowseContext context, {
    bool more = false,
    bool before = false,
  }) => _read(context, more: more, before: before);

  Future<void> restore(
    VideoBrowseContext context, {
    required List<String> anchors,
  }) => _read(context, anchors: anchors);

  Future<void> _read(
    VideoBrowseContext context, {
    bool more = false,
    bool before = false,
    List<String>? anchors,
  }) async {
    if (_disposed || ((more || before) && _state.loading)) return;
    final same = context.queryKey == _state.context.queryKey;
    final append = more && same;
    final prepend = before && same;
    if ((append && !_state.hasAfter) || (prepend && !_state.hasBefore)) return;
    final previous = same ? _state.items : <LibraryVideo>[];
    final total = same ? _state.total : 0;
    final previousOffset = same ? _state.offset : 0;
    final offset = append
        ? previousOffset + previous.length
        : prepend
        ? (previousOffset - pageSize).clamp(0, previousOffset)
        : 0;
    final generation = ++_generation;
    var retryRestore = false;
    _publish(
      VideoLibraryState(
        context: context,
        items: previous,
        total: total,
        loading: true,
        offset: previousOffset,
      ),
    );
    try {
      final page = anchors == null
          ? await repository.loadVideoEntry(
              context.entry,
              offset: offset,
              limit: pageSize,
            )
          : await repository.restoreVideoEntry(
              context.entry,
              anchors: anchors,
              fallbackIndex: context.scrollIndex,
              limit: pageSize,
            );
      if (_disposed || generation != _generation) return;
      final ids = page.items.map((item) => item.id).toSet();
      if (ids.length != page.items.length ||
          page.total < page.offset + page.items.length ||
          ((append || prepend) &&
              (page.total != total ||
                  page.offset != offset ||
                  previous.any((item) => ids.contains(item.id)) ||
                  (page.items.isEmpty && offset < page.total))) ||
          (prepend && page.offset + page.items.length != previousOffset)) {
        retryRestore = previous.isNotEmpty;
        throw const LibraryFailure('视频列表已变化，请重新定位当前范围');
      }
      final items = append
          ? [...previous, ...page.items]
          : prepend
          ? [...page.items, ...previous]
          : [...page.items];
      var nextOffset = append ? previousOffset : page.offset;
      while (items.length > maximumItems) {
        if (prepend) {
          items.removeRange(items.length - pageSize, items.length);
        } else {
          items.removeRange(0, pageSize);
          nextOffset += pageSize;
        }
      }
      _publish(
        VideoLibraryState(
          context: context,
          items: items,
          total: page.total,
          offset: nextOffset,
          anchorIndex: page.anchorIndex,
        ),
      );
    } on RequestCancelled {
      if (!_disposed && generation == _generation) {
        _publish(
          VideoLibraryState(
            context: context,
            items: previous,
            total: total,
            offset: previousOffset,
            error: '读取已取消，请重试',
            beforeFailure: prepend,
            retryRestore: anchors != null,
          ),
        );
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _publish(
          VideoLibraryState(
            context: context,
            items: previous,
            total: total,
            error: error.toString(),
            offset: previousOffset,
            beforeFailure: prepend,
            retryRestore: retryRestore,
          ),
        );
      }
    }
  }

  /// Leaving the page invalidates a response without dropping visible cards.
  void cancel() {
    _generation++;
    repository.cancelVideoRead();
    _publish(
      VideoLibraryState(
        context: _state.context,
        items: _state.items,
        total: _state.total,
        error: _state.error,
        offset: _state.offset,
        anchorIndex: _state.anchorIndex,
        beforeFailure: _state.beforeFailure,
        retryRestore: _state.retryRestore,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    repository.cancelVideoRead();
    super.dispose();
  }
}
