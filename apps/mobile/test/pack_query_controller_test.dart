import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/library/browse_context.dart';
import 'package:video_viewer/features/library/pack_query_controller.dart';
import 'package:video_viewer/library/demo_repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/state_store.dart';

class DelayedPacks extends DemoLibraryRepository {
  DelayedPacks() : super(MemoryStateStore(), latency: Duration.zero);
  Object identity = Object();
  @override
  Object get connectionIdentity => identity;
  final reads =
      <
        ({
          PackQuery query,
          int offset,
          Completer<CatalogPage<LibraryPack>> result,
        })
      >[];
  final locations =
      <
        ({
          PackQuery query,
          List<String> anchors,
          int fallback,
          Completer<CatalogPage<LibraryPack>> result,
        })
      >[];
  @override
  Future<CatalogPage<LibraryPack>> restorePackEntry(
    PackQuery query, {
    required List<String> anchors,
    required int fallbackIndex,
    int limit = 24,
  }) {
    final result = Completer<CatalogPage<LibraryPack>>();
    locations.add((
      query: query,
      anchors: [...anchors],
      fallback: fallbackIndex,
      result: result,
    ));
    return result.future;
  }

  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) {
    final result = Completer<CatalogPage<LibraryPack>>();
    reads.add((query: query, offset: offset, result: result));
    return result.future;
  }

  void switchConnection() {
    identity = Object();
    notifyListeners();
  }
}

