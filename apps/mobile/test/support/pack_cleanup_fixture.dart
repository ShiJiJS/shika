import 'dart:async';

import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';

import '../pack_reader_widget_test.dart' show AssetReadingLibrary;

typedef Json = Map<String, dynamic>;

class CleanupReaderLibrary extends AssetReadingLibrary {
  CleanupReaderLibrary({this.count = 3});
  final int count;
  Object owner = Object();
  @override
  Object get connectionIdentity => owner;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    'image_packs',
    'pack_tags',
    'pack_reading_sessions',
    'pack_logical_trash',
    'pack_reader_cleanup',
  ]);
  final journal = PackFileJournal(MemoryFileCommandStore());
  final unavailable = <String>{};
  final writes = <ReaderCommand>[];
  final filePosts = <Json>[], fileReads = <String>[];
  final receipts = <String, Json>{};
  final deleted = <String, ({String pack, int cursor, int revision})>{};
  String identity = '';
  PackReadingEntry? lastEntry;
  int cursor = 0, revision = 0;
  bool finished = false,
      loseBefore = false,
      loseAfter = false,
      failMetadata = false,
      undoRestores = true;
  Completer<void>? fileStarted, fileRelease;
  String get selected {
    final after = [
      for (var i = cursor; i < count; i++)
        if (!unavailable.contains('p$i')) 'p$i',
    ];
    if (after.isNotEmpty) return after.first;
    return [
      for (var i = 0; i < cursor; i++)
        if (!unavailable.contains('p$i')) 'p$i',
    ].last;
  }

  LibraryPack pack(String id) => LibraryPack(
    id: id,
    rootId: 'root',
    path: '/packs/$id',
    name: '阅读图包$id',
    pageCount: 3,
    readableCount: 3,
    contentVersion: 1,
    status: 'available',
    createdAt: 1,
  );
  ReaderPage page(String id, int index) => ReaderPage(
    id: '$id-$index',
    packId: id,
    name: '${index + 1}.jpg',
    ordinal: index,
    width: 400,
    height: 600,
    version: 1,
    image: const MediaSource('assets/media/flower-portrait.jpg', asset: true),
    thumbnail: const MediaSource(
      'assets/media/flower-portrait.jpg',
      asset: true,
    ),
  );
  ReaderState state(String id) {
    final mark = marks[id] ?? ReaderMark('$id-0');
    final i = int.parse(mark.pageId.split('-').last);
    return ReaderState(
      page: page(id, i),
      pageIndex: i,
      mark: mark,
      revision: revisions[id] ?? 0,
      version: 1,
      preferences: prefs[id] ?? const ReaderPreferences(),
      sessionRevision: revision,
    );
  }

  PackReadingRange get range {
    final available = count - unavailable.length;
    final id = available > 0 ? selected : null;
    final at = id == null ? null : int.parse(id.substring(1));
    return PackReadingRange(
      id: identity,
      revision: revision,
      candidateCount: count,
      availableCount: available,
      cursor: at,
      finished: finished || available == 0,
      pack: id == null ? null : pack(id),
      resume: id == null ? null : state(id),
      source: lastEntry?.source ?? BrowseSource.library,
      random: lastEntry?.random ?? false,
      previous: at == null || at == 0
          ? null
          : ReaderNeighbor('p${at - 1}', at - 1),
      next: at == null || at == count - 1
          ? null
          : ReaderNeighbor('p${at + 1}', at + 1),
    );
  }

  @override
  PackReader createPackReader() => CleanupReader(this, owner);
  @override
  PackFiles createPackFiles() {
    final token = owner;
    return PackFiles(
      journal: journal,
      scope: 'fixture',
      isCurrent: () => identical(token, owner),
      pollDelay: Duration.zero,
      call: (method, path, {body}) async {
        if (method == 'GET') {
          fileReads.add(path);
          final value = receipts[path.split('/').last];
          if (value == null) {
            throw const ApiFailure('未找到原请求', code: 'not_found', status: 404);
          }
          return {...value, 'server_time': 1000.0};
        }
        final payload = Map<String, dynamic>.from(body!);
        filePosts.add({'path': path, ...payload});
        fileStarted?.complete();
        await fileRelease?.future;
        if (loseBefore) {
          loseBefore = false;
          throw const ApiFailure('结果尚未确认', code: 'response_lost', status: 503);
        }
        final key = payload['request_id'] as String;
        if (receipts.containsKey(key)) return receipts[key]!;
        final taskId = 'op-$key';
        late String id;
        late String kind;
        Json? transition;
        var restored = false;
        if (path == '/api/v1/packs/trash') {
          kind = 'trash';
          id = (payload['pack_ids'] as List).single;
          final scene = payload['reading'] as Map;
          if (scene['session_id'] != identity ||
              scene['expected_session_revision'] != revision ||
              scene['expected_progress_revision'] != revisions[id]) {
            throw const ApiFailure('阅读已变化', code: 'pack_changed', status: 409);
          }
          deleted[taskId] = (pack: id, cursor: cursor, revision: revision);
          unavailable.add(id);
          revision++;
          if (scene['advance'] != false) {
            final next = [
              for (var i = cursor + 1; i < count; i++)
                if (!unavailable.contains('p$i')) i,
            ];
            if (next.isEmpty) {
              finished = true;
            } else {
              cursor = next.first;
            }
            transition = {
              'session_id': identity,
              'revision': revision,
              'cursor': cursor,
              'pack_id': finished ? null : selected,
              'finished': finished,
            };
          }
        } else {
          kind = 'undo';
          final old = deleted[Uri.decodeComponent(path.split('/')[4])]!;
          id = old.pack;
          unavailable.remove(id);
          restored = undoRestores;
          if (restored) {
            cursor = old.cursor;
            finished = false;
            revision++;
          }
        }
        final task = {
          'id': taskId,
          'kind': 'pack_$kind',
          'status': 'completed',
          'error': null,
          'server_time': 1000.0,
          'result': {
            'operation_id': taskId,
            'total': 1,
            'processed': 1,
            'succeeded': 1,
            'failed': 0,
            'partial': false,
            'items': [
              {
                'requested_id': kind == 'trash' ? id : 'trash-$id',
                'pack_id': id,
                'trash_id': 'trash-$id',
                'outcome': 'succeeded',
                'phase': 'committed',
                'error': null,
              },
            ],
            'reading_transition': transition,
            'reading_restored': restored,
            'undo_expires_at': kind == 'trash' ? 1008.0 : null,
          },
        };
        receipts[key] = task;
        if (loseAfter) {
          loseAfter = false;
          throw const ApiFailure('结果尚未确认', code: 'response_lost', status: 503);
        }
        return task;
      },
    );
  }
}

