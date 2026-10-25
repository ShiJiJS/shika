import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';

class MaintenanceTaskSession extends ChangeNotifier {
  MaintenanceTaskSession(this.repository, {MaintenanceTaskCatalog? catalog})
    : catalog = catalog ?? repository.createMaintenanceTasks() {
    repository.addListener(ownerChanged);
  }
  static const pageSize = 24;
  final LibraryRepository repository;
  final MaintenanceTaskCatalog catalog;
  List<MaintenanceTask> items = const [];
  List<MaintenanceReceipt> pending = const [];
  String family = 'all',
      filter = 'all',
      error = '',
      pendingError = '',
      message = '';
  int total = 0, offset = 0, _read = 0;
  bool loading = false, hasLoaded = false, _disposed = false;
  String? querying;
  bool get live => !_disposed && catalog.isCurrent;
  bool get canNext => hasLoaded && offset + items.length < total;
  bool get canPrevious => offset > 0;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void ownerChanged() {
    if (_disposed || live) return;
    _read++;
    items = const [];
    pending = const [];
    loading = false;
    hasLoaded = false;
    error = '服务连接或管理数据已变化，请重新打开操作任务';
    changed();
  }

  Future<void> load({int? start, String? kind, String? state}) async {
    if (!live) return;
    if ((kind != null && kind != family) ||
        (state != null && state != filter)) {
      items = const [];
      hasLoaded = false;
      total = offset = 0;
    }
    family = kind ?? family;
    filter = state ?? filter;
    final at = max(0, start ?? offset), serial = ++_read;
    loading = true;
    error = pendingError = '';
    changed();
    Future<void> readPage() async {
      try {
        var result = await catalog.page(
          offset: at,
          family: family,
          state: filter,
        );
        if (!live || serial != _read) return;
        if (at > 0 && result.items.isEmpty) {
          result = await catalog.page(
            offset: max(0, (result.total - 1) ~/ pageSize * pageSize),
            family: family,
            state: filter,
          );
        }
        if (!live || serial != _read) return;
        items = result.items;
        total = result.total;
        offset = result.offset;
        hasLoaded = true;
      } on RequestCancelled {
        /* New scope owns the view. */
      } catch (failure) {
        if (live && serial == _read) error = packFileFailureMessage(failure);
      }
    }

    Future<void> readPending() async {
      try {
        final result = await catalog.pending();
        if (live && serial == _read) pending = result;
      } on RequestCancelled {
        /* New scope owns the view. */
      } catch (failure) {
        if (live && serial == _read) {
          pendingError = packFileFailureMessage(failure);
        }
      }
    }

    await Future.wait([readPage(), readPending()]);
    if (!_disposed && serial == _read) {
      loading = false;
      changed();
    }
  }

  Future<MaintenanceTask?> query(MaintenanceReceipt receipt) async {
    if (!live || querying != null) return null;
    querying = receipt.id;
    message = '';
    changed();
    try {
      final result = await catalog.reconcile(receipt);
      if (!live) return null;
      if (result == null) message = '未找到原请求，未重新提交操作。请核对当前内容与服务状态后再查询。';
      return result;
    } on RequestCancelled {
      return null;
    } catch (failure) {
      if (live) message = packFileFailureMessage(failure);
      return null;
    } finally {
      if (!_disposed) {
        querying = null;
        changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _read++;
    repository.removeListener(ownerChanged);
    catalog.dispose();
    super.dispose();
  }
}
