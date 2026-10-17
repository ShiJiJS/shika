import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
export 'models.dart' show RequestCancelled;

class ApiFailure extends LibraryFailure {
  const ApiFailure(super.message, {required this.code, this.status});
  final String code;
  final int? status;
}

/// Cancels obsolete HTTP work as well as preventing its result from publishing.
class RequestScope {
  bool cancelled = false;
  final Set<void Function()> _callbacks = {};

  void add(void Function() callback) {
    if (cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void remove(void Function() callback) => _callbacks.remove(callback);
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final callback in _callbacks.toList()) {
      callback();
    }
    _callbacks.clear();
  }
}

class ApiResponse {
  const ApiResponse(this.status, this.bytes, this.headers);
  final int status;
  final Uint8List bytes;
  final Map<String, String> headers;
}

class ServerApi {
  ServerApi(this.endpoint, {this.token = '', HttpClient? client})
    : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 8);
    _client.idleTimeout = const Duration(seconds: 15);
    _client.maxConnectionsPerHost = 4;
  }
  final Uri endpoint;
  String token;
  final HttpClient _client;
  bool _closed = false;
  final RequestScope _lifetime = RequestScope();

  Map<String, String> get authorization =>
      token.isEmpty ? {} : {'Authorization': 'Bearer $token'};

  Uri resolve(String path) {
    final uri = endpoint.resolve(path);
    if (uri.origin != endpoint.origin || uri.userInfo.isNotEmpty) {
      throw const ApiFailure('服务返回了不合法的媒体地址', code: 'invalid_media_url');
    }
    return uri;
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    RequestScope? scope,
  }) async {
    final response = await request(
      method,
      path,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      query: query,
      scope: scope,
    );
    if (response.bytes.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bytes)) as Map,
      );
    } catch (_) {
      throw const ApiFailure('服务响应格式不正确，请重试', code: 'invalid_response');
    }
  }

  Future<ApiResponse> request(
    String method,
    String path, {
    List<int>? body,
    Map<String, dynamic>? query,
    Map<String, String> headers = const {},
    RequestScope? scope,
    int maximumBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final elapsed = Stopwatch()..start();
    Future<ApiResponse> attempt(Duration budget) => _requestOnce(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
      scope: scope,
      maximumBytes: maximumBytes,
      timeout: budget,
    );
    try {
      return await attempt(timeout);
    } on ApiFailure catch (error) {
      final remaining = timeout - elapsed.elapsed;
      if (error.code != 'network_unavailable' ||
          (method != 'GET' && method != 'HEAD') ||
          body != null ||
          remaining <= Duration.zero ||
          _closed ||
          scope?.cancelled == true) {
        rethrow;
      }
      // A broken idle socket or truncated read may be retried once. Writes
      // retain their caller-owned command ID and are never replayed here.
      return attempt(remaining);
    }
  }

  Future<ApiResponse> _requestOnce(
    String method,
    String path, {
    List<int>? body,
    Map<String, dynamic>? query,
    Map<String, String> headers = const {},
    RequestScope? scope,
    int maximumBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_closed || scope?.cancelled == true) throw const RequestCancelled();
    HttpClientRequest? request;
    StreamSubscription<List<int>>? subscription;
    Completer<Uint8List>? completion;
    Object? interruption;

    void interrupt(Object error) {
      interruption ??= error;
      request?.abort(error);
      unawaited(subscription?.cancel());
      if (completion != null && !completion.isCompleted) {
        completion.completeError(error);
      }
    }

    void cancel() => interrupt(const RequestCancelled());
    scope?.add(cancel);
    _lifetime.add(cancel);
    final timer = Timer(
      timeout,
      () => interrupt(TimeoutException('request deadline')),
    );
    try {
      var uri = resolve(path);
      if (query != null) uri = uri.replace(queryParameters: query);
      request = await _client
          .openUrl(method, uri)
          .then((opened) {
            if (interruption != null || _closed) opened.abort(interruption);
            return opened;
          })
          .timeout(timeout);
      if (interruption != null) throw interruption!;
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      for (final entry in {...authorization, ...headers}.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) request.add(body);
      final response = await request.close().timeout(timeout);
      final chunks = BytesBuilder(copy: false);
      final bodyDone = Completer<Uint8List>();
      completion = bodyDone;
      subscription = response.listen(
        (chunk) {
          if (bodyDone.isCompleted) return;
          if (chunks.length + chunk.length > maximumBytes) {
            interrupt(
              const ApiFailure('服务响应过大，请缩小范围后重试', code: 'response_too_large'),
            );
            return;
          }
          chunks.add(chunk);
        },
        onError: (Object error, StackTrace stack) {
          if (!bodyDone.isCompleted) bodyDone.completeError(error, stack);
        },
        onDone: () {
          if (!bodyDone.isCompleted) {
            bodyDone.complete(chunks.takeBytes());
          }
        },
        cancelOnError: true,
      );
      if (interruption != null) interrupt(interruption!);
      final bytes = await bodyDone.future;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var code = 'http_${response.statusCode}';
        var message = response.statusCode == 401
            ? '连接凭据已失效，请重新输入口令'
            : '服务暂时无法完成操作，请重试';
        try {
          final error = (jsonDecode(utf8.decode(bytes)) as Map)['error'] as Map;
          code = error['code'] as String;
          final detail = error['message'] as String;
          if (detail.length <= 256) message = detail;
        } catch (_) {
          // Proxy HTML and transport diagnostics are not shown as app content.
        }
        throw ApiFailure(message, code: code, status: response.statusCode);
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach(
        (key, values) => responseHeaders[key] = values.join(', '),
      );
      return ApiResponse(response.statusCode, bytes, responseHeaders);
    } on RequestCancelled {
      rethrow;
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure('连接超时，请检查服务后重试', code: 'timeout');
    } on IOException {
      request?.abort();
      if (interruption is RequestCancelled || _closed) {
        throw const RequestCancelled();
      }
      if (interruption is TimeoutException) {
        throw const ApiFailure('连接超时，请检查服务后重试', code: 'timeout');
      }
      throw const ApiFailure(
        '暂时无法连接服务，请检查地址和网络后重试',
        code: 'network_unavailable',
      );
    } finally {
      timer.cancel();
      scope?.remove(cancel);
      _lifetime.remove(cancel);
      await subscription?.cancel();
    }
  }

  void close() {
    _closed = true;
    _lifetime.cancel();
    _client.close(force: true);
  }
}
