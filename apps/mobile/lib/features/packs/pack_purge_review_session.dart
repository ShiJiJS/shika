import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/repository.dart';
import '../../library/models.dart';

/// Preparation is read-only. Only authorize() creates a physical command, and
/// the existing file journal persists that command before any destructive POST.
class PackPurgeReviewSession extends ChangeNotifier {
  PackPurgeReviewSession(this.gateway, Iterable<String> ids, {this.selectionId})
    : ids = List.unmodifiable((ids.toSet().toList()..sort()).take(1000)) {
    if (this.ids.isEmpty) throw const LibraryFailure('请先选择图包');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!canConfirm) checked = false;
      if (!_disposed) notifyListeners();
    });
  }
  final PackPurgeGateway gateway;
  final String? selectionId;
  final List<String> ids;
  late final Timer _timer;
  String requestId = packFileRequestId(), error = '';
  PackPurgePlan? plan;
  bool checked = false, busy = false, _disposed = false;
  bool get live => !_disposed && gateway.isCurrent;
  bool get canConfirm => live && !busy && plan?.canConfirm == true;
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
    if (renew) {
      requestId = packFileRequestId();
      plan = null;
      checked = false;
    }
    busy = true;
    error = '';
    notifyListeners();
    try {
      PackPurgePlan? value;
      if (submit || renew) {
        try {
          value = await gateway.prepare(requestId, ids);
        } catch (_) {
          if (!live) rethrow;
          // An accepted preparation may have lost its response. Never replace
          // its key or automatically repeat POST when checking a receipt.
          value = await gateway.receipt(requestId);
          if (value == null) rethrow;
        }
      } else {
        value = await gateway.receipt(requestId);
      }
      if (!live) return;
      if (value == null) {
        error = '未找到原清单。可重新准备，之后需要重新确认。';
        return;
      }
      accept(value);
      notifyListeners();
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (live &&
          ['queued', 'running'].contains(plan!.status) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!live) return;
        accept(await gateway.plan(plan!.id));
        if (!live) return;
        notifyListeners();
      }
    } catch (failure) {
      if (live) error = packFileFailureMessage(failure);
    } finally {
      if (!_disposed) {
        busy = false;
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
    gateway.dispose();
    super.dispose();
  }
}
