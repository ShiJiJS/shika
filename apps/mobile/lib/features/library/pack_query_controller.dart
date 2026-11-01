import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import 'browse_context.dart';

enum PackReadIntent { refresh, append, prepend, restore }

class PackLibraryState {
  PackLibraryState({
    required this.context,
    Iterable<LibraryPack> items = const [],
    this.total = 0,
    this.offset = 0,
    this.anchorIndex,
    this.loading = false,
    this.error = '',
    this.retry = PackReadIntent.refresh,
  }) : items = List.unmodifiable(items);
  final PackBrowseContext context;
  final List<LibraryPack> items;
  final int total, offset;
  final int? anchorIndex;
  final bool loading;
  final String error;
  final PackReadIntent retry;
  bool get retryMore => retry == PackReadIntent.append;
  bool get retryBefore => retry == PackReadIntent.prepend;
  bool get retryRestore => retry == PackReadIntent.restore;
  bool get hasBefore => offset > 0;
  bool get hasMore => offset + items.length < total;
}

/// A bounded window of one pack query. Restoring reads by stable identity;
/// paging and failures never change the viewing session or widen the scope.
class PackQueryController extends ChangeNotifier {
  PackQueryController(this.repository)
    : _identity = repository.connectionIdentity,
      _state = PackLibraryState(context: PackBrowseContext()) {
    repository.addListener(_connectionChanged);
  }
  static const pageSize = 24, maximumItems = 120;
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

  Future<void> load(
    PackBrowseContext context, {
    bool more = false,
    bool before = false,
  }) => _read(context, more: more, before: before);

  Future<void> restore(
    PackBrowseContext context, {
    required List<String> anchors,
  }) => _read(context, anchors: anchors);

  Future<void> _read(
    PackBrowseContext context, {
    bool more = false,
    bool before = false,
    List<String>? anchors,
  }) async {
    final same = context.queryKey == _state.context.queryKey;
    if (_disposed || ((more || before) && _state.loading)) return;
    final append = more && same, prepend = before && same;
    if ((append && !_state.hasMore) || (prepend && !_state.hasBefore)) return;
    final previous = same ? _state.items : <LibraryPack>[];
    final previousOffset = same ? _state.offset : 0;
    final previousTotal = same ? _state.total : 0;
    final offset = append
        ? previousOffset + previous.length
        : prepend
        ? (previousOffset - pageSize).clamp(0, previousOffset)
        : 0;
    var intent = anchors != null
        ? PackReadIntent.restore
        : append
        ? PackReadIntent.append
        : prepend
        ? PackReadIntent.prepend
        : PackReadIntent.refresh;
    final generation = ++_generation, identity = repository.connectionIdentity;
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
      if (context.source == BrowseSource.recent &&
          !repository.capabilities.packReadingSessions) {
        throw const LibraryFailure('当前服务尚不支持最近图包，请升级服务端');
      }
      final page = anchors == null
          ? await repository.loadPacks(
              context.query,
              offset: offset,
              limit: pageSize,
            )
          : await repository.restorePackEntry(
              context.query,
              anchors: anchors,
              fallbackIndex: context.scrollIndex,
              limit: pageSize,
            );
      if (!valid()) return;
      final ids = page.items.map((item) => item.id).toSet();
      final drift =
          ids.length != page.items.length ||
          page.total < page.offset + page.items.length ||
          ((append || prepend) &&
              (page.total != previousTotal ||
                  page.offset != offset ||
                  previous.any((item) => ids.contains(item.id)) ||
                  (page.items.isEmpty && offset < page.total))) ||
          (prepend && page.offset + page.items.length != previousOffset);
      if (drift) {
        intent = previous.isEmpty
            ? PackReadIntent.refresh
            : PackReadIntent.restore;
        throw const LibraryFailure('图包列表已变化，请重新定位当前范围');
      }
      final items = append
          ? [...previous, ...page.items]
          : prepend
          ? [...page.items, ...previous]
          : [...page.items];
      var start = append ? previousOffset : page.offset;
      while (items.length > maximumItems) {
        if (prepend) {
          items.removeRange(items.length - pageSize, items.length);
        } else {
          items.removeRange(0, pageSize);
          start += pageSize;
        }
      }
      _publish(
        PackLibraryState(
          context: context,
          items: items,
          total: page.total,
          offset: start,
          anchorIndex: page.anchorIndex,
        ),
      );
    } on RequestCancelled {
      if (valid()) {
        _publish(
          PackLibraryState(
            context: context,
            items: previous,
            total: previousTotal,
            offset: previousOffset,
            error: '图包读取已取消，原列表已保留，请重试',
            retry: intent,
          ),
        );
      }
    } catch (failure) {
      if (valid()) {
        _publish(
          PackLibraryState(
            context: context,
            items: previous,
            total: previousTotal,
            offset: previousOffset,
            error: failure.toString(),
            retry: intent,
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
        anchorIndex: _state.anchorIndex,
        error: _state.error,
        retry: _state.retry,
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
