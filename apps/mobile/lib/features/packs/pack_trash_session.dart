import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../library/catalog_selection.dart';

/// One trash query and its ID selection. Submitted commands outlive this view.
class PackTrashSession extends ChangeNotifier {
  PackTrashSession(
    this.repository, {
    PackTrashCatalog? catalog,
    PackFiles? files,
  }) : files = files ?? repository.createPackFiles(),
       catalog = catalog ?? repository.createPackTrash() {
    selection = CatalogSelection(
      connection: () => repository.connectionIdentity,
      cancelRead: this.catalog.cancelSelection,
    )..addListener(_notify);
    repository.addListener(_ownerChanged);
    if (repository.capabilities.packRestorePlans) {
      plans = repository.createPackRestorePlans();
    }
  }
  static const pageSize = 24;
  final LibraryRepository repository;
  final PackTrashCatalog catalog;
  final PackFiles files;
  PackRestorePlans? plans;
  List<RestorePlanPending> pendingPlans = const [];
  List<PackPurgeSelection> purgeSelections = const [];
  RestorePlan? lastPlan;
  late final CatalogSelection selection;
  bool _disposed = false, active = true, loading = false, restoring = false;
  bool hasLoaded = false;
  int _read = 0, offset = 0, total = 0;
  String search = '', error = '', message = '';
  List<PackTrashItem> _items = const [];
  List<PackTrashItem> get items => _items;
  List<PackFileCommand> pending = const [];
  PackFileTask? lastResult;
  final failures = <String, String>{};
  bool get live => !_disposed && catalog.isCurrent && files.isCurrent();
  bool get canPrevious => offset > 0;
  bool get canNext => offset + items.length < total;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _ownerChanged() {
    if (_disposed || live) return;
    _read++;
    catalog.cancelPages();
    selection.cancel(clear: true);
    _items = const [];
    hasLoaded = false;
    pending = const [];
    pendingPlans = const [];
    purgeSelections = const [];
    lastPlan = null;
    failures.clear();
    error = '服务连接或管理数据已变化，请返回后重新打开回收站';
    _notify();
  }

  void setActive(bool value) {
    active = value;
    if (!value) {
      _read++;
      catalog.cancelPages();
      selection.cancel();
      loading = false;
    }
    _notify();
  }

