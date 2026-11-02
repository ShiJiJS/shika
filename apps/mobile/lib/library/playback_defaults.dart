import 'models.dart';

class PlaybackDefaults {
  const PlaybackDefaults(this.order, this.revision);
  final PlayOrder order;
  final int revision;
}

class WritePlaybackDefaults {
  const WritePlaybackDefaults(this.requestId, this.value);
  final String requestId;
  final PlaybackDefaults value;
}

/// Bound to one endpoint/server instance and management-data generation.
abstract class PlaybackDefaultsGateway {
  String get scope;
  bool get isCurrent;
  Future<PlaybackDefaults> read();
  Future<PlaybackDefaults> submit(WritePlaybackDefaults command);
  Future<PlaybackDefaults?> receipt(WritePlaybackDefaults command);
  void dispose();
}