CatalogPage<LibraryPack> page(
  int offset,
  int count, {
  int total = 50,
  int? anchor,
}) => CatalogPage(
  items: [
    for (var i = offset; i < offset + count; i++)
      LibraryPack(
        id: 'p$i',
        rootId: 'r',
        path: '/packs/$i',
        name: '图包$i',
        pageCount: 500,
        readableCount: 500,
        contentVersion: 1,
        status: 'available',
        createdAt: 0,
      ),
  ],
  total: total,
  offset: offset,
  limit: 24,
  anchorIndex: anchor,
);
void main() {
  late DelayedPacks repo;
  late PackQueryController controller;
  setUp(() async {
    repo = DelayedPacks();
    await repo.initialize();
    controller = PackQueryController(repo);
  });
  tearDown(() {
    controller.dispose();
    repo.dispose();
  });

  test('pagination failure preserves whole-pack cards and retries the same page, without changing video playback', () async {
    final videoIdentity = repo.playbackIdentity;
    final context = PackBrowseContext(
      query: PackQuery(search: '合集', tags: {'pack-tag'}),
    );
    final first = controller.load(context);
    repo.reads.last.result.complete(page(0, 24));
    await first;
    expect(controller.state.total, 50);
    expect(controller.state.items, hasLength(24));
    final next = controller.load(context, more: true);
    await controller.load(context, more: true);
    expect(repo.reads, hasLength(2));
    repo.reads.last.result.completeError(const LibraryFailure('离线'));
    await next;
    expect(controller.state.items, hasLength(24));
    expect(controller.state.loading, isFalse);
    expect(controller.state.error, contains('离线'));
    expect(controller.state.retryMore, isTrue);
    final retry = controller.load(context, more: true);
    expect(repo.reads.last.offset, 24);
    repo.reads.last.result.complete(page(24, 24));
    await retry;
    final last = controller.load(context, more: true);
    expect(repo.reads.last.offset, 48);
    repo.reads.last.result.complete(page(48, 2));
    await last;
    expect(controller.state.items, hasLength(50));
    expect(controller.state.hasMore, isFalse);
    await controller.load(context, more: true);
    expect(repo.reads, hasLength(4));
    expect(repo.playbackIdentity, videoIdentity);
    expect(repo.snapshot.recentVideos, isEmpty);
  });

  test('a failed refresh keeps its refresh intent instead of appending another page on retry', () async {
    final context = PackBrowseContext();
    final first = controller.load(context);
    repo.reads.last.result.complete(page(0, 24));
    await first;
    final refresh = controller.load(context);
    repo.reads.last.result.completeError(const LibraryFailure('暂时离线'));
    await refresh;
    expect(controller.state.items, hasLength(24));
    expect(controller.state.retryMore, isFalse);
    final retry = controller.load(context, more: controller.state.retryMore);
    expect(repo.reads.last.offset, 0);
    repo.reads.last.result.complete(page(0, 24));
    await retry;
    expect(controller.state.items, hasLength(24));
    expect(controller.state.error, isEmpty);
  });

  test('new pack query wins over late results; source and filters belong to its own context', () async {
    final old = controller.load(
      PackBrowseContext(
        query: PackQuery(search: '旧', tags: {'old'}),
      ),
    );
    final current = controller.load(
      PackBrowseContext(
        query: PackQuery(search: '新', readState: PackReadState.unread),
        source: BrowseSource.tags,
      ),
    );
    repo.reads.last.result.complete(page(0, 1, total: 1));
    await current;
    repo.reads.first.result.complete(page(0, 24));
    await old;
    expect(controller.state.items, hasLength(1));
    expect(controller.state.context.query.search, '新');
    expect(controller.state.context.query.tags, isEmpty);
    expect(controller.state.context.source, BrowseSource.tags);
  });

  test('leaving cancels loading but retains cards; changing connection clears cards and rejects old receipts', () async {
    final context = PackBrowseContext();
    final first = controller.load(context);
    repo.reads.last.result.complete(page(0, 24));
    await first;
    final next = controller.load(context, more: true);
    controller.cancel();
    expect(controller.state.items, hasLength(24));
    expect(controller.state.loading, isFalse);
    repo.reads.last.result.complete(page(24, 24));
    await next;
    expect(controller.state.items, hasLength(24));
    final pending = controller.load(context);
    repo.switchConnection();
    expect(controller.state.items, isEmpty);
    expect(controller.state.total, 0);
    repo.reads.last.result.complete(page(0, 24));
    await pending;
    expect(controller.state.items, isEmpty);
  });

  test('an unexpected append offset or empty incomplete page cannot silently corrupt the list', () async {
    final context = PackBrowseContext();
    final first = controller.load(context);
    repo.reads.last.result.complete(page(0, 24));
    await first;
    final wrong = controller.load(context, more: true);
    repo.reads.last.result.complete(page(0, 24));
    await wrong;
    expect(controller.state.items, hasLength(24));
    expect(controller.state.error, contains('已变化'));
    final empty = controller.load(context, more: true);
    repo.reads.last.result.complete(page(24, 0));
    await empty;
    expect(controller.state.items, hasLength(24));
    expect(controller.state.error, contains('已变化'));
  });

  test('localized restore and prepend keep complete scope and authoritative offsets', () async {
    final context = PackBrowseContext(
      query: PackQuery(search: '包', tags: {'a', 'b'}),
      source: BrowseSource.tags,
      scrollIndex: 58,
    );
    final restoring = controller.restore(context, anchors: ['p58', 'p59']);
    expect(repo.locations.last.fallback, 58);
    expect(repo.locations.last.anchors, ['p58', 'p59']);
    expect(repo.locations.last.query.tags, {'a', 'b'});
    repo.locations.last.result.complete(page(48, 24, total: 73, anchor: 58));
    await restoring;
    expect(controller.state.offset, 48);
    expect(controller.state.items.length, 24);
    expect(controller.state.anchorIndex, 58);
    expect(controller.state.hasBefore, isTrue);
    final before = controller.load(context, before: true);
    expect(repo.reads.last.offset, 24);
    repo.reads.last.result.complete(page(24, 24, total: 73));
    await before;
    expect(controller.state.offset, 24);
    expect(controller.state.items.length, 48);
    expect(controller.state.items.last.id, 'p71');
  });

  test('restore failure retains old deep cards and repeats location instead of appending', () async {
    final context = PackBrowseContext(scrollIndex: 58);
    final initial = controller.load(context);
    repo.reads.last.result.complete(page(0, 24, total: 73));
    await initial;
    for (final offset in [24, 48]) {
      final next = controller.load(context, more: true);
      repo.reads.last.result.complete(page(offset, 24, total: 73));
      await next;
    }
    final location = controller.restore(context, anchors: ['p58', 'p59']);
    repo.locations.last.result.completeError(const LibraryFailure('定位离线'));
    await location;
    expect(controller.state.items.length, 72);
    expect(controller.state.offset, 0);
    expect(controller.state.retryRestore, isTrue);
    expect(controller.state.retryMore, isFalse);
    final retry = controller.restore(context, anchors: ['p58', 'p59']);
    expect(repo.locations.last.fallback, 58);
    repo.locations.last.result.complete(page(48, 24, total: 73, anchor: 59));
    await retry;
    expect(controller.state.items.length, 24);
    expect(controller.state.offset, 48);
    expect(controller.state.anchorIndex, 59);
    expect(controller.state.error, isEmpty);
  });

  test('long browsing stays within five pages and can prepend discarded earlier items', () async {
    final context = PackBrowseContext();
    for (var offset = 0; offset <= 120; offset += 24) {
      final reading = controller.load(context, more: offset > 0);
      expect(repo.reads.last.offset, offset);
      repo.reads.last.result.complete(page(offset, 24, total: 200));
      await reading;
      expect(controller.state.items.length, lessThanOrEqualTo(120));
    }
    expect(controller.state.offset, 24);
    expect(controller.state.items.first.id, 'p24');
    final before = controller.load(context, before: true);
    repo.reads.last.result.complete(page(0, 24, total: 200));
    await before;
    expect(controller.state.offset, 0);
    expect(controller.state.items.length, 120);
    expect(controller.state.items.last.id, 'p119');
  });

  test('changed membership while paging retains old rows and requires stable relocation', () async {
    final context = PackBrowseContext();
    final first = controller.load(context);
    repo.reads.last.result.complete(page(0, 24, total: 73));
    await first;
    final more = controller.load(context, more: true);
    repo.reads.last.result.complete(page(24, 24, total: 74));
    await more;
    expect(controller.state.items.length, 24);
    expect(controller.state.total, 73);
    expect(controller.state.retryRestore, isTrue);
    expect(controller.state.error, contains('已变化'));
  });

  test(
    'late location cannot overwrite a new query or a replaced connection',
    () async {
      final old = controller.restore(
        PackBrowseContext(query: PackQuery(search: '旧')),
        anchors: ['p58'],
      );
      final current = controller.load(
        PackBrowseContext(query: PackQuery(search: '新')),
      );
      repo.reads.last.result.complete(page(0, 1, total: 1));
      await current;
      repo.locations.last.result.complete(page(48, 24, total: 73, anchor: 58));
      await old;
      expect(controller.state.context.query.search, '新');
      expect(controller.state.items.length, 1);
      final pending = controller.restore(
        PackBrowseContext(scrollIndex: 58),
        anchors: ['p58'],
      );
      repo.switchConnection();
      repo.locations.last.result.complete(page(48, 24, total: 73, anchor: 58));
      await pending;
      expect(controller.state.items, isEmpty);
    },
  );

  test('a recent pack source cannot fall back to the whole catalog before its protocol exists', () async {
    await controller.load(PackBrowseContext(source: BrowseSource.recent));
    expect(repo.reads, isEmpty);
    expect(controller.state.error, contains('最近图包'));
    expect(controller.state.items, isEmpty);
  });
}
