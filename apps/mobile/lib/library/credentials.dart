import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Only the revocable session is retained; the service passphrase is never saved.
class ConnectionCredentials {
  const ConnectionCredentials({
    required this.endpoint,
    required this.token,
    required this.serverId,
    required this.expiresAt,
  });
  final Uri endpoint;
  final String token, serverId;
  final DateTime expiresAt;

  String encode() => jsonEncode({
    'endpoint': endpoint.toString(),
    'token': token,
    'serverId': serverId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  });

  static ConnectionCredentials? decode(String? text) {
    if (text == null) return null;
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      final endpoint = Uri.parse(data['endpoint'] as String);
      if (!['http', 'https'].contains(endpoint.scheme) ||
          endpoint.host.isEmpty ||
          endpoint.userInfo.isNotEmpty ||
          endpoint.hasQuery ||
          endpoint.hasFragment ||
          (endpoint.path.isNotEmpty && endpoint.path != '/')) {
        return null;
      }
      final token = data['token'] as String;
      if (token.isEmpty || token.length > 256) return null;
      return ConnectionCredentials(
        endpoint: endpoint,
        token: token,
        serverId: data['serverId'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

abstract interface class CredentialStore {
  Future<ConnectionCredentials?> read();
  Future<Uri?> readEndpoint();
  Future<void> save(ConnectionCredentials credentials);
  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({
    FlutterSecureStorage? storage,
    this.key = 'video_viewer.connection.v1',
  }) : storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage storage;
  final String key;

  @override
  Future<Uri?> readEndpoint() async {
    final text = await storage.read(key: '$key.endpoint');
    if (text == null) return (await read())?.endpoint;
    try {
      final uri = Uri.parse(text);
      return ['http', 'https'].contains(uri.scheme) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              (uri.path.isEmpty || uri.path == '/') &&
              !uri.hasQuery &&
              !uri.hasFragment
          ? uri
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ConnectionCredentials?> read() async =>
      ConnectionCredentials.decode(await storage.read(key: key));

  @override
  Future<void> save(ConnectionCredentials credentials) async {
    await storage.write(key: key, value: credentials.encode());
    await storage.write(
      key: '$key.endpoint',
      value: credentials.endpoint.toString(),
    );
  }

  @override
  Future<void> clear() => storage.delete(key: key);
}

class MemoryCredentialStore implements CredentialStore {
  ConnectionCredentials? value;
  Uri? endpoint;
  @override
  Future<Uri?> readEndpoint() async => endpoint;
  @override
  Future<ConnectionCredentials?> read() async => value;
  @override
  Future<void> save(ConnectionCredentials credentials) async {
    value = credentials;
    endpoint = credentials.endpoint;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