class CleanupReader implements PackReader {
  CleanupReader(this.repo, this.owner);
  final CleanupReaderLibrary repo;
  final Object owner;
  bool alive = true;
  @override
  bool get isCurrent => alive && identical(owner, repo.owner);
  @override
  Future<T> submit<T>(ReaderCommand<T> command) async {
    repo.writes.add(command);
    late Object result;
    switch (command) {
      case final CreatePackReading value:
        repo.lastEntry = value.entry;
        repo.identity = 'reading-${repo.scopes++}';
        repo.cursor = int.parse((value.entry.anchorId ?? 'p0').substring(1));
        repo.revision = 0;
        repo.finished = false;
        result = repo.range;
      case final OpenPackReading value:
        repo.openedCount++;
        final id = value.cursor.packId;
        repo.marks.putIfAbsent(id, () => ReaderMark(value.pageId));
        repo.revisions[id] = (repo.revisions[id] ?? 0) + 1;
        repo.prefs.putIfAbsent(
          id,
          () => const ReaderPreferences(overridden: true),
        );
        result = repo.state(id);
      case final WritePackProgress value:
        final id = value.cursor.packId;
        repo.marks[id] = value.mark;
        repo.revisions[id] = (repo.revisions[id] ?? 0) + 1;
        result = repo.state(id);
      case final WritePackPreferences value:
        final p = value.preferences;
        repo.prefs[value.cursor.packId] = ReaderPreferences(
          mode: p.mode,
          direction: p.direction,
          gap: p.gap,
          fit: p.fit,
          revision: p.revision + 1,
          overridden: true,
        );
        result = repo.prefs[value.cursor.packId]!;
      case final MovePackReading value:
        repo.cursor = int.parse(value.packId!.substring(1));
        repo.revision++;
        result = repo.range;
      case WriteReaderDefaults():
        throw UnimplementedError();
    }
    return result as T;
  }

  @override
  Future<T?> receipt<T>(ReaderCommand<T> command) async => null;
  @override
  Future<PackReadingRange> read(String sessionId) async {
    if (repo.failMetadata) throw const LibraryFailure('下一包尚未读取，请查询原结果');
    return repo.range;
  }

  @override
  Future<PackManifest> pages(
    String packId, {
    required int version,
    int offset = 0,
    int limit = 40,
  }) async => PackManifest(
    pages: [
      for (var i = offset; i < 3 && i < offset + limit; i++)
        repo.page(packId, i),
    ],
    packId: packId,
    version: 1,
    total: 3,
    offset: offset,
    limit: limit,
  );
  @override
  Future<ReaderQueuePage> queue(
    String sessionId, {
    int offset = 0,
    int limit = 40,
  }) async => ReaderQueuePage(
    entries: [
      for (var i = offset; i < repo.count && i < offset + limit; i++)
        ReaderQueueEntry(
          i,
          repo.pack('p$i'),
          available: !repo.unavailable.contains('p$i'),
        ),
    ],
    total: repo.count,
    offset: offset,
    limit: limit,
    revision: repo.revision,
  );
  @override
  Future<ReaderPreferences> defaults() async => const ReaderPreferences();
  @override
  void cancelMetadata() {}
  @override
  void cancelPages() {}
  @override
  void cancelQueue() {}
  @override
  void dispose() {
    alive = false;
  }
}
