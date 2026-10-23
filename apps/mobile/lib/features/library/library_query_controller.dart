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
  }) : items = List.unmodifiable(items);

  final VideoBrowseContext context;
  final List<LibraryVideo> items;
  final int total;
  final bool loading;
  final String error;
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

  Future<void> load(VideoBrowseContext context, {bool more = false}) async {
    if (_disposed || (more && _state.loading)) return;
    final same = context.queryKey == _state.context.queryKey;
    final append = more && same;
    final previous = same ? _state.items : <LibraryVideo>[];
    final total = same ? _state.total : 0;
    final offset = append ? previous.length : 0;
    final generation = ++_generation;
    _publish(
      VideoLibraryState(
        context: context,
        items: previous,
        total: total,
        loading: true,
      ),
    );
    try {
      final page = await repository.loadVideos(
        scope: context.query,
        search: context.search,
        offset: offset,
        limit: 24,
      );
      if (_disposed || generation != _generation) return;
      final items = append ? [...previous, ...page.items] : page.items;
      _publish(
        VideoLibraryState(
          context: context,
          items: items,
          total: page.total,
          error: append && page.items.isEmpty && items.length < page.total
              ? '视频列表已变化，请刷新后继续'
              : '',
        ),
      );
    } on RequestCancelled {
      if (!_disposed && generation == _generation) {
        _publish(
          VideoLibraryState(context: context, items: previous, total: total),
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
