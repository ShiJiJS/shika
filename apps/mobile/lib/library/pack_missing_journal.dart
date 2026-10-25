part of 'pack_files.dart';

const _missingNamespace = 'missing_cleanup_v1';

MissingCleanupReceipt _missingEntry(MapEntry<String, dynamic> entry) {
  final value = _map(entry.value),
      request = _id(_map(entry.value)['request_id']);
  if (entry.key != request) throw const LibraryFailure('本机清理请求记录不完整，请核对服务端任务');
  return MissingCleanupReceipt(request, historical: _flag(value['historical']));
}

extension MissingCleanupJournal on PackFileJournal {
  Future<List<MissingCleanupReceipt>> missingPending(String scope) => _edit(
    scope,
    (rows) => [for (final entry in rows.entries) _missingEntry(entry)],
    namespace: _missingNamespace,
    write: false,
  );
  Future<bool> rememberMissing(String scope, String requestId) =>
      _edit(scope, (rows) {
        _id(requestId);
        if (rows.containsKey(requestId)) return false;
        if (rows.values.any((v) => !_flag(_map(v)['historical']))) {
          throw const LibraryFailure('已有清理结果待核对，请先查询原请求');
        }
        if (rows.length >= 256) throw const LibraryFailure('本机清理记录过多，请先核对原任务');
        rows[requestId] = {'request_id': requestId, 'historical': false};
        return true;
      }, namespace: _missingNamespace);
  Future<void> forgetMissingReceipt(String scope, String requestId) =>
      _edit(scope, (rows) {
        rows.remove(_id(requestId));
      }, namespace: _missingNamespace);
  Future<void> historicalMissing(String scope) => _edit(scope, (rows) {
    for (final entry in rows.entries.toList()) {
      rows[entry.key] = {..._map(entry.value), 'historical': true};
    }
  }, namespace: _missingNamespace);
}
