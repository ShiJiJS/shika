import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import 'browse_context.dart';

class PackLibraryState {
  PackLibraryState({
    required this.context,
    Iterable<LibraryPack> items = const [],
    this.total = 0,
    this.offset = 0,
    this.loading = false,
    this.error = '',
    this.retryMore = false,
  }) : items = List.unmodifiable(items);
  final PackBrowseContext context;
  final List<LibraryPack> items;
  final int total, offset;
  final bool loading, retryMore;
  final String error;
  bool get hasMore => offset + items.length < total;
}

/// Owns a pack list's pagination and stale results, independently of video.
class PackQueryController extends ChangeNotifier {
  PackQueryController(this.repository)
    : _identity = repository.connectionIdentity,
      _state = PackLibraryState(context: PackBrowseContext()) {
    repository.addListener(_connectionChanged);
  }
  final LibraryRepository repository;
  Object _identity;
  PackLibraryState _state;
  PackLibraryState get state => _state;
  int _generation = 0;
  bool _disposed = false;

  void _publish(PackLibraryState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void _connectionChanged() {
    if (!identical(_identity, repository.connectionIdentity) ||
        !repository.snapshot.connected) {
      _identity = repository.connectionIdentity;
      ++_generation;
      repository.cancelPackRead();
      _publish(
        PackLibraryState(
          context: PackBrowseContext(source: _state.context.source),
        ),
      );
    }
  }

  Future<void> load(PackBrowseContext context, {bool more = false}) async {
    final same = context.queryKey == _state.context.queryKey;
    if (_disposed || (more && same && (_state.loading || !_state.hasMore))) {
      return;
    }
    final append = more && same;
    final previous = same ? _state.items : <LibraryPack>[];
    final previousOffset = same ? _state.offset : 0;
    final previousTotal = same ? _state.total : 0;
    final offset = append ? previousOffset + previous.length : 0;
    final generation = ++_generation;
    final identity = repository.connectionIdentity;
    bool valid() =>
        !_disposed &&
        generation == _generation &&
        identical(identity, repository.connectionIdentity);
    _publish(
      PackLibraryState(
        context: context,
        items: previous,
        total: previousTotal,
        offset: previousOffset,
        loading: true,
      ),
    );
    try {
      // LF5 owns recent pack membership. Until that service exists, a recent
      // source must fail clearly rather than silently returning the whole library.
      if (context.source == BrowseSource.recent) {
        throw const LibraryFailure('当前服务尚不支持最近图包，请升级服务端');
      }
      final page = await repository.loadPacks(context.query, offset: offset);
      if (!valid()) return;
      if (append && page.offset != offset) {
        throw const LibraryFailure('图包列表已变化，请刷新后继续');
      }
      _publish(
        PackLibraryState(
          context: context,
          items: append ? [...previous, ...page.items] : page.items,
          total: page.total,
          offset: append ? _state.offset : page.offset,
          retryMore: append && page.items.isEmpty,
          error: append && page.items.isEmpty && offset < page.total
              ? '图包列表已变化，请刷新后继续'
              : '',
        ),
      );
    } on RequestCancelled {
      if (valid()) {
        _publish(
          PackLibraryState(
            context: context,
            items: previous,
            total: _state.total,
            offset: _state.offset,
          ),
        );
      }
    } catch (failure) {
      if (valid()) {
        _publish(
          PackLibraryState(
            context: context,
            items: previous,
            total: _state.total,
            offset: _state.offset,
            error: failure.toString(),
            retryMore: append,
          ),
        );
      }
    }
  }

  void cancel() {
    ++_generation;
    repository.cancelPackRead();
    _publish(
      PackLibraryState(
        context: _state.context,
        items: _state.items,
        total: _state.total,
        offset: _state.offset,
        error: _state.error,
        retryMore: _state.retryMore,
      ),
    );
  }

  @override
  void dispose() {
    repository.removeListener(_connectionChanged);
    _disposed = true;
    ++_generation;
    repository.cancelPackRead();
    super.dispose();
  }
}
