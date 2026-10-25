part of 'pack_files.dart';

/// A saved choice is not permission to delete. Only a separately reviewed,
/// explicit PackFileCommand can claim one bounded batch.
class PackPurgeSelection {
  PackPurgeSelection.fromJson(Map<String, dynamic> raw)
    : id = _id(raw['id']),
      createdAt = _integer(raw['created_at']),
      historical = _flag(raw['historical']),
      ids = List.unmodifiable((raw['ids'] as List).map(_id)),
      batches = List.unmodifiable(
        (raw['batches'] as List).map((v) => PackPurgeBatch.fromJson(_map(v))),
      ) {
    final sorted = ids.toList()..sort();
    if (jsonEncode(sorted) != jsonEncode(ids) ||
        ids.isEmpty ||
        ids.length > 50000 ||
        ids.toSet().length != ids.length ||
        batches.length > 256 ||
        batches.map((b) => b.command.requestId).toSet().length !=
            batches.length) {
      throw const LibraryFailure('本机删除选择记录不完整');
    }
    final original = ids.toSet(), claimed = <String>{};
    for (final batch in batches) {
      if (batch.command.purgeSelectionId != id ||
          batch.command.targets.any((v) => !original.contains(v)) ||
          !batch.rejected &&
              batch.command.targets.any((v) => !claimed.add(v))) {
        throw const LibraryFailure('本机删除批次与原选择不一致');
      }
    }
  }
  final String id;
  final int createdAt;
  final bool historical;
  final List<String> ids;
  final List<PackPurgeBatch> batches;
  List<String> get remaining {
    final claimed = {
      for (final b in batches.where((b) => !b.rejected)) ...b.command.targets,
    };
    return List.unmodifiable(ids.where((id) => !claimed.contains(id)));
  }

  String get signature => jsonEncode(toJson());
  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt,
    'historical': historical,
    'ids': ids,
    'batches': batches.map((v) => v.toJson()).toList(),
  };
}

class PackPurgeBatch {
  PackPurgeBatch.fromJson(Map<String, dynamic> raw)
    : command = PackFileCommand.fromJson(_map(raw['command'])),
      taskId = raw['task_id'] == null ? null : _id(raw['task_id']),
      rejected = _flag(raw['rejected']) {
    if (command.kind != 'permanent' ||
        command.purgeSelectionId == null ||
        rejected && taskId != null) {
      throw const LibraryFailure('本机删除批次记录不完整');
    }
  }
  final PackFileCommand command;
  final String? taskId;
  final bool rejected;
  Map<String, dynamic> toJson() => {
    'command': command.toJson(),
    'task_id': taskId,
    'rejected': rejected,
  };
}

const _purgeSelectionsNamespace = 'purge_selections_v1';
Map<String, dynamic> _purgeSelectionRows(
  Map<String, dynamic> book,
  String scope,
) => _map(
  _map(book[_purgeSelectionsNamespace] ?? <String, dynamic>{})[scope] ??
      <String, dynamic>{},
);
PackPurgeSelection _purgeSelection(String key, Object? raw) {
  final value = PackPurgeSelection.fromJson(_map(raw));
  if (key != value.id) throw const LibraryFailure('本机删除选择身份不一致');
  return value;
}

void _writePurgeSelection(
  Map<String, dynamic> book,
  String scope,
  Map<String, dynamic> rows,
) {
  final scopes = _map(book[_purgeSelectionsNamespace] ?? <String, dynamic>{});
  scopes[scope] = rows;
  book[_purgeSelectionsNamespace] = scopes;
}

void _claimPurgeSelection(
  Map<String, dynamic> book,
  String scope,
  PackFileCommand command,
) {
  final id = command.purgeSelectionId;
  if (id == null) return;
  final rows = _purgeSelectionRows(book, scope);
  final selection = _purgeSelection(id, rows[id]);
  if (selection.historical) throw const LibraryFailure('旧管理数据的选择不能继续删除，请重新选择');
  final existing = selection.batches
      .where((v) => v.command.requestId == command.requestId)
      .firstOrNull;
  if (existing != null) {
    if (existing.command.signature != command.signature || existing.rejected) {
      throw const LibraryFailure('原删除批次已变化，请重新核对清单');
    }
    return;
  }
  if (selection.batches.length >= 256 ||
      jsonEncode(selection.remaining.take(1000).toList()) !=
          jsonEncode(command.targets)) {
    throw const LibraryFailure('剩余选择已变化，请重新核对本批清单');
  }
  rows[id] = {
    ...selection.toJson(),
    'batches': [
      ...selection.batches.map((b) => b.toJson()),
      {'command': command.toJson(), 'task_id': null, 'rejected': false},
    ],
  };
  _writePurgeSelection(book, scope, rows);
}

