import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'file_command_store.dart';
import 'models.dart';
import 'pack_reading.dart';
import 'server_api.dart';

typedef PackFileCall = Future<Map<String, dynamic>> Function(
  String method,
  String path, {
  Map<String, dynamic>? body,
});

String packFileRequestId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

String packFileFailureMessage(Object failure) => failure is LibraryFailure
    ? failure.message
    : failure is RequestCancelled
    ? '服务连接或管理数据已变化，请关闭后重新打开'
    : '操作记录或网络结果未能确认，请查询原操作后再试';

String _id(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 128
    ? value
    : throw const LibraryFailure('图包操作身份不完整，请重新查询');
int _integer(Object? value) => value is int && value >= 0
    ? value
    : throw const LibraryFailure('图包操作结果不完整，请重新查询');
bool _flag(Object? value) =>
    value is bool ? value : throw const LibraryFailure('图包操作结果不完整，请重新查询');
Map<String, dynamic> _map(Object? value) => value is Map
    ? Map<String, dynamic>.from(value)
    : throw const LibraryFailure('图包操作结果不完整，请重新查询');
Object? _freeze(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key as String, _freeze(item))),
      )
    : value is List
    ? List.unmodifiable(value.map(_freeze))
    : value;

/// Immutable intent, including the original reading owner for quick cleanup.
class PackCleanupContext {
  PackCleanupContext({
    required this.entry,
    required this.quick,
    this.scrollOffset = 0,
    this.scrollAnchor,
    this.scrollIndex = 0,
    this.scrollInset = 0,
    this.sessionId,
    Iterable<String> anchors = const [],
  }) : anchors = List.unmodifiable(anchors) {
    if (!scrollOffset.isFinite ||
        scrollOffset < 0 ||
        !scrollInset.isFinite ||
        scrollIndex < 0 ||
        this.anchors.length > 16 ||
        this.anchors.toSet().length != this.anchors.length) {
      throw const LibraryFailure('阅读来源记录不完整');
    }
    for (final value in this.anchors) {
      _id(value);
    }
    if (scrollAnchor != null) _id(scrollAnchor);
    if (sessionId != null) _id(sessionId);
  }
  final PackReadingEntry entry;
  final bool quick;
  final String? sessionId;
  final double scrollOffset, scrollInset;
  final String? scrollAnchor;
  final int scrollIndex;
  final List<String> anchors;
  PackCleanupContext withQuick(bool value, {String? session}) =>
      PackCleanupContext(
        entry: entry,
        quick: value,
        scrollOffset: scrollOffset,
        scrollAnchor: scrollAnchor,
        scrollIndex: scrollIndex,
        scrollInset: scrollInset,
        anchors: anchors,
        sessionId: session ?? sessionId,
      );
  Map<String, dynamic> toJson() => {
    'query': entry.query.toJson(),
    'random': entry.random,
    'entry_anchor': entry.anchorId,
    'quick': quick,
    'scroll_offset': scrollOffset,
    'scroll_anchor': scrollAnchor,
    'scroll_index': scrollIndex,
    'scroll_inset': scrollInset,
    'anchors': anchors,
    'session_id': sessionId,
  };
  factory PackCleanupContext.fromJson(Map<String, dynamic> raw) {
    try {
      final query = _map(raw['query']);
      final folder = query['folder'], search = query['search'];
      if (folder is! String ||
          folder.length > 4096 ||
          search is! String ||
          search.length > 200) {
        throw const FormatException();
      }
      final tags = (query['tag_ids'] as List).map(_id).toList();
      if (tags.length > 256 || tags.toSet().length != tags.length) {
        throw const FormatException();
      }
      return PackCleanupContext(
        entry: PackReadingEntry(
          PackQuery(
            folder: folder,
            tags: tags,
            search: search,
            readState: PackReadState.values.byName(query['read_state']),
            source: BrowseSource.values.byName(query['source']),
            sort: PackSort.values.byName(query['sort']),
          ),
          anchorId: raw['entry_anchor'] == null
              ? null
              : _id(raw['entry_anchor']),
          random: _flag(raw['random']),
        ),
        quick: _flag(raw['quick']),
        scrollOffset: (raw['scroll_offset'] as num).toDouble(),
        scrollAnchor: raw['scroll_anchor'] == null
            ? null
            : _id(raw['scroll_anchor']),
        scrollIndex: _integer(raw['scroll_index']),
        scrollInset: (raw['scroll_inset'] as num).toDouble(),
        anchors: (raw['anchors'] as List).map(_id),
        sessionId: raw['session_id'] == null ? null : _id(raw['session_id']),
      );
    } catch (_) {
      throw const LibraryFailure('阅读来源记录不完整');
    }
  }
}

