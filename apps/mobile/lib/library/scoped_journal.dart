import 'dart:async';
import 'dart:convert';

import 'models.dart';

/// Serializes the existing text stores without dropping another generation's
/// receipts. A scope is captured by its adapter, never read from a live owner.
class ScopedJournal {
  ScopedJournal({required this.readText, required this.writeText});
  final Future<String?> Function() readText;
  final Future<void> Function(String) writeText;
  Future<void> _tail = Future.value();
  Map<String, Map<String, dynamic>>? _scopes;

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _load() async {
    if (_scopes != null) return;
    final text = await readText();
    if (text == null) {
      _scopes = {};
      return;
    }
    try {
      final raw = Map<String, dynamic>.from(jsonDecode(text) as Map);
      final result = <String, Map<String, dynamic>>{};
      if (raw['version'] == 2 && raw['scopes'] is Map && raw.length == 2) {
        for (final entry in (raw['scopes'] as Map).entries) {
          final scope = entry.key as String;
          final value = Map<String, dynamic>.from(entry.value as Map);
          if (scope.isEmpty || scope.length > 8192 || value['scope'] != scope) {
            throw const FormatException();
          }
          result[scope] = value;
        }
      } else {
        final scope = raw['scope'];
        if (scope is! String || scope.isEmpty || scope.length > 8192) {
          throw const FormatException();
        }
        result[scope] = raw;
      }
      _scopes = result;
    } catch (_) {
      throw const LibraryFailure('本机操作日志无法读取，已保留原记录；请先核对操作任务');
    }
  }

  Future<String?> read(String scope) => _serial(() async {
    await _load();
    final value = _scopes![scope];
    return value == null ? null : jsonEncode(value);
  });

  Future<void> write(String scope, String text) => _serial(() async {
    await _load();
    Map<String, dynamic> value;
    try {
      value = Map<String, dynamic>.from(jsonDecode(text) as Map);
      if (value['scope'] != scope) throw const FormatException();
    } catch (_) {
      throw const LibraryFailure('操作日志所属连接不一致，未覆盖原记录');
    }
    final next = {..._scopes!, scope: value};
    // Preserve the existing single-scope format for a legacy connection. New
    // epoch scopes and multi-server books always use the versioned envelope.
    final encoded = next.length == 1 && isLegacyScope(scope)
        ? jsonEncode(value)
        : jsonEncode({'version': 2, 'scopes': next});
    try {
      await writeText(encoded);
    } catch (_) {
      // Storage can commit and then lose its acknowledgement. Re-read before
      // merging any later scope rather than overwriting that unknown result.
      _scopes = null;
      rethrow;
    }
    _scopes = next;
  });

  Future<Map<String, Map<String, dynamic>>> entries(String currentScope) =>
      _serial(() async {
        await _load();
        return {
          for (final entry in _scopes!.entries)
            if (sameServerScope(entry.key, currentScope))
              entry.key: Map<String, dynamic>.from(
                jsonDecode(jsonEncode(entry.value)) as Map,
              ),
        };
      });
}

bool isLegacyScope(String value) {
  try {
    return (jsonDecode(value) as List).length == 2;
  } catch (_) {
    return false;
  }
}

bool sameServerScope(String one, String two) {
  if (one == two) return true;
  try {
    final a = jsonDecode(one) as List, b = jsonDecode(two) as List;
    return (a.length == 2 || a.length == 3) &&
        (b.length == 2 || b.length == 3) &&
        a[0] is String &&
        a[1] is String &&
        a[0] == b[0] &&
        a[1] == b[1];
  } catch (_) {
    return false;
  }
}
