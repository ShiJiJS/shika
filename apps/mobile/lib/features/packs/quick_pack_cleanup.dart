import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../library/server_api.dart';

enum QuickRemovalState { queued, pending, succeeded, failed, unknown }

class QuickPackRemoval {
  QuickPackRemoval(this.pack, this.command);
  final LibraryPack pack;
  final PackFileCommand command;
  QuickRemovalState state = QuickRemovalState.queued;
  PackFileTask? task;
  PackFileCommand? undoCommand;
  bool restored = false, working = false;
  String error = '';
  bool get hidden => !restored && state != QuickRemovalState.failed;
  bool get canUndo =>
      !restored &&
      undoCommand == null &&
      state == QuickRemovalState.succeeded &&
      (task?.remainingUndo() ?? Duration.zero) > Duration.zero;
}

/// Durable file work is independent from the currently displayed reader cursor.
/// A late receipt updates its own record and never selects a different pack.
class QuickPackCleanup extends ChangeNotifier {
  QuickPackCleanup(this.files, {this.changedFiles});
  final PackFiles files;
  final VoidCallback? changedFiles;
  final List<QuickPackRemoval> _items = [];
  final Set<String> _confirmed = {};
  bool _disposed = false;
  Timer? _undoExpiry;
  List<QuickPackRemoval> get items => List.unmodifiable(_items);
  Set<String> get hiddenIds => {
    ..._confirmed,
    for (final item in _items)
      if (item.hidden) item.pack.id,
  };
  QuickPackRemoval? get undoable =>
      _items.reversed.where((item) => item.canUndo).firstOrNull;
  int get unresolved => _items
      .where(
        (item) => !item.restored && item.state != QuickRemovalState.succeeded,
      )
      .length;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<QuickPackRemoval> enqueue(LibraryPack pack) async {
    if (!files.isCurrent() || files.readOnly) throw const RequestCancelled();
    final prior = _items
        .where((item) => item.pack.id == pack.id && item.hidden)
        .firstOrNull;
    if (prior != null) return prior;
    final pending = await files.pending();
    final existing = pending
        .where((c) => c.resources.contains('pack:${pack.id}'))
        .firstOrNull;
    if (existing != null &&
        (existing.kind != 'trash' || existing.body['reading'] != null)) {
      throw const LibraryFailure('这个图包有待核对的操作，请先查看操作记录');
    }
    // No reading snapshot: background trash must not mutate a newer cursor.
    final command =
        existing ??
        PackFileCommand.trash(packFileRequestId(), [
          pack.id,
        ], label: pack.displayTitle);
    await files.journal.remember(files.scope, command);
    if (!files.isCurrent()) throw const RequestCancelled();
    final item = QuickPackRemoval(pack, command);
    _items.add(item);
    _notify();
    unawaited(_resolve(item, submit: existing == null));
    return item;
  }

  Future<void> query(QuickPackRemoval item, {bool resend = false}) async {
    if (resend && !await files.canResend(item.command)) return;
    await _resolve(item, submit: resend);
  }

  Future<void> _resolve(QuickPackRemoval item, {required bool submit}) async {
    if (item.working) return;
    item.working = true;
    item.error = '';
    _notify();
    try {
      final task = await files.resolve(
        item.command,
        submit: submit,
        keepWaiting: files.isCurrent,
      );
      item.task = task;
      if (task?.settled == true) {
        if (task!.result!.succeeded > 0) {
          item.state = QuickRemovalState.succeeded;
          _confirmed.add(item.pack.id);
          await files.acknowledge(item.command);
          changedFiles?.call();
          _undoExpiry?.cancel();
          final remaining = task.remainingUndo();
          if (!_disposed && remaining > Duration.zero) {
            _undoExpiry = Timer(remaining, _notify);
          }
        } else {
          item.state = QuickRemovalState.failed;
          item.error = '移除未完成，可在操作记录中核对';
        }
      } else {
        item.state = task == null
            ? QuickRemovalState.unknown
            : QuickRemovalState.pending;
        item.error = task == null ? '移除结果待核对，请查询原操作' : '操作仍在处理中';
      }
    } catch (failure) {
      final rejected =
          failure is ApiFailure &&
          failure.status != null &&
          failure.status! >= 400 &&
          failure.status! < 500 &&
          ![408, 429].contains(failure.status);
      item.state = rejected
          ? QuickRemovalState.failed
          : QuickRemovalState.unknown;
      item.error = packFileFailureMessage(failure);
    } finally {
      item.working = false;
      // Retain pending records and the recent undo target; old successful
      // members only need their stable ID to stay out of this viewing range.
      if (_items.length > 60) {
        final old = _items
            .where(
              (x) =>
                  !x.working &&
                  (x.restored ||
                      (x.state == QuickRemovalState.succeeded && !x.canUndo)),
            )
            .toList();
        for (final x in old) {
          if (_items.length <= 60) break;
          _items.remove(x);
        }
      }
      _notify();
    }
  }

  Future<bool> undo(QuickPackRemoval item) async {
    if (item.working || (!item.canUndo && item.undoCommand == null)) {
      return false;
    }
    item.working = true;
    item.error = '';
    final submit = item.undoCommand == null;
    final command = item.undoCommand ??= PackFileCommand.undo(
      packFileRequestId(),
      item.task!.id,
    );
    _notify();
    try {
      final task = await files.resolve(
        command,
        submit: submit,
        keepWaiting: files.isCurrent,
      );
      if (task?.settled == true && task!.result!.succeeded > 0) {
        await files.acknowledge(command);
        item.restored = true;
        _confirmed.remove(item.pack.id);
        changedFiles?.call();
        return true;
      }
      item.error = '撤销结果待核对，请查询原操作';
      return false;
    } catch (failure) {
      item.error = packFileFailureMessage(failure);
      return false;
    } finally {
      item.working = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _undoExpiry?.cancel();
    // A saved user command may finish after leaving the page. Its journal
    // remains connection-bound; reopening only queries, never replays it.
    super.dispose();
  }
}
