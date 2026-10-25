part of 'pack_files.dart';

/// One explicit action. Reopening an existing command always reads its receipt.
class RestorePlanCommand {
  RestorePlanCommand.restore(this.requestId, Iterable<String> ids)
    : kind = 'restore',
      planId = null,
      ids = List.unmodifiable((ids.toSet().toList()..sort())) {
    _id(requestId);
    if (this.ids.isEmpty || this.ids.length > 50000) {
      throw const LibraryFailure('整份恢复请选择1至50000个图包');
    }
    for (final id in this.ids) {
      _id(id);
    }
  }
  RestorePlanCommand.stop(this.requestId, String identity)
    : kind = 'stop',
      planId = _id(identity),
      ids = const [] {
    _id(requestId);
  }
  final String requestId, kind;
  final String? planId;
  final List<String> ids;
  String get key => '$kind:$requestId';
  String get signature => jsonEncode(toJson());
  String get label => kind == 'stop' ? '停止后续恢复批次' : '恢复 ${ids.length} 个图包';
  Set<String> get resources => ids.map((id) => 'trash:$id').toSet();
  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'kind': kind,
    'ids': ids,
    'plan_id': planId,
  };
  factory RestorePlanCommand.fromJson(Map<String, dynamic> raw) {
    final request = _id(raw['request_id']);
    if (raw['kind'] == 'stop' &&
        raw['ids'] is List &&
        (raw['ids'] as List).isEmpty) {
      return RestorePlanCommand.stop(request, _id(raw['plan_id']));
    }
    if (raw['kind'] == 'restore' &&
        raw['plan_id'] == null &&
        raw['ids'] is List) {
      final ids = (raw['ids'] as List).map(_id).toList();
      if (ids.toSet().length != ids.length) {
        throw const LibraryFailure('恢复计划记录包含重复成员');
      }
      return RestorePlanCommand.restore(request, ids);
    }
    throw const LibraryFailure('本机整份恢复记录不完整，请核对服务端任务');
  }
}

class RestorePlan {
  RestorePlan.fromJson(Map<String, dynamic> raw)
    : id = _id(raw['id']),
      requestId = _id(raw['request_id']),
      status = _id(raw['status']),
      phase = _id(raw['phase']),
      historical = _flag(raw['historical']),
      stopRequested = _flag(raw['stop_requested']),
      batchSize = _integer(raw['batch_size']),
      error = raw['error'] == null ? null : _id(raw['error']),
      total = _integer(_map(raw['result'])['total']),
      processed = _integer(_map(raw['result'])['processed']),
      succeeded = _integer(_map(raw['result'])['succeeded']),
      failed = _integer(_map(raw['result'])['failed']),
      stopped = _integer(_map(raw['result'])['stopped']),
      remaining = _integer(_map(raw['result'])['remaining']),
      batches = _integer(_map(raw['result'])['batches']) {
    if (raw['kind'] != 'pack_restore_plan' ||
        _map(raw['result'])['operation_id'] != id ||
        ![
          'queued',
          'running',
          'completed',
          'failed',
          'interrupted',
        ].contains(status) ||
        total < 1 ||
        total > 50000 ||
        batchSize < 1 ||
        batchSize > 1000 ||
        processed != succeeded + failed ||
        processed + stopped + remaining != total ||
        batches > (total + batchSize - 1) ~/ batchSize ||
        (status == 'completed' && remaining != 0)) {
      throw const LibraryFailure('服务端整份恢复结果不完整，请查询原计划');
    }
  }
  final String id, requestId, status, phase;
  final String? error;
  final bool historical, stopRequested;
  final int batchSize,
      total,
      processed,
      succeeded,
      failed,
      stopped,
      remaining,
      batches;
  bool get needsAttention => error == 'operation_recovery_required';
  bool get settled =>
      historical ||
      !needsAttention &&
          ['completed', 'failed'].contains(status) &&
          remaining == 0;
}

class RestorePlanPending {
  RestorePlanPending(this.command, this.taskId);
  final RestorePlanCommand command;
  final String? taskId;
}

