import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'backup_document.dart';
import 'request_scope.dart';
export 'request_scope.dart';
export 'models.dart' show RequestCancelled;

class ApiFailure extends LibraryFailure {
  const ApiFailure(super.message, {required this.code, this.status});
  final String code;
  final int? status;
}

class ApiResponse {
  const ApiResponse(this.status, this.bytes, this.headers);
  final int status;
  final Uint8List bytes;
  final Map<String, String> headers;
}

class ApiFileResponse extends ApiResponse {
  ApiFileResponse(int status, this.document, Map<String, String> headers)
    : super(status, Uint8List(0), headers);
  final BackupDocument document;
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
  String? _managementEpoch;
  bool _authorityBound = false, _authorityChanged = false;
  void Function()? onManagementChanged;
  String? get managementEpoch => _managementEpoch;

  /// A transport is bound once. A replacement library needs a new transport,
  /// leaving every old gateway and in-flight command on its captured epoch.
  void bindAuthority(Map<String, dynamic> info) {
    final supported = ServiceCapabilities.fromInfo(info).managementAuthority;
    final value = supported ? info['management_epoch'] : null;
    if (supported &&
        (value is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(value))) {
      throw const ApiFailure('服务管理数据身份不完整，请重新连接', code: 'invalid_response');
    }
    if (_authorityBound && _managementEpoch != value) {
      throw StateError('A ServerApi cannot adopt another management epoch');
    }
    _managementEpoch = value as String?;
    _authorityBound = true;
  }

  void _changed() {
    if (_authorityChanged) return;
    _authorityChanged = true;
    onManagementChanged?.call();
  }

