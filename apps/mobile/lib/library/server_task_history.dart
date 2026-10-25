part of 'server_repository.dart';

extension _StrictTaskHistory on _ServerMaintenanceTasks {
  String originalEpoch(String sourceScope) {
    final raw = parse(() => jsonDecode(sourceScope));
    if (raw is! List ||
        raw.length != 3 ||
        raw[2] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(raw[2])) {
      throw const LibraryFailure('旧服务未提供可定位的原管理代次；原历史记录已保留');
    }
    return raw[2] as String;
  }

  Future<Json> historyReceipt(
    String namespace,
    String key,
    String originEpoch,
  ) => get(
    '/api/v1/management-history/receipts/$namespace/${Uri.encodeComponent(key)}',
    query: {'epoch': originEpoch},
  );
  Future<Json> historyOperation(
    String namespace,
    String identity,
    String originEpoch,
  ) => get(
    '/api/v1/management-history/operations/$namespace/${Uri.encodeComponent(id(identity))}',
    query: {'epoch': originEpoch},
  );
  Future<Json> historyRecord(String identity, String originEpoch) => get(
    '/api/v1/management-history/tasks/${Uri.encodeComponent(id(identity))}/record',
    query: {'epoch': originEpoch},
  );

  /// Translate only original GETs used by existing typed receipt validators.
  /// Unknown epochs and missing receipts never fall through to a current graph.
  Future<Json> strictHistoryCall(
    String path,
    String originEpoch, {
    void Function(String)? onGraph,
  }) async {
    final parts = Uri.parse(path).pathSegments;
    if (parts.length < 4 || parts[0] != 'api' || parts[1] != 'v1') {
      throw const LibraryFailure('历史请求路径不正确');
    }
    final namespace = parts[2], key = parts[3];
    late Json packet;
    var plan = false;
    switch (namespace) {
      case 'pack-file-requests':
        packet = await historyReceipt(
          'pack_file_operations',
          'pack_files:$key',
          originEpoch,
        );
      case 'file-requests':
        packet = await historyReceipt(
          'file_operations',
          'files:$key',
          originEpoch,
        );
      case 'pack-missing-requests':
        packet = await historyReceipt(
          'pack_missing_cleanups',
          key,
          originEpoch,
        );
      case 'pack-retry-requests':
        final receipt = await historyReceipt(
          'request_records',
          'pack_files.retry:$key',
          originEpoch,
        );
        final identity = object(
          object(receipt['record'])['result'],
        )['operation_id'];
        packet = await historyOperation(
          'pack_file_operations',
          id(identity),
          originEpoch,
        );
      case 'pack-restore-requests':
        plan = true;
        packet = await historyReceipt(
          'pack_restore_plans',
          'pack_restore_plan:$key',
          originEpoch,
        );
      case 'pack-restore-plans':
        plan = true;
        packet = await historyOperation('pack_restore_plans', key, originEpoch);
      case 'pack-restore-stop-requests':
        plan = true;
        final receipt = await historyReceipt(
          'request_records',
          'pack_restore_plan.stop:$key',
          originEpoch,
        );
        final identity = object(object(receipt['record'])['result'])['plan_id'];
        packet = await historyOperation(
          'pack_restore_plans',
          id(identity),
          originEpoch,
        );
      case 'backup-requests':
      case 'management-backups':
        final version = namespace == 'management-backups' ? 2 : 1;
        final kind = version == 2 ? parts[4] : key;
        final request = version == 2 ? parts[5] : parts[4];
        final prefix = kind == 'restore'
            ? (version == 2 ? 'management.restore' : 'backup.restore')
            : version == 2
            ? 'management.backup_${kind}_v2'
            : 'backup.backup_$kind';
        final receipt = await historyReceipt(
          'request_records',
          '$prefix:$request',
          originEpoch,
        );
        final identity = object(object(receipt['record'])['result'])['id'];
        final raw = await historyRecord(id(identity), originEpoch);
        onGraph?.call(id(raw['graph_id']));
        return raw;
      default:
        throw const LibraryFailure('历史细项不能通过当前数据代替，请返回原任务核对');
    }
    final record = object(packet['record']), task = object(packet['task']);
    if (task['id'] != record['id'] || packet['graph_id'] is! String) {
      throw const LibraryFailure('原历史回执与父任务不一致');
    }
    onGraph?.call(id(packet['graph_id']));
    return {
      ...task,
      'historical': true,
      'graph_id': packet['graph_id'],
      if (plan) ...{
        'request_id': id(
          (record['request_key'] as String).replaceFirst(
            'pack_restore_plan:',
            '',
          ),
        ),
        'stop_requested': record['stop_requested'],
        'batch_size': record['batch_size'],
        if (namespace == 'pack-restore-stop-requests') 'stop_request_id': key,
      },
    };
  }

