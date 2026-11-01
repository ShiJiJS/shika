import 'maintenance_tasks.dart';
import 'pack_models.dart';

class MissingCleanupReceipt {
  const MissingCleanupReceipt(this.requestId, {this.historical = false});
  final String requestId;
  final bool historical;
}

abstract class PackMissingCatalog {
  bool get isCurrent;
  Future<CatalogPage<LibraryPack>> page({int offset = 0, int limit = 24});
  Future<List<MissingCleanupReceipt>> pending();
  Future<MaintenanceTask> submit(String requestId);
  Future<MaintenanceTask?> query(String requestId);
  Future<void> removeLocalReceipt(String requestId);
  void cancelPages();
  void dispose();
}
