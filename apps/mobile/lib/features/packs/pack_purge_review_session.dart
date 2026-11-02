import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../library/server_api.dart';

/// Preparation is read-only. Only authorize() creates a physical command, and
/// the existing file journal persists that command before any destructive POST.
class PackPurgeReviewSession extends ChangeNotifier {
  PackPurgeReviewSession(
    this.gateway,
    Iterable<String> ids, {
    this.selectionId,
    this.requestIdentity,
  }) : ids = List.unmodifiable((ids.toSet().toList()..sort()).take(1000)) {
    if (this.ids.isEmpty) throw const LibraryFailure('请先选择图包');
    // A saved selection is durable already. Reopening the same bounded batch
    // queries its original preparation instead of queuing another full hash.
    requestId = selectionId == null
        ? packFileRequestId()
        : 'purge-review-${sha256.convert(utf8.encode(jsonEncode([selectionId, this.ids])))}';
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!canConfirm) checked = false;
      if (!_disposed) notifyListeners();
    });
  }
  final PackPurgeGateway gateway;
  final String? selectionId;
  final Future<String> Function(String? replace)? requestIdentity;
  final List<String> ids;
  late final Timer _timer;
  Timer? _pollTimer;
  Completer<void>? _pause;
  late String requestId;
  String error = '', waitingMessage = '';
  PackPurgePlan? plan;
  bool checked = false, busy = false, _disposed = false;
  bool get live => !_disposed && gateway.isCurrent;
  bool get canConfirm =>
      live && !busy && error.isEmpty && plan?.canConfirm == true;
  bool get preparing =>
      plan != null && ['queued', 'running'].contains(plan!.status);
  bool get canRenew =>
      live &&
      !busy &&
      plan != null &&
      !preparing &&
      !canConfirm &&
      plan!.operationId == null;
  int get processed =>
      plan?.members.where((m) => m.digest != null || m.error != null).length ??
      0;
  bool transient(Object failure) =>
      failure is ApiFailure &&
      ([
            'timeout',
            'network_unavailable',
            'reply_lost',
          ].contains(failure.code) ||
          failure.status == 408 ||
          failure.status == 429 ||
          (failure.status != null && failure.status! >= 500));
  Future<void> pause(Duration duration) {
    final done = Completer<void>();
    _pause = done;
    _pollTimer = Timer(duration, () {
      _pause = null;
      _pollTimer = null;
      done.complete();
    });
    return done.future;
  }

  void check(bool value) {
    checked = value && canConfirm;
    notifyListeners();
  }

  void accept(PackPurgePlan value) {
    value.bind(ids);
    if (plan != null && plan!.id != value.id) {
      throw const LibraryFailure('原图片清单身份已变化，请重新核对');
    }
    if (plan?.digest != value.digest || !value.canConfirm) checked = false;
    plan = value;
  }

  Future<void> load({bool submit = false, bool renew = false}) async {
    if (!live || busy) return;
    if (renew && (preparing || plan?.operationId != null)) return;
    final previous = requestId;
    if (renew) {
      requestId = packFileRequestId();
      plan = null;
      checked = false;
    }
    busy = true;
    error = '';
    waitingMessage = '';
    notifyListeners();
    try {
      if (requestIdentity != null && (submit || renew)) {
        requestId = await requestIdentity!(renew ? previous : null);
        if (!live) return;
      }
      var maySubmit = submit || renew;
      var needsRead = !maySubmit;
      // First try the stable key when reopening a saved selection. If this
      // GET fails, keep querying; do not infer absence and enqueue more work.
      if (maySubmit && !renew && selectionId != null) {
        while (live) {
          try {
            final existing = await gateway.receipt(requestId);
            if (!live) return;
            if (existing != null) {
              accept(existing);
              maySubmit = false;
            }
            break;
          } catch (failure) {
            if (!live) return;
            if (!transient(failure)) rethrow;
            waitingMessage = '连接暂时不稳定，正在继续查询原清单…';
            notifyListeners();
            await pause(const Duration(seconds: 5));
          }
        }
      }
      if (maySubmit && live) {
        try {
          final value = await gateway.prepare(requestId, ids);
          if (!live) return;
          accept(value);
        } catch (failure) {
          if (!live) return;
          if (!transient(failure)) rethrow;
          // Acceptance may outlive the response. Only read the same key after
          // a timeout; neither polling nor recovery is permission to delete.
          waitingMessage = '服务器可能仍在准备，正在查询原清单…';
        }
      }
      if (!live) return;
      notifyListeners();
      while (live) {
        if (!needsRead && plan != null && !preparing) break;
        if (plan != null || waitingMessage.isNotEmpty) {
          await pause(Duration(seconds: waitingMessage.isEmpty ? 2 : 5));
        }
        if (!live) return;
        try {
          final value = plan == null
              ? await gateway.receipt(requestId)
              : await gateway.plan(plan!.id);
          if (!live) return;
          if (value == null) {
            // The accepting transaction may still be running. Keep the key,
            // and let the user close without losing the saved selection.
            waitingMessage = '尚未查到原清单，正在继续查询…';
          } else {
            accept(value);
            needsRead = false;
            waitingMessage = '';
          }
        } catch (failure) {
          if (!live) return;
          if (!transient(failure)) rethrow;
          waitingMessage = '连接暂时不稳定，正在继续查询原清单…';
        }
        notifyListeners();
      }
    } catch (failure) {
      if (live) error = packFileFailureMessage(failure);
    } finally {
      if (!_disposed) {
        busy = false;
        waitingMessage = '';
        notifyListeners();
      }
    }
  }

  PackFileCommand authorize() {
    if (!canConfirm || !checked) {
      checked = false;
      throw const LibraryFailure('请重新核对有效的图片清单并明确确认');
    }
    return PackFileCommand.permanent(
      packFileRequestId(),
      planId: plan!.id,
      digest: plan!.digest!,
      trashIds: ids,
      imageCount: plan!.imageCount,
      selectionId: selectionId,
      label: '永久删除 ${ids.length} 个图包中的 ${plan!.imageCount} 张图片',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer.cancel();
    _pollTimer?.cancel();
    _pause?.complete();
    _pause = null;
    gateway.dispose();
    super.dispose();
  }
}
