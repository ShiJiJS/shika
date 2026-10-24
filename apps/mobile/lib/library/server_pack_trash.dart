part of 'server_repository.dart';

class _ServerPackTrash implements PackTrashCatalog {
  _ServerPackTrash(this.owner, this.target, this.generation, this.epoch);
  final ServerLibraryRepository owner;
  final ServerApi target;
  final int generation, epoch;
  bool disposed = false;
  RequestScope pages = RequestScope(), selection = RequestScope();
  @override
  bool get isCurrent =>
      !disposed &&
      !owner._disposed &&
      owner._generation == generation &&
      owner._readerEpoch == epoch &&
      identical(owner.connectionIdentity, target);
  void current(RequestScope scope) {
    if (!isCurrent || scope.cancelled) throw const RequestCancelled();
    owner.ensureNotRestoring();
  }

  Never bad() => throw const LibraryFailure('图包回收站数据不完整，请重新读取');
  String id(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 128
      ? value
      : bad();
  int integer(Object? value) => value is int && value >= 0 ? value : bad();
  String query(String value) {
    if (value.length > 200) throw const LibraryFailure('搜索内容不能超过200字');
    return value;
  }

  @override
  Future<CatalogPage<PackTrashItem>> page({
    String search = '',
    int offset = 0,
    int limit = 24,
  }) async {
    query(search);
    if (offset < 0 || limit < 1 || limit > 200) bad();
    cancelPages();
    final scope = pages = RequestScope();
    current(scope);
    final data = await owner.call(
      'GET',
      '/api/v1/pack-trash',
      using: target,
      cancel: scope,
      query: {'search': search, 'offset': '$offset', 'limit': '$limit'},
    );
    current(scope);
    try {
      final total = integer(data['total']);
      final raw = rows(data);
      if (data['offset'] != offset ||
          data['limit'] != limit ||
          raw.length != min(limit, max(0, total - offset))) {
        bad();
      }
      final items = raw.map((raw) {
        final pack = owner._pack(object(raw['pack']), target);
        final path = raw['original_path'], deletedAt = raw['deleted_at'];
        if (pack.status != 'trash' ||
            pack.id.isEmpty ||
            pack.name.isEmpty ||
            path is! String ||
            path.isEmpty ||
            path.length > 4096 ||
            deletedAt is! num ||
            !deletedAt.isFinite ||
            deletedAt < 0 ||
            integer(raw['page_count']) != pack.pageCount) {
          bad();
        }
        id(pack.id);
        return PackTrashItem(
          id: id(raw['id']),
          operationId: id(raw['operation_id']),
          originalPath: path,
          deletedAt: deletedAt.toDouble(),
          pageCount: pack.pageCount,
          pack: pack,
        );
      }).toList();
      if (items.map((v) => v.id).toSet().length != items.length ||
          items.map((v) => v.pack.id).toSet().length != items.length) {
        bad();
      }
      return CatalogPage(
        items: items,
        total: total,
        offset: offset,
        limit: limit,
      );
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      bad();
    }
  }

  @override
  Future<Set<String>> select(String search) async {
    query(search);
    cancelSelection();
    final scope = selection = RequestScope();
    current(scope);
    final data = await owner.call(
      'GET',
      '/api/v1/pack-trash/selection',
      using: target,
      cancel: scope,
      query: {'search': search},
    );
    current(scope);
    try {
      final values = (data['ids'] as List).map(id).toList();
      if (data['kind'] != 'pack-trash' ||
          values.length > 50000 ||
          integer(data['total']) != values.length ||
          values.toSet().length != values.length) {
        bad();
      }
      return Set.unmodifiable(values);
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      bad();
    }
  }

  @override
  void cancelPages() => pages.cancel();
  @override
  void cancelSelection() => selection.cancel();
  @override
  void dispose() {
    disposed = true;
    cancelPages();
    cancelSelection();
    owner._trashReaders.remove(this);
  }
}