extension RestorePlanJournal on PackFileJournal {
  static const namespace = 'restore_plans_v1';
  Map<String, dynamic> _restoreRows(String scope) => _map(
    _map(_book?[namespace] ?? <String, dynamic>{})[scope] ??
        <String, dynamic>{},
  );
  Future<List<RestorePlanPending>> restorePending(String scope) => _edit(
    scope,
    (entries) => [
      for (final entry in entries.entries)
        _restoreEntry(entry.key, _map(entry.value)),
    ],
    write: false,
    namespace: namespace,
  );
  RestorePlanPending _restoreEntry(String key, Map<String, dynamic> row) {
    final command = RestorePlanCommand.fromJson(_map(row['command']));
    final task = row['task_id'] == null ? null : _id(row['task_id']);
    if (key != command.key ||
        command.kind == 'stop' && task != command.planId) {
      throw const LibraryFailure('本机恢复计划身份不一致');
    }
    return RestorePlanPending(command, task);
  }

  Future<bool> rememberRestore(
    String scope,
    RestorePlanCommand command,
  ) => _edit(scope, (entries) {
    if (entries[command.key] != null) {
      final previous = _restoreEntry(command.key, _map(entries[command.key]));
      if (previous.command.signature != command.signature) {
        throw const LibraryFailure('请求标识已用于不同的恢复计划');
      }
      return false;
    }
    for (final entry in entries.entries) {
      final other = _restoreEntry(entry.key, _map(entry.value));
      if (other.command.resources.intersection(command.resources).isNotEmpty ||
          command.kind == 'stop' &&
              other.command.kind == 'stop' &&
              other.taskId == command.planId) {
        throw const LibraryFailure('这项恢复或停止结果尚未确认，请先查询原请求');
      }
    }
    final files = _map(
      _map(_book?['scopes'] ?? <String, dynamic>{})[scope] ??
          <String, dynamic>{},
    );
    for (final row in files.values) {
      final other = PackFileCommand.fromJson(_map(_map(row)['command']));
      if (other.resources.intersection(command.resources).isNotEmpty) {
        throw const LibraryFailure('所选图包有待核对操作，请先查询原结果');
      }
    }
    if (entries.length >= 256) throw const LibraryFailure('待核对恢复记录过多，请先查询原请求');
    entries[command.key] = {
      'command': command.toJson(),
      'task_id': command.planId,
    };
    return true;
  }, namespace: namespace);
  Future<void> bindRestore(
    String scope,
    RestorePlanCommand command,
    String identity,
  ) => _edit(scope, (entries) {
    final previous = _restoreEntry(command.key, _map(entries[command.key]));
    if (previous.command.signature != command.signature ||
        previous.taskId != null && previous.taskId != identity) {
      throw const LibraryFailure('原恢复计划身份不一致');
    }
    entries[command.key] = {
      'command': command.toJson(),
      'task_id': _id(identity),
    };
  }, namespace: namespace);
  Future<void> forgetRestore(
    String scope,
    RestorePlanCommand command, {
    String? identity,
  }) => _edit(scope, (entries) {
    if (entries[command.key] == null) return;
    final previous = _restoreEntry(command.key, _map(entries[command.key]));
    if (previous.command.signature == command.signature &&
        (identity == null || previous.taskId == identity)) {
      entries.remove(command.key);
    }
  }, namespace: namespace);
}

/// Shared durable journal; this gateway never polls or schedules child work.
class PackRestorePlans {
  PackRestorePlans({
    required this.journal,
    required this.scope,
    required this.call,
    required this.isCurrent,
  });
  final PackFileJournal journal;
  final String scope;
  final PackFileCall call;
  final bool Function() isCurrent;
  final _sending = <String, Future<RestorePlan?>>{};
  final _signatures = <String, String>{};
  void _check() {
    if (!isCurrent()) throw const RequestCancelled();
  }