void _updatePurgeBatch(
  Map<String, dynamic> book,
  String scope,
  PackFileCommand command,
  Map<String, dynamic> Function(PackPurgeBatch) update,
) {
  final id = command.purgeSelectionId;
  if (id == null) return;
  final rows = _purgeSelectionRows(book, scope);
  // Discarding a choice must never discard a submitted file command.
  if (rows[id] == null) return;
  final selection = _purgeSelection(id, rows[id]);
  rows[id] = {
    ...selection.toJson(),
    'batches': [
      for (final batch in selection.batches)
        if (batch.command.requestId == command.requestId)
          update(batch)
        else
          batch.toJson(),
    ],
  };
  _writePurgeSelection(book, scope, rows);
}

void _bindPurgeSelection(
  Map<String, dynamic> book,
  String scope,
  PackFileCommand command,
  String taskId,
) => _updatePurgeBatch(book, scope, command, (batch) {
  if (batch.command.signature != command.signature ||
      batch.rejected ||
      batch.taskId != null && batch.taskId != taskId) {
    throw const LibraryFailure('原删除批次身份不一致');
  }
  return {...batch.toJson(), 'task_id': _id(taskId)};
});
void _rejectPurgeSelection(
  Map<String, dynamic> book,
  String scope,
  PackFileCommand command,
) => _updatePurgeBatch(book, scope, command, (batch) {
  if (batch.command.signature != command.signature || batch.taskId != null) {
    throw const LibraryFailure('原删除结果已受理，请查询原请求');
  }
  return {...batch.toJson(), 'rejected': true};
});

extension PurgeSelectionsJournal on PackFileJournal {
  Future<List<PackPurgeSelection>> purgeSelections(String scope) => _edit(
    scope,
    (rows) => List.unmodifiable([
      for (final row in rows.entries) _purgeSelection(row.key, row.value),
    ]),
    write: false,
    namespace: _purgeSelectionsNamespace,
  );
  Future<void> historicalPurgeSelections(String scope) => _edit(scope, (rows) {
    for (final key in rows.keys.toList()) {
      rows[key] = {
        ..._purgeSelection(key, rows[key]).toJson(),
        'historical': true,
      };
    }
  }, namespace: _purgeSelectionsNamespace);
}

/// Local persistence only. This module cannot submit or resume file operations.
class PackPurgeSelections {
  PackPurgeSelections(this.files);
  final PackFiles files;
  bool get isCurrent => files.isCurrent();
  void _check() {
    if (!isCurrent) throw const RequestCancelled();
  }

  Future<List<PackPurgeSelection>> list() async {
    _check();
    final rows = await files.journal.purgeSelections(files.scope);
    _check();
    return rows;
  }

  Future<PackPurgeSelection> read(String id) async {
    final result = (await list()).where((v) => v.id == id).firstOrNull;
    if (result == null) throw const LibraryFailure('这份删除选择已移除，请返回重新读取');
    return result;
  }

  Future<PackPurgeSelection> save(Iterable<String> selected) async {
    _check();
    if (files.readOnly) throw const LibraryFailure('恢复前的选择只能查看或移除，请从当前媒体库重新选择');
    final ids = selected.map(_id).toSet().toList()..sort();
    final selectedIds = ids.toSet();
    if (ids.isEmpty || ids.length > 50000) {
      throw const LibraryFailure('请选择1至50000个图包');
    }
    final result = await files.journal._edit(files.scope, (rows) {
      _check();
      final previous = rows.entries.map((v) => _purgeSelection(v.key, v.value));
      for (final row in previous.where((v) => !v.historical)) {
        if (jsonEncode(row.remaining) == jsonEncode(ids)) return row;
        if (row.remaining.any(selectedIds.contains)) {
          throw const LibraryFailure('所选图包已有保存的删除选择，请从原入口继续或移除原选择');
        }
      }
      if (rows.length >= 32) throw const LibraryFailure('保存的删除选择过多，请先处理或移除旧选择');
      final value = PackPurgeSelection.fromJson({
        'id': packFileRequestId(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'historical': false,
        'ids': ids,
        'batches': <Object>[],
      });
      rows[value.id] = value.toJson();
      return value;
    }, namespace: _purgeSelectionsNamespace);
    _check();
    return result;
  }

  Future<void> discard(PackPurgeSelection expected) async {
    _check();
    await files.journal._edit(files.scope, (rows) {
      _check();
      if (rows[expected.id] == null) return;
      if (_purgeSelection(expected.id, rows[expected.id]).signature !=
          expected.signature) {
        throw const LibraryFailure('删除选择已有新批次，请重新读取后再移除');
      }
      rows.remove(expected.id);
    }, namespace: _purgeSelectionsNamespace);
    _check();
  }
}
