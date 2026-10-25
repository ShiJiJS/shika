part of 'server_backups.dart';

extension ServerArchiveBackups on ServerBackups {
  int _version(_Json command) => command['version'] == 2 ? 2 : 1;
  String _prefix(int version) =>
      version == 2 ? '/api/v1/management-backups' : '/api/v1/backups';

  Future<ArchiveExport> exportDocument(
    BackupFileStore files, {
    required int maximumBytes,
  }) => _serial(() async {
    _canStart();
    if (files.owner != scope) throw const LibraryFailure('文件暂存与当前连接不一致');
    final fresh = _state['export'] == null;
    var command = _map(_state['export'] ?? {'key': _nonce(), 'version': 2});
    final version = _version(command);
    await _save({..._state, 'export': command});
    if (command['task'] == null) {
      final accepted = fresh
          ? await _json(
              'POST',
              _prefix(version),
              body: {'request_id': command['key']},
            )
          : await _original('export', command['key'], version: version);
      command = {...command, 'task': accepted['id']};
      await _save({..._state, 'export': command});
    }
    final task = await _poll(command['task'], 'export');
    if (task['status'] != 'completed') {
      if (task['status'] == 'failed') await _remove('export');
      throw _failed(task);
    }
    if (command['file'] is Map) {
      try {
        final original = files.restore(_map(command['file']));
        await original.verify(scope: _lifetime);
        _check();
        return ArchiveExport(command['task'], original);
      } on RequestCancelled {
        rethrow;
      } on LibraryFailure {
        /* Same original GET may restore a missing private copy. */
      } on FileSystemException {
        /* Same task, no new export. */
      }
    }
    final result = _map(task['result']);
    if (task['kind'] != 'backup_export${version == 2 ? '_v2' : ''}' ||
        result['bytes'] is! int ||
        result['file_sha256'] is! String) {
      throw const LibraryFailure('原导出任务的文件身份不完整');
    }
    final document = await api.downloadFile(
      '${_prefix(version)}/${command['task']}/download',
      files,
      expectedBytes: result['bytes'],
      expectedSha256: result['file_sha256'],
      maximumBytes: maximumBytes,
      scope: _lifetime,
      originalReceipt: true,
    );
    _check();
    await _save({
      ..._state,
      'export': {...command, 'file': document.toJson()},
    });
    status.value = '备份已核对，请选择保存位置';
    return ArchiveExport(command['task'], document);
  });

  Future<ArchivePreview> inspectDocument(BackupDocument document) => _serial(
    () async {
      _canStart();
      if (document.store.owner != scope) {
        throw const LibraryFailure('所选文件属于原连接，请重新选择');
      }
      await document.verify(scope: _lifetime);
      _check();
      var command = _state['inspect'] is Map
          ? _map(_state['inspect'])
          : <String, dynamic>{};
      if (command.isNotEmpty &&
          (command['digest'] != document.sha256 || _version(command) == 1)) {
        if (command['task'] == null) {
          final original = await _original(
            'inspect',
            command['key'],
            version: _version(command),
          );
          command = {...command, 'task': original['id']};
          await _save({..._state, 'inspect': command});
        }
        await _poll(command['task'], 'inspect');
      }
      // A deliberate new file selection can start a new v2 inspection after
      // the original v1 inspection is known. Reopening only uses original GET.
      final fresh =
          command['digest'] != document.sha256 || _version(command) == 1;
      if (fresh) {
        command = {
          'key': _nonce(),
          'version': 2,
          'digest': document.sha256,
          'file': document.toJson(),
        };
      }
      await _save({..._state, 'inspect': command});
      if (command['task'] == null) {
        final accepted = fresh
            ? _map(
                jsonDecode(
                  utf8.decode(
                    (await api.uploadFile(
                      '/api/v1/management-backups/imports',
                      document,
                      headers: {'Idempotency-Key': command['key']},
                      scope: _lifetime,
                    )).bytes,
                  ),
                ),
              )
            : await _original(
                'inspect',
                command['key'],
                version: _version(command),
              );
        command = {...command, 'task': accepted['id']};
        await _save({..._state, 'inspect': command});
      }
      final task = await _poll(command['task'], 'inspect');
      if (task['status'] != 'completed') {
        if (task['status'] == 'failed') await _remove('inspect');
        throw _failed(task);
      }
      try {
        _archivePreview = ArchivePreview.fromTask(
          task,
          protocol: _version(command),
          digest: document.sha256,
        );
      } on LibraryFailure {
        rethrow;
      } catch (_) {
        throw const LibraryFailure('服务端预览与原文件不一致，请重新校验');
      }
      status.value = '校验通过，请核对两类媒体目录映射';
      return _archivePreview!;
    },
  );

  Future<ArchivePreview> resumeDocumentPreview() =>
      _serial(_resumeDocumentPreview);

  Future<ArchivePreview> _resumeDocumentPreview() async {
    _canStart();
    if (_state['inspect'] is! Map) throw const LibraryFailure('尚无已选备份，请先选择文件');
    var command = _map(_state['inspect']);
    if (command['task'] == null) {
      final found = await _original(
        'inspect',
        command['key'],
        version: _version(command),
      );
      command = {...command, 'task': found['id']};
      await _save({..._state, 'inspect': command});
    }
    final task = await _poll(command['task'], 'inspect');
    if (task['status'] != 'completed') {
      if (task['status'] == 'failed') await _remove('inspect');
      throw _failed(task);
    }
    try {
      _archivePreview = ArchivePreview.fromTask(
        task,
        protocol: _version(command),
        digest: command['digest'],
      );
      return _archivePreview!;
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('原备份预览信息不完整，原记录已保留');
    }
  }