  Map<String, String> get authorization => token.isEmpty
      ? {}
      : {
          'Authorization': 'Bearer $token',
          'X-Management-Epoch': ?_managementEpoch,
        };

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
    bool originalReceipt = false,
  }) async {
    final response = await request(
      method,
      path,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      query: query,
      scope: scope,
      originalReceipt: originalReceipt,
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
    bool originalReceipt = false,
    int maximumBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    return _request(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
      scope: scope,
      originalReceipt: originalReceipt,
      maximumBytes: maximumBytes,
      timeout: timeout,
    );
  }

  Future<ApiResponse> uploadFile(
    String path,
    BackupDocument document, {
    Map<String, String> headers = const {},
    RequestScope? scope,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final elapsed = Stopwatch()..start();
    await document.verify(scope: scope);
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw const ApiFailure('核对备份文件超时，请重新选择', code: 'timeout');
    }
    return _request(
      'POST',
      path,
      bodyStream: document.verifiedRead(scope: scope),
      contentLength: document.bytes,
      headers: {'Content-Type': 'application/x-ndjson', ...headers},
      scope: scope,
      timeout: remaining,
    );
  }

  Future<BackupDocument> downloadFile(
    String path,
    BackupFileStore store, {
    required int expectedBytes,
    required String expectedSha256,
    required int maximumBytes,
    Map<String, dynamic>? query,
    bool originalReceipt = false,
    RequestScope? scope,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final response = await _request(
      'GET',
      path,
      query: query,
      fileStore: store,
      expectedBytes: expectedBytes,
      expectedSha256: expectedSha256,
      maximumBytes: maximumBytes,
      originalReceipt: originalReceipt,
      scope: scope,
      timeout: timeout,
    );
    return (response as ApiFileResponse).document;
  }

  Future<ApiResponse> _request(
    String method,
    String path, {
    List<int>? body,
    Stream<List<int>>? bodyStream,
    int? contentLength,
    BackupFileStore? fileStore,
    int? expectedBytes,
    String? expectedSha256,
    Map<String, dynamic>? query,
    Map<String, String> headers = const {},
    RequestScope? scope,
    bool originalReceipt = false,
    int maximumBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final explicitHistoryFile =
        RegExp(r'^/api/v1/management-history/tasks/[^/]+/download$')
            .hasMatch(path) &&
        query != null &&
        query.keys.every((key) => ['epoch', 'graph_id'].contains(key)) &&
        (query['epoch'] is String &&
                RegExp(r'^[a-f0-9]{32}$').hasMatch(query['epoch']) ||
            query['graph_id'] is String &&
                RegExp(
                  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
                ).hasMatch(query['graph_id']));
    if (originalReceipt &&
        (method != 'GET' && method != 'HEAD' ||
            body != null ||
            bodyStream != null ||
            !explicitHistoryFile &&
                !RegExp(
                  r'^/api/v1/(tasks/[^/]+|backup-requests/(export|inspect|restore)/[^/]+|backups/[^/]+/download|management-backups/requests/(export|inspect|restore)/[^/]+|management-backups/[^/]+/download)$',
                ).hasMatch(path))) {
      throw ArgumentError('Only an original read can cross a management epoch');
    }
    if (headers.keys.any((key) => key.toLowerCase() == 'x-management-epoch')) {
      throw ArgumentError('The transport owns its management epoch');
    }
    if (_authorityChanged && !originalReceipt) {
      throw const ApiFailure('管理数据已恢复，请重新读取当前媒体库', code: 'management_changed');
    }
    final elapsed = Stopwatch()..start();
    Future<ApiResponse> attempt(Duration budget) => _requestOnce(
      method,
      path,
      body: body,
      bodyStream: bodyStream,
      contentLength: contentLength,
      fileStore: fileStore,
      expectedBytes: expectedBytes,
      expectedSha256: expectedSha256,
      query: query,
      headers: headers,
      scope: scope,
      maximumBytes: maximumBytes,
      timeout: budget,
      originalReceipt: originalReceipt,
    );
    try {
      return await attempt(timeout);
    } on ApiFailure catch (error) {
      final remaining = timeout - elapsed.elapsed;
      if (error.code != 'network_unavailable' ||
          (method != 'GET' && method != 'HEAD') ||
          body != null ||
          bodyStream != null ||
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
    Stream<List<int>>? bodyStream,
    int? contentLength,
    BackupFileStore? fileStore,
    int? expectedBytes,
    String? expectedSha256,
    Map<String, dynamic>? query,
    Map<String, String> headers = const {},
    RequestScope? scope,
    bool originalReceipt = false,
    int maximumBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_closed || scope?.cancelled == true) throw const RequestCancelled();
    HttpClientRequest? request;
    StreamSubscription<List<int>>? subscription;
    Completer<Uint8List>? completion;
    Object? interruption;
    final receiving = RequestScope();
    BackupDocument? downloaded;
    var returned = false;

    void interrupt(Object error) {
      interruption ??= error;
      receiving.cancel();
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
      if (bodyStream != null) {
        if (body != null) throw ArgumentError('Only one request body');
        if (contentLength != null) request.contentLength = contentLength;
        await request.addStream(bodyStream);
      } else if (body != null) {
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      final fileHeaders = <String, String>{};
      response.headers.forEach(
        (key, values) => fileHeaders[key] = values.join(', '),
      );
      if (fileStore != null &&
          response.statusCode >= 200 &&
          response.statusCode < 300) {
        _verifyAuthority(fileHeaders, null, originalReceipt);
        if (response.contentLength >= 0 &&
            response.contentLength != expectedBytes) {
          throw const ApiFailure(
            '原备份文件大小不一致，请查询原任务',
            code: 'backup_artifact_changed',
          );
        }
        downloaded = await fileStore.capture(
          response,
          maximumBytes: maximumBytes,
          expectedBytes: expectedBytes,
          expectedSha256: expectedSha256,
          scope: receiving,
        );
        _verifyAuthority(fileHeaders, null, originalReceipt);
        if (_closed || scope?.cancelled == true) throw const RequestCancelled();
        returned = true;
        return ApiFileResponse(response.statusCode, downloaded, fileHeaders);
      }
      final chunks = BytesBuilder(copy: false);
      final bodyDone = Completer<Uint8List>();
      completion = bodyDone;
      subscription = response.listen(
        (chunk) {
          if (bodyDone.isCompleted) return;
          if (chunks.length + chunk.length >
              (fileStore == null ? maximumBytes : 2 * 1024 * 1024)) {
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
      ApiFailure? failure;
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
        failure = ApiFailure(message, code: code, status: response.statusCode);
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach(
        (key, values) => responseHeaders[key] = values.join(', '),
      );
      _verifyAuthority(responseHeaders, failure, originalReceipt);
      if (failure != null) throw failure;
      if (_closed || scope?.cancelled == true) throw const RequestCancelled();
      returned = true;
      return ApiResponse(response.statusCode, bytes, responseHeaders);
    } on RequestCancelled {
      if (interruption is TimeoutException) {
        throw const ApiFailure('连接超时，请检查服务后重试', code: 'timeout');
      }
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
      receiving.cancel();
      if (!returned) {
        request?.abort();
        await downloaded?.delete();
      }
      scope?.remove(cancel);
      _lifetime.remove(cancel);
      await subscription?.cancel();
    }
  }

  void _verifyAuthority(
    Map<String, String> responseHeaders,
    ApiFailure? failure,
    bool originalReceipt,
  ) {
    if (failure?.status != 401 && _managementEpoch != null) {
      final epoch = responseHeaders['x-management-epoch'];
      if (failure?.code == 'management_changed' && !originalReceipt) {
        _changed();
        throw failure!;
      }
      if (epoch == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(epoch)) {
        throw const ApiFailure(
          '服务管理数据身份未能确认，请查询原操作后重试',
          code: 'authority_unavailable',
        );
      }
      if ((_authorityChanged || epoch != _managementEpoch) &&
          !originalReceipt) {
        _changed();
        // A successful old write may have committed before a restore. Keep
        // its receipt unknown rather than classifying this as rejected 409.
        throw const ApiFailure(
          '管理数据已恢复，原操作结果请到任务中心核对',
          code: 'management_changed',
        );
      }
    }
  }

  void close() {
    _closed = true;
    _lifetime.cancel();
    _client.close(force: true);
  }
}