class PackFileCommand {
  PackFileCommand._(
    this.requestId,
    this.kind,
    this.path,
    Map<String, dynamic> body, {
    this.label,
    this.readerContext,
  }) : body = _freeze(body) as Map<String, dynamic> {
    _id(requestId);
    if (readerContext != null && body['reading'] == null && kind != 'undo') {
      throw const LibraryFailure('阅读来源缺少原阅读范围');
    }
    if (readerContext != null) {
      final scene = body['reading'] as Map?;
      if (readerContext!.sessionId == null ||
          (scene != null &&
              (readerContext!.sessionId != scene['session_id'] ||
                  readerContext!.quick != (scene['advance'] != false)))) {
        throw const LibraryFailure('阅读来源与整包操作不一致');
      }
    }
  }
  factory PackFileCommand.trash(
    String requestId,
    Iterable<String> ids, {
    ReaderCursor? reading,
    String? label,
    bool advance = true,
    PackCleanupContext? readerContext,
  }) => PackFileCommand._(
    requestId,
    'trash',
    '/api/v1/packs/trash',
    {
      'pack_ids': _ids(ids),
      if (reading != null)
        'reading': {
          'session_id': reading.sessionId,
          'expected_session_revision': reading.sessionRevision,
          'pack_id': reading.packId,
          'content_version': reading.version,
          'expected_progress_revision': reading.progressRevision,
          if (!advance) 'advance': false,
        },
    },
    label: label,
    readerContext: readerContext?.withQuick(
      readerContext.quick,
      session: reading?.sessionId,
    ),
  );
  factory PackFileCommand.restore(
    String requestId,
    Iterable<String> ids, {
    String? label,
  }) => PackFileCommand._(requestId, 'restore', '/api/v1/pack-trash/restore', {
    'trash_ids': _ids(ids),
  }, label: label);
  factory PackFileCommand.undo(
    String requestId,
    String operationId, {
    PackCleanupContext? readerContext,
  }) => PackFileCommand._(
    requestId,
    'undo',
    '/api/v1/pack-operations/${Uri.encodeComponent(_id(operationId))}/undo',
    {},
    readerContext: readerContext,
  );
  factory PackFileCommand.retry(
    String requestId,
    String operationId,
  ) => PackFileCommand._(
    requestId,
    'retry',
    '/api/v1/pack-operations/${Uri.encodeComponent(_id(operationId))}/retry',
    {},
  );
  static List<String> _ids(Iterable<String> ids) {
    final values = ids.map(_id).toSet().toList()..sort();
    if (values.isEmpty || values.length > 1000) {
      throw const LibraryFailure('每次请选择1至1000项');
    }
    return List.unmodifiable(values);
  }

  final String requestId, kind, path;
  final String? label;
  final PackCleanupContext? readerContext;
  String? get readingSessionId =>
      (body['reading'] as Map?)?['session_id'] as String? ??
      readerContext?.sessionId;
  final Map<String, dynamic> body;
  String get signature => jsonEncode([
    path,
    body,
    if (readerContext != null) readerContext!.toJson(),
  ]);
  Set<String> get resources => {
    for (final id in (body['pack_ids'] as List? ?? const [])) 'pack:$id',
    for (final id in (body['trash_ids'] as List? ?? const [])) 'trash:$id',
    if (kind == 'undo' || kind == 'retry') path.split('/').take(5).join('/'),
  };
  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'kind': kind,
    'path': path,
    'body': body,
    if (label != null) 'label': label,
    if (readerContext != null) 'reader_context': readerContext!.toJson(),
  };
  factory PackFileCommand.fromJson(Map<String, dynamic> value) {
    final kind = value['kind'], body = _map(value['body']);
    final requestId = _id(value['request_id']);
    PackFileCommand result;
    if (kind == 'trash') {
      final raw = body['reading'];
      final scene = raw == null ? null : _map(raw);
      result = PackFileCommand.trash(
        requestId,
        (body['pack_ids'] as List).cast<String>(),
        advance: scene == null || scene['advance'] == null
            ? true
            : _flag(scene['advance']),
        reading: scene == null
            ? null
            : ReaderCursor(
                sessionId: _id(scene['session_id']),
                packId: _id(scene['pack_id']),
                sessionRevision: _integer(scene['expected_session_revision']),
                version: _integer(scene['content_version']),
                progressRevision: _integer(scene['expected_progress_revision']),
              ),
      );
    } else if (kind == 'restore') {
      result = PackFileCommand.restore(
        requestId,
        (body['trash_ids'] as List).cast<String>(),
      );
    } else if (kind == 'undo' || kind == 'retry') {
      final parts = (value['path'] as String).split('/');
      if (parts.length != 6) throw const LibraryFailure('本机图包操作记录不完整');
      final operationId = Uri.decodeComponent(parts[4]);
      result = kind == 'undo'
          ? PackFileCommand.undo(requestId, operationId)
          : PackFileCommand.retry(requestId, operationId);
    } else {
      throw const LibraryFailure('本机图包操作记录不完整');
    }
    if (result.path != value['path'] ||
        jsonEncode(result.body) != jsonEncode(body)) {
      throw const LibraryFailure('本机图包操作记录不完整');
    }
    final label = value['label'];
    if (label != null && (label is! String || label.length > 1024)) {
      throw const LibraryFailure('本机图包操作记录不完整');
    }
    return PackFileCommand._(
      result.requestId,
      result.kind,
      result.path,
      result.body,
      label: label as String?,
      readerContext: value['reader_context'] == null
          ? null
          : PackCleanupContext.fromJson(_map(value['reader_context'])),
    );
  }
}

