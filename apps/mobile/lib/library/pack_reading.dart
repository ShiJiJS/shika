import 'models.dart';
import 'pack_models.dart';

/// The immutable query carries the same source/order as its catalogue entry.
class PackReadingEntry {
  PackReadingEntry(
    PackQuery query, {
    BrowseSource? source,
    this.anchorId,
    this.random = false,
  }) : query = source == null ? query : query.copy(source: source);
  final PackQuery query;
  BrowseSource get source => query.source;
  final String? anchorId;
  final bool random;
}

enum ReaderMode { horizontal, vertical }

enum ReaderDirection { ltr, rtl }

enum ReaderFit { contain, width }

class ReaderPreferences {
  const ReaderPreferences({
    this.mode = ReaderMode.vertical,
    this.direction = ReaderDirection.ltr,
    this.gap = false,
    this.fit = ReaderFit.contain,
    this.revision = 0,
    this.overridden = false,
  });
  final ReaderMode mode;
  final ReaderDirection direction;
  final ReaderFit fit;
  final bool gap, overridden;
  final int revision;
  Map<String, dynamic> get values => {
    'mode': mode.name,
    'direction': direction.name,
    'gap': gap,
    'fit': fit.name,
  };
  ReaderPreferences copy({
    ReaderMode? mode,
    ReaderDirection? direction,
    ReaderFit? fit,
    bool? gap,
  }) => ReaderPreferences(
    mode: mode ?? this.mode,
    direction: direction ?? this.direction,
    fit: fit ?? this.fit,
    gap: gap ?? this.gap,
    revision: revision,
    overridden: overridden,
  );
}

class ReaderPage {
  const ReaderPage({
    required this.id,
    required this.packId,
    required this.name,
    required this.ordinal,
    required this.width,
    required this.height,
    required this.version,
    this.error,
    this.image,
    this.thumbnail,
  });
  final String id, packId, name;
  final int ordinal, width, height, version;
  final String? error;
  final MediaSource? image, thumbnail;
  bool get readable => error == null && image != null;
}

class PackManifest {
  PackManifest({
    required Iterable<ReaderPage> pages,
    required this.packId,
    required this.version,
    required this.total,
    required this.offset,
    required this.limit,
  }) : pages = List.unmodifiable(pages);
  final List<ReaderPage> pages;
  final String packId;
  final int version, total, offset, limit;
}

class ReaderMark {
  const ReaderMark(this.pageId, {this.offsetRatio = 0, this.completed = false});
  final String pageId;
  final double offsetRatio;
  final bool completed;
}

/// Ownership required for writes; never derive this from an unrelated draft.
class ReaderCursor {
  const ReaderCursor({
    required this.sessionId,
    required this.sessionRevision,
    required this.packId,
    required this.version,
    required this.progressRevision,
  });
  final String sessionId, packId;
  final int sessionRevision, version, progressRevision;
}

class ReaderState {
  const ReaderState({
    required this.page,
    required this.pageIndex,
    required this.mark,
    required this.revision,
    required this.version,
    required this.preferences,
    this.recoveryReason,
    this.sessionRevision,
  });
  final ReaderPage page;
  final int pageIndex, revision, version;
  final int? sessionRevision;
  final ReaderMark mark;
  final String? recoveryReason;
  final ReaderPreferences preferences;
}

class ReaderNeighbor {
  const ReaderNeighbor(this.packId, this.ordinal);
  final String packId;
  final int ordinal;
}

class PackReadingRange {
  const PackReadingRange({
    required this.id,
    required this.revision,
    required this.candidateCount,
    required this.availableCount,
    required this.cursor,
    required this.finished,
    required this.pack,
    required this.resume,
    required this.source,
    required this.random,
    this.previous,
    this.next,
  });
  final String id;
  final int revision, candidateCount, availableCount;
  final int? cursor;
  final bool finished, random;
  final LibraryPack? pack;
  final ReaderState? resume;
  final BrowseSource source;
  final ReaderNeighbor? previous, next;
  ReaderCursor? get ownership => finished || pack == null || resume == null
      ? null
      : ReaderCursor(
          sessionId: id,
          sessionRevision: revision,
          packId: pack!.id,
          version: pack!.contentVersion,
          progressRevision: resume!.revision,
        );
}

class ReaderQueueEntry {
  const ReaderQueueEntry(this.ordinal, this.pack, {required this.available});
  final int ordinal;
  final LibraryPack pack;
  final bool available;
}

class ReaderQueuePage {
  ReaderQueuePage({
    required Iterable<ReaderQueueEntry> entries,
    required this.total,
    required this.offset,
    required this.limit,
    required this.revision,
  }) : entries = List.unmodifiable(entries);
  final List<ReaderQueueEntry> entries;
  final int total, offset, limit, revision;
}

/// Commands are immutable so an uncertain write can be queried/retried exactly.
sealed class ReaderCommand<T> {
  const ReaderCommand(this.requestId);
  final String requestId;
  String get kind;
}

class CreatePackReading extends ReaderCommand<PackReadingRange> {
  const CreatePackReading(super.requestId, this.entry);
  final PackReadingEntry entry;
  @override
  String get kind => 'session';
}

class MovePackReading extends ReaderCommand<PackReadingRange> {
  const MovePackReading(
    super.requestId, {
    required this.sessionId,
    required this.revision,
    this.packId,
    this.finish = false,
  });
  final String sessionId;
  final int revision;
  final String? packId;
  final bool finish;
  @override
  String get kind => 'position';
}

class OpenPackReading extends ReaderCommand<ReaderState> {
  const OpenPackReading(super.requestId, this.cursor, this.pageId);
  final ReaderCursor cursor;
  final String pageId;
  @override
  String get kind => 'opened';
}

class WritePackProgress extends ReaderCommand<ReaderState> {
  const WritePackProgress(super.requestId, this.cursor, this.mark);
  final ReaderCursor cursor;
  final ReaderMark mark;
  @override
  String get kind => 'progress';
}

class WritePackPreferences extends ReaderCommand<ReaderPreferences> {
  const WritePackPreferences(super.requestId, this.cursor, this.preferences);
  final ReaderCursor cursor;
  final ReaderPreferences preferences;
  @override
  String get kind => 'preferences';
}

class WriteReaderDefaults extends ReaderCommand<ReaderPreferences> {
  const WriteReaderDefaults(super.requestId, this.preferences);
  final ReaderPreferences preferences;
  @override
  String get kind => 'defaults';
}

/// One connection-bound handle. Metadata, page and queue reads cancel separately;
/// submit never retries. receipt is read-only and returns null only for unknown IDs.
abstract class PackReader {
  bool get isCurrent;
  Future<T> submit<T>(ReaderCommand<T> command);
  Future<T?> receipt<T>(ReaderCommand<T> command);
  Future<PackReadingRange> read(String sessionId);
  Future<PackManifest> pages(
    String packId, {
    required int version,
    int offset = 0,
    int limit = 40,
  });
  Future<ReaderQueuePage> queue(
    String sessionId, {
    int offset = 0,
    int limit = 40,
  });
  Future<ReaderPreferences> defaults();
  void cancelMetadata();
  void cancelPages();
  void cancelQueue();
  void dispose();
}
