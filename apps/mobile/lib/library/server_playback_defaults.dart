part of 'server_repository.dart';

class _ServerPlaybackDefaults implements PlaybackDefaultsGateway {
  _ServerPlaybackDefaults(
    this.owner,
    this.api,
    this.generation,
    this.epoch,
    this.scope,
  );
  final ServerLibraryRepository owner;
  final ServerApi api;
  final int generation, epoch;
  @override
  final String scope;
  final lifetime = RequestScope();
  bool disposed = false;
  @override
  bool get isCurrent =>
      !disposed &&
      !owner._disposed &&
      identical(api, owner._api) &&
      generation == owner._generation &&
      epoch == owner._readerEpoch &&
      !owner.backupRestorePending;
  void current() {
    if (!isCurrent) throw const RequestCancelled();
  }

  PlaybackDefaults decode(Json data, [WritePlaybackDefaults? command]) {
    final order = PlayOrder.values
        .where((v) => v.name == data['order'])
        .firstOrNull;
    final revision = data['revision'];
    if (order == null ||
        revision is! int ||
        revision < 0 ||
        (command != null &&
            (order != command.value.order ||
                revision != command.value.revision + 1))) {
      throw const ApiFailure('服务返回的默认播放顺序不完整，请重新核对', code: 'invalid_response');
    }
    return PlaybackDefaults(order, revision);
  }

  Future<Json> call(String method, String path, {Json? body}) async {
    current();
    final data = await owner.call(
      method,
      path,
      body: body,
      using: api,
      cancel: lifetime,
    );
    current();
    return data;
  }

  @override
  Future<PlaybackDefaults> read() async =>
      decode(await call('GET', '/api/v1/playback-defaults'));
  @override
  Future<PlaybackDefaults> submit(WritePlaybackDefaults command) async =>
      decode(
        await call(
          'PATCH',
          '/api/v1/playback-defaults',
          body: {
            'request_id': command.requestId,
            'expected_revision': command.value.revision,
            'order': command.value.order.name,
          },
        ),
        command,
      );
  @override
  Future<PlaybackDefaults?> receipt(WritePlaybackDefaults command) async {
    try {
      final data = await call(
        'GET',
        '/api/v1/playback-default-requests/${Uri.encodeComponent(command.requestId)}',
      );
      if (data['status'] != 'completed' || data['result'] is! Map) {
        throw const ApiFailure('服务未返回完整设置回执', code: 'invalid_response');
      }
      return decode(object(data['result']), command);
    } on ApiFailure catch (error) {
      if (error.status == 404 && error.code == 'defaults_request_not_found') {
        return null;
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    lifetime.cancel();
    owner._defaultsReaders.remove(this);
  }
}
