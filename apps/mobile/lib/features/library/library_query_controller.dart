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
  }) : items = List.unmodifiable(items);

  final VideoBrowseContext context;
  final List<LibraryVideo> items;
  final int total;
  final bool loading;
  final String error;
  final int offset;
  final int? anchorIndex;
  final bool beforeFailure;
  bool get hasBefore => offset > 0;
  bool get hasAfter => offset + items.length < total;
}

/// Owns pagination, cancellation and stale responses behind one read interface.
/// Loading a page never changes the repository's active playback round.
class LibraryQueryController extends ChangeNotifier {
  LibraryQueryController(this.repository)
    : _state = VideoLibraryState(context: VideoBrowseContext());

  final LibraryRepository repository;
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
    if (prepend && !_state.hasBefore) return;
    final previous = same ? _state.items : <LibraryVideo>[];
    final total = same ? _state.total : 0;
    final previousOffset = same ? _state.offset : 0;
    final offset = append
        ? previousOffset + previous.length
        : prepend
        ? (previousOffset - 24).clamp(0, previousOffset)
        : 0;
    final generation = ++_generation;
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
              limit: 24,
            )
          : await repository.restoreVideoEntry(
              context.entry,
              anchors: anchors,
              fallbackIndex: context.scrollIndex,
              limit: 24,
            );
      if (_disposed || generation != _generation) return;
      if (prepend && page.offset + page.items.length != previousOffset) {
        throw const LibraryFailure('视频列表已变化，请刷新后继续');
      }
      final items = append
          ? [...previous, ...page.items]
          : prepend
          ? [...page.items, ...previous]
          : page.items;
      final nextOffset = append ? previousOffset : page.offset;
      _publish(
        VideoLibraryState(
          context: context,
          items: items,
          total: page.total,
          offset: nextOffset,
          anchorIndex: page.anchorIndex,
          error:
              append &&
                  page.items.isEmpty &&
                  nextOffset + items.length < page.total
              ? '视频列表已变化，请刷新后继续'
              : '',
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