class PackFileItem {
  PackFileItem(Map<String, dynamic> raw)
    : requestedId = _id(raw['requested_id']),
      packId = _id(raw['pack_id']),
      trashId = _id(raw['trash_id']),
      outcome = _id(raw['outcome']),
      phase = _id(raw['phase']),
      error = raw['error'] as String? {
    if (!['succeeded', 'failed'].contains(outcome)) {
      throw const LibraryFailure('图包操作尚未确认完成');
    }
  }
  final String requestedId, packId, trashId, outcome, phase;
  final String? error;
  bool get succeeded => outcome == 'succeeded';
}

class PackReadingTransition {
  PackReadingTransition(Map<String, dynamic> raw)
    : sessionId = _id(raw['session_id']),
      revision = _integer(raw['revision']),
      cursor = _integer(raw['cursor']),
      packId = raw['pack_id'] == null ? null : _id(raw['pack_id']),
      finished = _flag(raw['finished']) {
    if (finished != (packId == null)) {
      throw const LibraryFailure('阅读转换结果不完整，请重新读取');
    }
  }
  final String sessionId;
  final String? packId;
  final int revision, cursor;
  final bool finished;
}

class PackFileResult {
  PackFileResult(Map<String, dynamic> raw, String operationId)
    : total = _integer(raw['total']),
      succeeded = _integer(raw['succeeded']),
      failed = _integer(raw['failed']),
      partial = _flag(raw['partial']),
      items = List.unmodifiable(
        (raw['items'] as List).map((i) => PackFileItem(_map(i))),
      ),
      readingRestored = _flag(raw['reading_restored']),
      transition = raw['reading_transition'] == null
          ? null
          : PackReadingTransition(_map(raw['reading_transition'])),
      undoExpiresAt = _deadline(raw['undo_expires_at']) {
    if (_id(raw['operation_id']) != operationId ||
        _integer(raw['processed']) != total ||
        total > 1000 ||
        total == 0 ||
        items.length != total ||
        succeeded + failed != total ||
        items.where((i) => i.succeeded).length != succeeded ||
        items.map((i) => i.requestedId).toSet().length != total ||
        partial != (succeeded > 0 && failed > 0)) {
      throw const LibraryFailure('图包操作结果不完整，请重新查询');
    }
  }
  static DateTime? _deadline(Object? value) {
    if (value == null) return null;
    if (value is! num ||
        !value.isFinite ||
        value <= 0 ||
        value > 8640000000000) {
      throw const LibraryFailure('撤销期限不完整，请重新查询');
    }
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
  }

  final int total, succeeded, failed;
  final bool partial, readingRestored;
  final List<PackFileItem> items;
  final PackReadingTransition? transition;
  final DateTime? undoExpiresAt;
}