  Future<ArchiveRestorePoint?> latestRestorePoint() => _serial(() async {
    _check();
    final raw = await api.json(
      'GET',
      '/api/v1/management-backups/latest-restore',
      scope: _lifetime,
    );
    _check();
    if (raw['item'] == null) return null;
    try {
      return ArchiveRestorePoint.fromJson(_map(raw['item']), owner: scope);
    } catch (_) {
      throw const LibraryFailure('恢复前快照信息不完整，请在后台操作结果中核对');
    }
  });

  Future<ArchivePreview> inspectRestorePoint(
    ArchiveRestorePoint point,
  ) => _serial(() async {
    _canStart();
    if (point.owner != scope) throw const LibraryFailure('快照属于原连接，请重新打开备份页面');
    var command = _state['inspect'] is Map
        ? _map(_state['inspect'])
        : <String, dynamic>{};
    final fresh =
        command['source_snapshot'] != point.snapshotId ||
        command['digest'] != point.fileSha256 ||
        _version(command) != 2;
    if (fresh && command.isNotEmpty) await _resumeDocumentPreview();
    if (fresh) {
      command = {
        'key': _nonce(),
        'version': 2,
        'digest': point.fileSha256,
        'source_snapshot': point.snapshotId,
      };
      await _save({..._state, 'inspect': command});
      final accepted = await _json(
        'POST',
        '/api/v1/management-backups/from-snapshot/${Uri.encodeComponent(point.snapshotId)}',
        body: {'request_id': command['key']},
      );
      await _save({
        ..._state,
        'inspect': {...command, 'task': accepted['id']},
      });
    }
    return _resumeDocumentPreview();
  });

  Future<ArchiveRootPage> documentRoots(
    ArchivePreview preview, {
    int offset = 0,
    int limit = 24,
  }) => _serial(() async {
    _samePreview(preview);
    if (offset < 0 || limit < 1 || limit > 100) {
      throw const LibraryFailure('目录页范围不正确');
    }
    if (preview.protocol == 1) {
      final roots = preview.legacyRoots!;
      return ArchiveRootPage(
        items: roots.skip(offset).take(limit).toList(),
        total: roots.length,
        offset: offset,
      );
    }
    final raw = await api.json(
      'GET',
      '/api/v1/management-backups/${Uri.encodeComponent(preview.taskId)}/roots',
      query: {'offset': '$offset', 'limit': '$limit'},
      scope: _lifetime,
    );
    _check();
    _samePreview(preview);
    try {
      final items = (raw['items'] as List)
          .map((v) => ArchiveRoot.fromJson(_map(v)))
          .toList();
      if (raw['offset'] != offset ||
          raw['total'] != preview.rootsTotal ||
          items.length != (preview.rootsTotal - offset).clamp(0, limit) ||
          items.map((r) => r.id).toSet().length != items.length ||
          offset + items.length > preview.rootsTotal) {
        throw const FormatException();
      }
      return ArchiveRootPage(
        items: List.unmodifiable(items),
        total: preview.rootsTotal,
        offset: offset,
      );
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('备份目录页信息不完整，请重新读取');
    }
  });

  void _samePreview(ArchivePreview preview) {
    _check();
    if (!identical(preview, _archivePreview) ||
        _state['inspect'] is! Map ||
        _state['inspect']['task'] != preview.taskId ||
        _state['inspect']['digest'] != preview.fileSha256) {
      throw const LibraryFailure('原预览已变化，请重新选择备份并核对');
    }
  }

  Future<void> restoreDocument(
    ArchivePreview preview,
    Map<String, String?> mappings,
  ) => _serial(() async {
    _canStart();
    _samePreview(preview);
    if (preview.protocol != 2) {
      throw const LibraryFailure('这份预览属于旧版流程，请重新选择原文件以校验完整恢复');
    }
    if (mappings.length != preview.rootsTotal) {
      throw const LibraryFailure('请逐一核对全部媒体目录，或明确选择不启用');
    }
    final entries = mappings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final command = {
      'key': _nonce(),
      'version': preview.protocol,
      'body': {
        'preview_id': preview.taskId,
        'confirmed': true,
        'root_mapping': {
          for (final e in entries)
            e.key: e.value == null || e.value!.trim().isEmpty
                ? null
                : e.value!.trim(),
        },
      },
    };
    await _save({..._state, 'restore': command});
    status.value = '正在提交已确认的完整恢复';
    try {
      final accepted = await _json(
        'POST',
        preview.protocol == 2
            ? '/api/v1/management-backups/restores'
            : '/api/v1/backup-restores',
        body: {'request_id': command['key'], ..._map(command['body'])},
      );
      await _save({
        ..._state,
        'restore': {...command, 'task': accepted['id']},
      });
    } on ApiFailure catch (error) {
      if (error.status != null &&
          error.status! >= 400 &&
          error.status! < 500 &&
          ![408, 429].contains(error.status)) {
        await _remove('restore');
      }
      rethrow;
    }
    await _reconcile();
  });
}