  Future<List<RestorePlanPending>> pending() async {
    _check();
    final values = await journal.restorePending(scope);
    _check();
    return values;
  }

  RestorePlan _parse(Map<String, dynamic> raw) {
    try {
      return RestorePlan.fromJson(raw);
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('整份恢复结果不完整，请查询原请求');
    }
  }

  Future<RestorePlan?> send(RestorePlanCommand command) {
    _check();
    if (_sending[command.key] case final Future<RestorePlan?> active) {
      if (_signatures[command.key] != command.signature) {
        return Future.error(const LibraryFailure('请求标识已用于不同的恢复计划'));
      }
      return active;
    }
    final work = _send(command);
    _sending[command.key] = work;
    _signatures[command.key] = command.signature;
    unawaited(
      work.then<void>(
        (_) {
          _sending.remove(command.key);
          _signatures.remove(command.key);
        },
        onError: (Object _, StackTrace _) {
          _sending.remove(command.key);
          _signatures.remove(command.key);
        },
      ),
    );
    return work;
  }

  Future<RestorePlan?> _send(RestorePlanCommand command) async {
    final fresh = await journal.rememberRestore(scope, command);
    _check();
    if (!fresh) return receipt(command);
    Map<String, dynamic> raw;
    try {
      raw = await call(
        'POST',
        command.kind == 'restore'
            ? '/api/v1/pack-restore-plans'
            : '/api/v1/pack-restore-plans/${Uri.encodeComponent(command.planId!)}/stop',
        body: {
          'request_id': command.requestId,
          if (command.kind == 'restore') 'trash_ids': command.ids,
        },
      );
    } on ApiFailure catch (failure) {
      _check();
      if (failure.status != null &&
          failure.status! >= 400 &&
          failure.status! < 500 &&
          ![408, 429].contains(failure.status)) {
        await journal.forgetRestore(scope, command);
      }
      rethrow;
    }
    _check();
    return _accept(command, raw);
  }

  Future<RestorePlan?> receipt(RestorePlanCommand command) async {
    _check();
    final records = await pending();
    final found = records
        .where((p) => p.command.key == command.key)
        .firstOrNull;
    if (found == null || found.command.signature != command.signature) {
      throw const LibraryFailure('恢复记录已变化，请重新读取');
    }
    Map<String, dynamic> raw;
    try {
      raw = await call(
        'GET',
        '/api/v1/${command.kind == 'stop' ? 'pack-restore-stop-requests' : 'pack-restore-requests'}/${Uri.encodeComponent(command.requestId)}',
      );
    } on ApiFailure catch (failure) {
      if (failure.status == 404) return null;
      rethrow;
    }
    _check();
    return _accept(command, raw);
  }

  Future<RestorePlan> _accept(
    RestorePlanCommand command,
    Map<String, dynamic> raw,
  ) async {
    final plan = _parse(raw);
    if (command.kind == 'restore' &&
            (plan.requestId != command.requestId ||
                plan.total != command.ids.length) ||
        command.kind == 'stop' &&
            (plan.id != command.planId ||
                raw['stop_request_id'] != command.requestId ||
                !plan.historical && !plan.stopRequested && !plan.settled)) {
      throw const LibraryFailure('原恢复或停止请求身份不一致，请保留记录');
    }
    await journal.bindRestore(scope, command, plan.id);
    _check();
    if (command.kind == 'stop' || plan.settled) {
      await journal.forgetRestore(scope, command, identity: plan.id);
      _check();
    }
    return plan;
  }

  Future<RestorePlan> task(String identity) async {
    _check();
    final raw = await call(
      'GET',
      '/api/v1/pack-restore-plans/${Uri.encodeComponent(_id(identity))}',
    );
    final plan = _parse(raw);
    _check();
    if (plan.id != identity) throw const LibraryFailure('原计划身份不一致');
    for (final record in await pending()) {
      if (record.command.kind == 'restore' &&
          record.command.requestId == plan.requestId) {
        await _accept(record.command, raw);
      }
    }
    _check();
    return plan;
  }
}