  Future<MaintenanceTask?> strictHistoricalReceipt(
    MaintenanceReceipt receipt,
  ) async {
    final source = receipt.journalScope!;
    String? identity, originalGraph;
    void bindGraph(String value) {
      if (originalGraph != null && originalGraph != value) {
        throw const LibraryFailure('原历史回执的数据图不一致');
      }
      originalGraph = value;
    }

    late String expected;
    // Local backup controllers survive replacements as the canonical original
    // execution ledger. Their completed result is newer than the pre-snapshot's
    // running projection; this does not authorize any retired media command.
    if (receipt.source == MaintenanceReceiptSource.backup) {
      final prefix = receipt.protocolVersion == 2
          ? 'management-backups/requests'
          : 'backup-requests';
      try {
        final raw = await get(
          '/api/v1/$prefix/${receipt.kind}/${Uri.encodeComponent(receipt.requestId)}',
        );
        expected =
            'backup_${receipt.kind}${receipt.protocolVersion == 2 ? '_v2' : ''}';
        if (raw['kind'] != expected ||
            receipt.taskId != null && receipt.taskId != raw['id']) {
          throw const LibraryFailure('原备份控制回执身份不一致');
        }
        if (raw['historical'] != true) {
          final value = await task(id(raw['id']));
          if (value.kind != expected) {
            throw const LibraryFailure('原备份控制任务类型不一致');
          }
          return value.asHistorical();
        }
      } on ApiFailure catch (error) {
        if (error.status == 404) return null;
        rethrow;
      }
    }
    final originEpoch = originalEpoch(source);
    try {
      if (receipt.source == MaintenanceReceiptSource.pack) {
        final value = await historicalFiles(
          source,
          originEpoch: originEpoch,
          onGraph: bindGraph,
        ).receipt(receipt.packCommand!);
        if (value == null) return null;
        identity = value.id;
        expected = value.kind;
      } else if (receipt.source == MaintenanceReceiptSource.restorePlan) {
        final command = receipt.restoreCommand!;
        final path =
            '/api/v1/${command.kind == 'stop' ? 'pack-restore-stop-requests' : 'pack-restore-requests'}/${Uri.encodeComponent(command.requestId)}';
        final raw = await strictHistoryCall(
          path,
          originEpoch,
          onGraph: bindGraph,
        );
        final value = RestorePlan.fromJson(raw);
        identity = value.id;
        expected = 'pack_restore_plan';
      } else {
        final namespace = receipt.source == MaintenanceReceiptSource.video
            ? 'file-requests'
            : receipt.source == MaintenanceReceiptSource.missingCleanup
            ? 'pack-missing-requests'
            : receipt.protocolVersion == 2
            ? 'management-backups/requests/${receipt.kind}'
            : 'backup-requests/${receipt.kind}';
        final raw = await strictHistoryCall(
          '/api/v1/$namespace/${Uri.encodeComponent(receipt.requestId)}',
          originEpoch,
          onGraph: bindGraph,
        );
        expected = receipt.source == MaintenanceReceiptSource.video
            ? receipt.kind
            : receipt.source == MaintenanceReceiptSource.missingCleanup
            ? 'pack_forget_missing'
            : 'backup_${receipt.kind}${receipt.protocolVersion == 2 ? '_v2' : ''}';
        if (raw['kind'] != expected) throw const LibraryFailure('原历史任务类型不一致');
        identity = id(raw['id']);
      }
      if (receipt.taskId != null && receipt.taskId != identity) {
        throw const LibraryFailure('原历史任务身份不一致');
      }
      final raw = await get(
        '/api/v1/management-history/tasks/${Uri.encodeComponent(identity)}',
        query: {'epoch': originEpoch},
      );
      final summary = parse(() => MaintenanceTask(raw));
      if (summary.id != identity ||
          summary.kind != expected ||
          summary.graphId == null ||
          summary.graphId != originalGraph) {
        throw const LibraryFailure('原历史父任务与所属数据图不一致');
      }
      return summary.asHistorical();
    } on ApiFailure catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }
}