  Future<void> load({String? query, int? start}) async {
    if (!live || !active) return;
    final next = query ?? search;
    if (next != search) {
      if (restoring) return;
      selection.cancel(clear: true);
      failures.clear();
      lastResult = null;
      message = '';
      _items = const [];
      hasLoaded = false;
      total = offset = 0;
    }
    search = next;
    final index = max(0, start ?? (query == null ? offset : 0));
    final serial = ++_read;
    loading = true;
    error = '';
    _notify();
    try {
      var result = await catalog.page(
        search: next,
        offset: index,
        limit: pageSize,
      );
      if (!live || !active || serial != _read) return;
      if (index > 0 && result.items.isEmpty) {
        final tail = max(0, (result.total - 1) ~/ pageSize * pageSize);
        result = await catalog.page(
          search: next,
          offset: tail,
          limit: pageSize,
        );
      }
      if (!live || !active || serial != _read) return;
      _items = result.items;
      hasLoaded = true;
      total = result.total;
      offset = result.offset;
      await loadPending();
    } on RequestCancelled {
      // A newer read, source or connection owns the view.
    } catch (failure) {
      if (live && serial == _read) error = packFileFailureMessage(failure);
    } finally {
      if (!_disposed && serial == _read) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadPending() async {
    final commands = await files.pending();
    final restores = await plans?.pending() ?? <RestorePlanPending>[];
    final selections = repository.capabilities.packPermanentDelete
        ? await PackPurgeSelections(files).list()
        : <PackPurgeSelection>[];
    if (live) {
      pending = commands;
      pendingPlans = restores;
      purgeSelections = selections;
      _notify();
    }
  }

  Future<void> selectAll() async {
    if (!live || !active || restoring) return;
    final query = search;
    await selection.all(() => catalog.select(query));
  }

  void toggle(String id) {
    if (live && active && !restoring) selection.toggle(id);
  }

  void clearSelection() {
    if (!restoring) selection.cancel(clear: true);
  }

  Future<void> accept(PackFileCommand command, PackFileTask task) async {
    if (!live || !task.settled) return;
    final permanent = task.kind == 'pack_permanent';
    if (!permanent) {
      await files.acknowledge(command);
    } else if (!task.result!.needsAttention) {
      await files.acknowledgeTask(task);
    }
    if (!live) return;
    lastResult = task;
    final result = task.result!;
    for (final item in result.items) {
      if (item.succeeded) {
        selection.ids.remove(item.trashId);
        failures.remove(item.trashId);
      } else {
        failures[item.trashId] = permanent
            ? '本包已删 ${item.pagesDeleted}/${item.pagesTotal} 张，请核对原操作结果'
            : '未恢复，请重新读取图包状态后再试';
      }
    }
    message = permanent
        ? '已确认删除 ${result.pagesDeleted} 张图片${result.needsAttention ? '，还有待核对内容，原操作已保留' : '，${result.failed} 个图包未完成'}'
        : task.kind == 'pack_trash'
        ? '已确认整包回收结果'
        : result.failed == 0
        ? '已恢复 ${result.succeeded} 个图包，标签和阅读进度保留'
        : '已恢复 ${result.succeeded} 个，${result.failed} 个未完成';
    repository.packFilesChanged();
    await loadPending();
    _notify();
  }

  Future<void> restoreSelected({Set<String>? only}) async {
    if (!live || !active || restoring || (only ?? selection.ids).isEmpty) {
      return;
    }
    selection.cancel();
    final ids = (only ?? selection.ids).toList()..sort();
    if (plans != null) {
      restoring = true;
      error = message = '';
      _notify();
      try {
        final plan = await plans!.send(
          RestorePlanCommand.restore(packFileRequestId(), ids),
        );
        if (!live) return;
        if (plan == null) {
          error = '原恢复结果待确认，请查询原请求；未重复提交';
          return;
        }
        lastPlan = plan;
        selection.ids.removeAll(ids);
        for (final id in ids) {
          failures.remove(id);
        }
        message = '整份 ${plan.total} 个图包的恢复计划已受理，可离开页面，在操作任务查看进度';
        repository.packFilesChanged();
      } catch (failure) {
        if (live) error = packFileFailureMessage(failure);
      } finally {
        if (!_disposed) {
          restoring = false;
          if (live) {
            final actionError = error;
            try {
              await loadPending();
              if (active) await load();
              if (actionError.isNotEmpty) error = actionError;
            } catch (failure) {
              error = packFileFailureMessage(failure);
            }
          }
          _notify();
        }
      }
      return;
    }
    restoring = true;
    error = message = '';
    failures.clear();
    var succeeded = 0, failed = 0;
    _notify();
    try {
      await loadPending();
      final resources = ids.map((id) => 'trash:$id').toSet();
      if (pending.any(
        (command) => command.resources.intersection(resources).isNotEmpty,
      )) {
        error = '所选图包有待核对操作，请先查询原结果';
        return;
      }
      for (var at = 0; at < ids.length && live && active; at += 1000) {
        final chunk = ids.sublist(at, min(ids.length, at + 1000));
        final command = PackFileCommand.restore(
          packFileRequestId(),
          chunk,
          label: '恢复 ${chunk.length} 个图包',
        );
        final task = await files.resolve(
          command,
          submit: true,
          keepWaiting: () => live && active,
        );
        if (!live || !active) return;
        if (task == null || !task.settled) {
          error = '恢复结果待确认，请查询原操作；尚未提交的图包仍保留选择';
          return;
        }
        await accept(command, task);
        if (!live) return;
        succeeded += task.result!.succeeded;
        failed += task.result!.failed;
        message = '已恢复 $succeeded 个，$failed 个未完成';
      }
    } catch (failure) {
      if (live) error = packFileFailureMessage(failure);
    } finally {
      if (!_disposed) {
        restoring = false;
        if (live) {
          try {
            await loadPending();
          } catch (failure) {
            error = packFileFailureMessage(failure);
          }
          if (active) await load();
        }
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _read++;
    repository.removeListener(_ownerChanged);
    selection.removeListener(_notify);
    selection.dispose();
    catalog.dispose();
    super.dispose();
  }
}