class PackFileTask {
  factory PackFileTask.fromJson(Map<String, dynamic> raw) {
    try {
      return PackFileTask._(raw);
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('图包操作结果不完整，请重新查询');
    }
  }
  PackFileTask._(Map<String, dynamic> raw)
    : id = _id(raw['id']),
      kind = _id(raw['kind']),
      status = _id(raw['status']),
      error = raw['error'] as String?,
      serverTime = PackFileResult._deadline(raw['server_time']),
      receivedAt = DateTime.now() {
    if (!['pack_trash', 'pack_restore', 'pack_undo'].contains(kind) ||
        ![
          'queued',
          'running',
          'completed',
          'failed',
          'interrupted',
        ].contains(status)) {
      throw const LibraryFailure('图包任务类型或状态不完整，请重新查询');
    }
    if (status == 'completed' ||
        (status == 'failed' && _map(raw['result']).isNotEmpty)) {
      result = PackFileResult(_map(raw['result']), id);
      if ((status == 'completed') != (result!.succeeded > 0)) {
        throw const LibraryFailure('图包任务结果与状态不一致，请重新查询');
      }
    } else {
      result = null;
    }
  }
  final String id, kind, status;
  final String? error;
  final DateTime? serverTime;
  final DateTime receivedAt;
  late final PackFileResult? result;
  bool get settled => result != null;
  Duration remainingUndo([DateTime? now]) {
    final expires = result?.undoExpiresAt;
    if (expires == null) return Duration.zero;
    final remaining =
        expires.difference(serverTime ?? receivedAt) -
        (now ?? DateTime.now()).difference(receivedAt);
    if (remaining <= Duration.zero) return Duration.zero;
    return remaining > const Duration(seconds: 8)
        ? const Duration(seconds: 8)
        : remaining;
  }
}

