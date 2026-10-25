part of 'server_repository.dart';

class _ServerMaintenanceTasks
    implements MaintenanceTaskCatalog, GraphTaskCatalog, ArchiveTaskFiles {
  _ServerMaintenanceTasks(
    this.owner,
    this.target,
    this.generation,
    this.epoch,
    this.fileScope, {
    this.graphId,
  });
  final ServerLibraryRepository owner;
  final ServerApi target;
  final int generation, epoch;
  final String fileScope;
  final String? graphId;
  final scope = RequestScope();
  final issued = <String, MaintenanceReceipt>{};
  final downloaded = <String>{};
  bool disposed = false;
  @override
  bool get isCurrent =>
      !disposed &&
      !owner._disposed &&
      generation == owner._generation &&
      epoch == owner._readerEpoch &&
      identical(target, owner.connectionIdentity);
  void check() {
    if (!isCurrent) throw const RequestCancelled();
  }

  String id(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 128
      ? value
      : throw const LibraryFailure('原操作任务标识不完整');
  Future<Json> get(String path, {Map<String, String>? query}) async {
    check();
    final effectiveQuery = {
      ...?query,
      if (graphId != null && path.startsWith('/api/v1/management-history/'))
        'graph_id': graphId!,
    };
    final data = await owner.call(
      'GET',
      path,
      using: target,
      query: effectiveQuery,
      cancel: scope,
    );
    check();
    return data;
  }

  String route(String identity) =>
      '/api/v1/${graphId == null ? 'maintenance-tasks' : 'management-history/tasks'}/${Uri.encodeComponent(id(identity))}';
  T parse<T>(T Function() action) {
    try {
      return action();
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('操作任务数据不完整，请重新读取');
    }
  }

  void bounds(int offset, int limit) {
    if (offset < 0 || limit < 1 || limit > 100) {
      throw const LibraryFailure('操作任务分页范围无效');
    }
  }

  CatalogPage<T> pageData<T>(
    Json data,
    int offset,
    int limit,
    T Function(Json) make,
    String Function(T) identity,
  ) => parse(() {
    final total = data['total'], items = rows(data).map(make).toList();
    if (total is! int ||
        total < 0 ||
        data['offset'] != offset ||
        data['limit'] != limit ||
        items.length != min(limit, max(0, total - offset)) ||
        items.map(identity).toSet().length != items.length) {
      throw const LibraryFailure('任务分页不完整，请重新读取');
    }
    return CatalogPage(
      items: items,
      total: total,
      offset: offset,
      limit: limit,
    );
  });
  @override
  Future<CatalogPage<MaintenanceTask>> page({
    int offset = 0,
    int limit = 24,
    String family = 'all',
    String state = 'all',
  }) async {
    bounds(offset, limit);
    if (!['all', 'scan', 'video', 'pack', 'backup', 'other'].contains(family) ||
        ![
          'all',
          'processing',
          'attention',
          'completed',
          'historical',
        ].contains(state)) {
      throw const LibraryFailure('任务筛选条件无效');
    }
    return pageData(
      await get(
        graphId != null ||
                state == 'historical' && owner.capabilities.managementHistory
            ? '/api/v1/management-history/tasks'
            : '/api/v1/maintenance-tasks',
        query: {
          'offset': '$offset',
          'limit': '$limit',
          'family': family,
          'state': state,
        },
      ),
      offset,
      limit,
      MaintenanceTask.new,
      (value) => value.id,
    );
  }

  @override
  Future<MaintenanceTask> task(String identity) async {
    final data = await get(route(identity));
    final value = parse(() => MaintenanceTask(data));
    if (value.id != identity || graphId != null && value.graphId != graphId) {
      throw const LibraryFailure('原任务身份不一致，请重新读取');
    }
    return value;
  }

  @override
  Future<CatalogPage<MaintenanceItem>> items(
    String identity, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  }) async {
    bounds(offset, limit);
    final data = await get(
      '${route(identity)}/items',
      query: {
        'offset': '$offset',
        'limit': '$limit',
        'unfinished': '$unfinished',
      },
    );
    if (data['operation_id'] != identity ||
        data['historical'] is! bool ||
        graphId != null && data['graph_id'] != graphId) {
      throw const LibraryFailure('原操作明细身份不一致');
    }
    return pageData(
      data,
      offset,
      limit,
      MaintenanceItem.new,
      (value) => value.id,
    );
  }

  PackFiles historicalFiles(
    String sourceScope, {
    String? originEpoch,
    void Function(String)? onGraph,
  }) => PackFiles(
    journal: owner.packFileJournal,
    scope: sourceScope,
    readOnly: true,
    isCurrent: () => isCurrent,
    call: (method, path, {body}) {
      if (method != 'GET' || body != null) {
        throw const LibraryFailure('历史记录只能查询原结果');
      }
      return originEpoch == null
          ? get(path)
          : strictHistoryCall(path, originEpoch, onGraph: onGraph);
    },
  );

  String localId(String sourceScope, String value) => sourceScope == fileScope
      ? value
      : 'historical:${Uri.encodeComponent(sourceScope)}:$value';

  @override
  Future<List<MaintenanceReceipt>> pending() async {
    check();
    final result = <MaintenanceReceipt>[];
    for (final sourceScope in await owner.packFileJournal.serverScopes(
      fileScope,
    )) {
      final historical = sourceScope != fileScope;
      final commands = await owner.packFileJournal.pending(sourceScope);
      final bindings = await owner.packFileJournal.bindings(sourceScope);
      final plans = await owner.packFileJournal.restorePending(sourceScope);
      final selections = await owner.packFileJournal.purgeSelections(
        sourceScope,
      );
      final files = historical ? historicalFiles(sourceScope) : null;
      result.addAll([
        for (final value in selections)
          MaintenanceReceipt(
            id: localId(sourceScope, 'purge-selection:${value.id}'),
            requestId: value.id,
            title: '图包删除选择 · ${value.remaining.length} 个未提交',
            source: MaintenanceReceiptSource.purgeSelection,
            kind: 'purge_selection',
            purgeSelectionId: value.id,
            historical: historical || value.historical,
            journalScope: sourceScope,
            historyFiles: files,
          ),
        for (final value in plans)
          MaintenanceReceipt(
            id: localId(sourceScope, 'restore-plan:${value.command.key}'),
            requestId: value.command.requestId,
            title: value.command.label,
            source: MaintenanceReceiptSource.restorePlan,
            kind: value.command.kind,
            taskId: value.taskId,
            restoreCommand: value.command,
            historical: historical,
            journalScope: sourceScope,
          ),
        for (final command in commands)
          MaintenanceReceipt(
            id: localId(sourceScope, 'pack:${command.requestId}'),
            requestId: command.requestId,
            source: MaintenanceReceiptSource.pack,
            title:
                command.label ??
                (command.kind == 'permanent'
                    ? '永久删除图包图片'
                    : command.kind == 'restore'
                    ? '恢复图包'
                    : '图包操作'),
            kind: command.kind,
            taskId: bindings[command.requestId],
            packCommand: command,
            historical: historical,
            journalScope: sourceScope,
          ),
      ]);
      for (final entry in await owner.packFileJournal.missingPending(
        sourceScope,
      )) {
        result.add(
          MaintenanceReceipt(
            id: localId(sourceScope, 'missing:${entry.requestId}'),
            requestId: entry.requestId,
            title: '清除失效图包记录',
            source: MaintenanceReceiptSource.missingCleanup,
            kind: 'pack_forget_missing',
            historical: historical || entry.historical,
            journalScope: sourceScope,
          ),
        );
      }
    }
    for (final entry in (await owner._videoBook.entries(fileScope)).entries) {
      final pending = entry.value['pending'];
      if (pending == null) continue;
      if (pending is! Map) throw const LibraryFailure('本机视频操作记录无法读取');
      final key = id(pending['key']), path = pending['path'];
      if (path is! String || !path.startsWith('/api/v1/')) {
        throw const LibraryFailure('本机视频操作记录不完整');
      }
      final kind = path.split('/').last;
      result.add(
        MaintenanceReceipt(
          id: localId(entry.key, 'video:$key'),
          requestId: key,
          title:
              const {
                'trash': '视频移入回收站',
                'restore': '恢复视频',
                'permanent': '永久删除视频',
                'undo': '撤销视频移除',
              }[kind] ??
              '视频操作',
          source: MaintenanceReceiptSource.video,
          kind: kind,
          taskId: pending['task'] == null ? null : id(pending['task']),
          historical: entry.key != fileScope,
          journalScope: entry.key,
        ),
      );
    }
    for (final entry in (await owner._backupBook.entries(fileScope)).entries) {
      for (final kind in ['export', 'inspect', 'restore']) {
        final raw = entry.value[kind];
        if (raw == null) continue;
        if (raw is! Map) throw const LibraryFailure('本机备份操作记录无法读取');
        final key = id(raw['key']);
        result.add(
          MaintenanceReceipt(
            id: localId(entry.key, 'backup:$kind:$key'),
            requestId: key,
            title: const {
              'export': '导出管理备份',
              'inspect': '校验管理备份',
              'restore': '恢复管理数据',
            }[kind]!,
            source: MaintenanceReceiptSource.backup,
            protocolVersion: raw['version'] == 2 ? 2 : 1,
            kind: kind,
            taskId: raw['task'] == null ? null : id(raw['task']),
            historical: entry.key != fileScope,
            journalScope: entry.key,
          ),
        );
      }
    }
    check();
    issued
      ..clear()
      ..addEntries(result.map((value) => MapEntry(value.id, value)));
    return List.unmodifiable(result);
  }

  Future<MaintenanceTask?> historicalReceipt(MaintenanceReceipt receipt) async {
    final sourceScope = receipt.journalScope;
    if (sourceScope == null || !sameServerScope(sourceScope, fileScope)) {
      throw const LibraryFailure('历史记录所属连接不一致');
    }
    if (owner.capabilities.managementHistory &&
        owner.capabilities.historyAvailable != false) {
      return strictHistoricalReceipt(receipt);
    }
    String? identity;
    String expected;
    if (receipt.source == MaintenanceReceiptSource.pack) {
      final value = await historicalFiles(sourceScope)
          .receipt(receipt.packCommand!);
      if (value == null) return null;
      identity = value.id;
      expected = value.kind;
    } else if (receipt.source == MaintenanceReceiptSource.restorePlan) {
      final plans = PackRestorePlans(
        journal: owner.packFileJournal,
        scope: sourceScope,
        readOnly: true,
        isCurrent: () => isCurrent,
        call: (method, path, {body}) {
          if (method != 'GET' || body != null) {
            throw const LibraryFailure('历史记录只能查询原结果');
          }
          return get(path);
        },
      );
      final value = await plans.receipt(receipt.restoreCommand!);
      if (value == null) return null;
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
      Json raw;
      try {
        raw = await get(
          '/api/v1/$namespace/${Uri.encodeComponent(receipt.requestId)}',
        );
      } on ApiFailure catch (error) {
        if (error.status == 404) return null;
        rethrow;
      }
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
    final summary = await task(identity);
    if (summary.kind != expected) throw const LibraryFailure('原历史任务类型不一致');
    return summary.asHistorical();
  }

  @override
  Future<MaintenanceTask?> reconcile(MaintenanceReceipt receipt) async {
    if (receipt.historical &&
        receipt.source != MaintenanceReceiptSource.purgeSelection) {
      check();
      if (!identical(issued[receipt.id], receipt)) {
        throw const LibraryFailure('本机历史记录已变化，请重新读取');
      }
      return historicalReceipt(receipt);
    }
    if (receipt.source == MaintenanceReceiptSource.missingCleanup) {
      check();
      if (!identical(issued[receipt.id], receipt)) {
        throw const LibraryFailure('本机原请求已变化，请重新读取');
      }
      final gateway = owner.createPackMissing();
      try {
        return await gateway.query(receipt.requestId);
      } finally {
        gateway.dispose();
      }
    }
    check();
    if (!identical(issued[receipt.id], receipt)) {
      throw const LibraryFailure('本机操作记录已更新，请重新读取任务');
    }
    if (receipt.source == MaintenanceReceiptSource.purgeSelection) {
      throw const LibraryFailure('这是保存的选择，请打开后逐批核对；没有自动提交删除');
    }
    if (receipt.source == MaintenanceReceiptSource.restorePlan) {
      final plans = PackRestorePlans(
        journal: owner.packFileJournal,
        scope: fileScope,
        isCurrent: () => isCurrent,
        call: (method, path, {body}) {
          if (method != 'GET' || body != null) {
            throw const LibraryFailure('查询原计划不会重新提交');
          }
          return get(path);
        },
      );
      final value = await plans.receipt(receipt.restoreCommand!);
      if (value == null) return null;
      final summary = await task(value.id);
      if (summary.kind != 'pack_restore_plan' || summary.total != value.total) {
        throw const LibraryFailure('原恢复计划身份不一致');
      }
      return summary;
    }
    if (receipt.source == MaintenanceReceiptSource.pack) {
      final files = PackFiles(
        journal: owner.packFileJournal,
        scope: fileScope,
        isCurrent: () => isCurrent,
        call: (method, path, {body}) {
          if (method != 'GET' || body != null) {
            throw const LibraryFailure('查询任务不会重新提交操作');
          }
          return get(path);
        },
      );
      final value = await files.receipt(receipt.packCommand!);
      if (value == null) return null;
      final summary = await task(value.id);
      if (summary.historical) {
        await owner.packFileJournal.forget(fileScope, receipt.requestId);
      } else if (value.settled &&
          !value.result!.needsAttention &&
          ['completed', 'partial', 'failed'].contains(summary.state)) {
        if (value.kind == 'pack_permanent') {
          await files.acknowledgeTask(value);
        } else {
          await files.acknowledge(receipt.packCommand!);
        }
        check();
        owner.packFilesChanged();
      }
      check();
      return summary;
    }
    final namespace = receipt.source == MaintenanceReceiptSource.video
        ? 'file-requests'
        : receipt.protocolVersion == 2
        ? 'management-backups/requests/${receipt.kind}'
        : 'backup-requests/${receipt.kind}';
    Json raw;
    try {
      raw = await get(
        '/api/v1/$namespace/${Uri.encodeComponent(id(receipt.requestId))}',
      );
    } on ApiFailure catch (failure) {
      if (failure.status == 404) return null;
      rethrow;
    }
    final identity = id(raw['id']);
    final expected = receipt.source == MaintenanceReceiptSource.backup
        ? 'backup_${receipt.kind}${receipt.protocolVersion == 2 ? '_v2' : ''}'
        : receipt.kind;
    if (raw['kind'] != expected ||
        (receipt.taskId != null && receipt.taskId != identity)) {
      throw const LibraryFailure('原请求的任务身份或类型不一致');
    }
    final summary = await task(identity);
    if (summary.kind != expected) throw const LibraryFailure('原请求的任务类型不一致');
    if (receipt.source == MaintenanceReceiptSource.video) {
      if (summary.historical) {
        await owner.serializeFiles(() async {
          check();
          if (owner._fileState['pending'] case final Map current
              when current['key'] == receipt.requestId) {
            await owner.saveFileState({...owner._fileState}..remove('pending'));
            owner.fileStatus.value = null;
            owner.publish();
          }
        });
      } else if (['completed', 'partial', 'failed'].contains(summary.state)) {
        try {
          await owner._reconcileFileReceipt(receipt.requestId);
        } on LibraryFailure {
          if (owner.fileOperationPending) rethrow;
        }
      }
    } else {
      final client = owner._backups;
      if (client != null &&
          await client.attachReceipt(
            receipt.kind,
            receipt.requestId,
            identity,
          ) &&
          receipt.kind == 'restore' &&
          ['completed', 'failed'].contains(summary.state)) {
        try {
          await client.reconcile(expectedRequestId: receipt.requestId);
        } on LibraryFailure {
          if (client.restorePending) rethrow;
        }
      }
    }
    check();
    return summary;
  }

  @override
  MaintenanceTaskCatalog forTask(MaintenanceTask task) {
    check();
    if (task.graphId == null) {
      return task.historical ? HistoricalTaskCatalog(this) : this;
    }
    final child = _ServerMaintenanceTasks(
      owner,
      target,
      generation,
      epoch,
      fileScope,
      graphId: task.graphId,
    );
    owner._taskReaders.add(child);
    return child;
  }

  Future<Json> originalTask(String identity) => get(
    graphId == null
        ? '/api/v1/tasks/${Uri.encodeComponent(id(identity))}'
        : '/api/v1/management-history/tasks/${Uri.encodeComponent(id(identity))}/record',
  );

  @override
  Future<String?> restoreSnapshot(String identity) async {
    final value = await originalTask(identity);
    if (value['id'] != identity ||
        !['backup_restore', 'backup_restore_v2'].contains(value['kind'])) {
      return null;
    }
    final raw = object(value['result'])['pre_snapshot_id'];
    return raw == null ? null : id(raw);
  }

  @override
  Future<ArchiveExport> downloadArchiveFile(String identity) async {
    final value = await originalTask(identity),
        result = object(value['result']);
    final kind = value['kind'];
    if (value['id'] != identity ||
        value['status'] != 'completed' ||
        ![
          'backup_export',
          'backup_snapshot',
          'backup_export_v2',
          'backup_snapshot_v2',
        ].contains(kind) ||
        result['bytes'] is! int ||
        result['file_sha256'] is! String) {
      throw const LibraryFailure('原备份尚未完成或下载身份不完整');
    }
    final files = await owner._archiveFileStoreFactory(
      graphId == null ? fileScope : '$fileScope:graph:$graphId',
    );
    check();
    final prefix = graphId != null
        ? '/api/v1/management-history/tasks'
        : kind.toString().endsWith('_v2')
        ? '/api/v1/management-backups'
        : '/api/v1/backups';
    final document = await target.downloadFile(
      '$prefix/${Uri.encodeComponent(id(identity))}/download',
      files,
      expectedBytes: result['bytes'],
      expectedSha256: result['file_sha256'],
      maximumBytes: owner.capabilities.archiveMaximumBytes ?? 32 * 1024 * 1024,
      query: graphId == null ? null : {'graph_id': graphId},
      scope: scope,
      originalReceipt: true,
    );
    try {
      check();
    } catch (_) {
      await document.delete();
      rethrow;
    }
    downloaded.add(identity);
    return ArchiveExport(identity, document);
  }

  @override
  void dispose() {
    disposed = true;
    scope.cancel();
    issued.clear();
    owner._taskReaders.remove(this);
  }

  @override
  Future<String> downloadBackup(String identity) async {
    final encoded = Uri.encodeComponent(id(identity));
    final task = await get('/api/v1/tasks/$encoded');
    final result = parse(() => object(task['result']));
    final hash = result['file_sha256'];
    if (task['id'] != identity ||
        task['kind'] != 'backup_export' ||
        task['status'] != 'completed' ||
        hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const LibraryFailure('原备份尚未准备完成或下载校验信息不完整');
    }
    final response = await target.request(
      'GET',
      '/api/v1/backups/$encoded/download',
      maximumBytes: 32 * 1024 * 1024,
      timeout: const Duration(minutes: 2),
      scope: scope,
    );
    check();
    if (crypto.sha256.convert(response.bytes).toString() != hash) {
      throw const LibraryFailure('原备份下载校验失败，请重新下载');
    }
    final text = parse(() => utf8.decode(response.bytes));
    downloaded.add(identity);
    return text;
  }

  @override
  Future<void> backupSaved(String identity) async {
    check();
    if (!downloaded.contains(identity)) {
      throw const LibraryFailure('请先下载并核对这份备份');
    }
    final files = owner.capabilities.backupV2
        ? await owner._archiveFileStoreFactory(fileScope)
        : null;
    check();
    if (files != null && files.owner != fileScope) {
      throw const LibraryFailure('备份暂存与原连接不一致');
    }
    await owner._backups?.markExportSaved(identity, files: files);
    check();
    downloaded.remove(identity);
  }
}
