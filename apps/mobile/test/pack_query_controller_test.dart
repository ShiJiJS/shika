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

CatalogPage<LibraryPack> page(int offset, int count, {int total = 50}) =>
    CatalogPage(
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

  test('a recent pack source cannot fall back to the whole catalog before its protocol exists', () async {
    await controller.load(PackBrowseContext(source: BrowseSource.recent));
    expect(repo.reads, isEmpty);
    expect(controller.state.error, contains('最近图包'));
    expect(controller.state.items, isEmpty);
  });
}