/// One serialized journal shared by all connection-bound gateways. A stale
/// connection can finish its disk write without replacing another scope's book.
class PackFileJournal {
  PackFileJournal(this.store);
  final FileCommandStore store;
  Future<void> _tail = Future.value();
  Map<String, dynamic>? _book;
  Future<T> _edit<T>(
    String scope,
    T Function(Map<String, dynamic>) action, {
    bool write = true,
  }) {
    final result = _tail.then((_) async {
      if (_book == null) {
        final text = await store.read();
        try {
          _book = text == null
              ? {'version': 1, 'scopes': <String, dynamic>{}}
              : _map(jsonDecode(text));
          if (_book!['version'] != 1) throw const FormatException();
          _map(_book!['scopes']);
        } catch (_) {
          _book = null;
          throw const LibraryFailure('本机图包操作记录无法读取，请先核对服务端任务');
        }
      }
      final next = _map(jsonDecode(jsonEncode(_book)));
      final scopes = _map(next['scopes']);
      final commands = _map(scopes[scope] ?? <String, dynamic>{});
      final value = action(commands);
      if (write) {
        scopes[scope] = commands;
        next['scopes'] = scopes;
        await store.write(jsonEncode(next));
        _book = next;
      }
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<PackFileCommand>> pending(String scope) => _edit(
    scope,
    (commands) => List.unmodifiable(
      commands.values.map(
        (v) => PackFileCommand.fromJson(_map(_map(v)['command'])),
      ),
    ),
    write: false,
  );
  Future<String?> remember(String scope, PackFileCommand command) =>
      _edit(scope, (commands) {
        final previous = commands[command.requestId];
        if (previous != null) {
          final row = _map(previous);
          if (PackFileCommand.fromJson(_map(row['command'])).signature !=
              command.signature) {
            throw const LibraryFailure('请求标识已用于不同的图包操作');
          }
          return row['task_id'] as String?;
        }
        for (final row in commands.values) {
          final previous = PackFileCommand.fromJson(_map(_map(row)['command']));
          if (previous.resources.intersection(command.resources).isNotEmpty) {
            throw const LibraryFailure('这项图包操作的结果尚未确认，请先查询原结果');
          }
        }
        if (commands.length >= 256) {
          throw const LibraryFailure('待核对图包操作过多，请先查询原结果');
        }
        commands[command.requestId] = {'command': command.toJson()};
        return null;
      });
  Future<void> accepted(
    String scope,
    PackFileCommand command,
    String identity,
  ) => _edit(scope, (commands) {
    final row = _map(commands[command.requestId]);
    if (row['task_id'] != null && row['task_id'] != identity) {
      throw const LibraryFailure('服务端原请求身份已变化，请先核对任务');
    }
    row['task_id'] = identity;
    commands[command.requestId] = row;
  });
  Future<void> forget(String scope, String requestId) =>
      _edit(scope, (commands) {
        commands.remove(requestId);
      });
  Future<String?> identity(String scope, String requestId) => _edit(
    scope,
    (commands) => commands[requestId] == null
        ? null
        : _map(commands[requestId])['task_id'] as String?,
    write: false,
  );
}

/// All mutations are explicit; reopening and receipt lookup only perform GET.
/// The journal is written before POST and retained until a settled result is
/// acknowledged, including 404, interrupted tasks and malformed responses.
class PackFiles {
  PackFiles({
    required this.journal,
    required this.scope,
    required this.call,
    required this.isCurrent,
    this.pollDelay = const Duration(milliseconds: 350),
  });
  final PackFileJournal journal;
  final String scope;
  final PackFileCall call;
  final bool Function() isCurrent;
  final Duration pollDelay;
  final Map<String, Future<PackFileTask>> _sending = {};
  final Map<String, String> _sendingSignatures = {};
  final Map<String, PackFileTask> _settled = {};
  void _check() {
    if (!isCurrent()) throw const RequestCancelled();
  }

  Future<List<PackFileCommand>> pending() async {
    _check();
    final result = await journal.pending(scope);
    _check();
    return result;
  }

  Future<bool> canResend(PackFileCommand command) async {
    _check();
    final identity = await journal.identity(scope, command.requestId);
    _check();
    return identity == null;
  }

  Future<PackFileTask> send(PackFileCommand command) {
    _check();
    final active = _sending[command.requestId];
    if (active != null) {
      if (_sendingSignatures[command.requestId] != command.signature) {
        return Future.error(const LibraryFailure('请求标识已用于不同的图包操作'));
      }
      return active;
    }
    final work = _send(command);
    _sending[command.requestId] = work;
    _sendingSignatures[command.requestId] = command.signature;
    unawaited(
      work.then<void>(
        (_) {
          _sending.remove(command.requestId);
          _sendingSignatures.remove(command.requestId);
        },
        onError: (Object _, StackTrace _) {
          _sending.remove(command.requestId);
          _sendingSignatures.remove(command.requestId);
        },
      ),
    );
    return work;
  }

  Future<PackFileTask> _send(PackFileCommand command) async {
    _settled.remove(command.requestId);
    final known = await journal.remember(scope, command);
    _check();
    Map<String, dynamic> raw;
    if (known != null) {
      raw = await call(
        'GET',
        '/api/v1/pack-operations/${Uri.encodeComponent(known)}',
      );
    } else {
      try {
        raw = await call(
          'POST',
          command.path,
          body: {'request_id': command.requestId, ...command.body},
        );
      } on ApiFailure catch (failure) {
        _check();
        if (failure.status != null &&
            failure.status! >= 400 &&
            failure.status! < 500 &&
            ![408, 429].contains(failure.status)) {
          await journal.forget(scope, command.requestId);
        }
        rethrow;
      }
    }
    _check();
    return _accept(command, raw);
  }

  Future<PackFileTask> _accept(
    PackFileCommand command,
    Map<String, dynamic> raw,
  ) async {
    final task = PackFileTask.fromJson(raw);
    final expected = command.kind == 'retry' ? null : 'pack_${command.kind}';
    if (expected != null && task.kind != expected) {
      throw const LibraryFailure('服务端图包任务类型与请求不一致');
    }
    if (command.kind == 'retry' &&
        task.id != Uri.decodeComponent(command.path.split('/')[4])) {
      throw const LibraryFailure('重试结果与原图包任务不一致');
    }
    final requested =
        command.body[command.kind == 'trash' ? 'pack_ids' : 'trash_ids'];
    if (requested is List &&
        task.result != null &&
        (task.result!.total != requested.length ||
            !task.result!.items.every(
              (item) => requested.contains(item.requestedId),
            ))) {
      throw const LibraryFailure('图包操作结果与所选内容不一致');
    }
    await journal.accepted(scope, command, task.id);
    _check();
    if (task.settled) _settled[command.requestId] = task;
    return task;
  }

  Future<PackFileTask?> receipt(PackFileCommand command) async {
    _check();
    _settled.remove(command.requestId);
    try {
      final route = command.kind == 'retry'
          ? 'pack-retry-requests'
          : 'pack-file-requests';
      final raw = await call(
        'GET',
        '/api/v1/$route/${Uri.encodeComponent(command.requestId)}',
      );
      _check();
      return await _accept(command, raw);
    } on ApiFailure catch (error) {
      _check();
      if (error.status == 404) return null;
      rethrow;
    }
  }

  Future<PackFileTask?> resolve(
    PackFileCommand command, {
    bool submit = false,
    Duration timeout = const Duration(seconds: 25),
    bool Function()? keepWaiting,
  }) async {
    var task = submit ? await send(command) : await receipt(command);
    final deadline = DateTime.now().add(timeout);
    while (task != null &&
        !task.settled &&
        ['queued', 'running'].contains(task.status) &&
        (keepWaiting?.call() ?? true) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollDelay);
      _check();
      if (keepWaiting != null && !keepWaiting()) break;
      task = await receipt(command);
    }
    return task;
  }

  Future<void> acknowledge(PackFileCommand command) async {
    _check();
    if (_settled[command.requestId] == null) {
      throw const LibraryFailure('请先查询并核对这次图包操作结果');
    }
    await journal.forget(scope, command.requestId);
    _check();
    _settled.remove(command.requestId);
  }
}
