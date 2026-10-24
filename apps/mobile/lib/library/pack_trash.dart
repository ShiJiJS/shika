import 'pack_models.dart';

/// An active logical trash record. Its identity is distinct from the pack ID.
class PackTrashItem {
  const PackTrashItem({
    required this.id,
    required this.operationId,
    required this.originalPath,
    required this.deletedAt,
    required this.pageCount,
    required this.pack,
  });
  final String id, operationId, originalPath;
  final double deletedAt;
  final int pageCount;
  final LibraryPack pack;
}

/// Reads have their own lifetime, independent of video reads and file commands.
abstract interface class PackTrashCatalog {
  bool get isCurrent;
  Future<CatalogPage<PackTrashItem>> page({
    String search = '',
    int offset = 0,
    int limit = 24,
  });
  Future<Set<String>> select(String search);
  void cancelPages();
  void cancelSelection();
  void dispose();
}
