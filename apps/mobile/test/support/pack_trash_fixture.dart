import 'dart:async';

import 'package:video_viewer/library/file_command_store.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/server_api.dart';

import '../media_workspace_widget_test.dart' show WorkspaceLibrary;
import '../pack_files_test.dart' show FilesFixture;

class TrashLibrary extends WorkspaceLibrary {
  TrashLibrary({int count = 27}) {
    for (var i = 0; i < count; i++) {
      final id = 'trash-$i';
      records[id] = PackTrashItem(
        id: id,
        operationId: 'original-$i',
        originalPath: '/packs/图包$i',
        deletedAt: i.toDouble(),
        pageCount: 3,
        pack: LibraryPack(
          id: 'p$i',
          rootId: 'root',
          path: '/packs/图包$i',
          name: '图包$i',
          pageCount: 3,
          readableCount: 3,
          contentVersion: 1,
          status: 'trash',
          createdAt: 0,
          tags: {'保留'},
          progress: PackProgress(
            pageId: 'page-$i',
            pageIndex: 1,
            offsetRatio: .37,
            completed: false,
            revision: 4,
            updatedAt: 1,
          ),
        ),
      );
    }
  }
  final records = <String, PackTrashItem>{};
  Object owner = Object();
  @override
  Object get connectionIdentity => owner;
  @override
  ServiceCapabilities get capabilities =>
      ServiceCapabilities(['image_packs', 'pack_tags', 'pack_logical_trash']);
  final commandStore = MemoryFileCommandStore();
  late final journal = PackFileJournal(commandStore);
  final posts = <Map<String, dynamic>>[], calls = <String>[];
  final receipts = <String, Map<String, dynamic>>{};
  final pageQueries = <({String search, int offset})>[];
  final pageGates = <String, Completer<void>>{};
  Completer<Set<String>>? selectionGate;
  Completer<void>? fileStarted, fileRelease;
  bool loseBefore = false, loseAfter = false, failPage = false;
  final failing = <String>{};
  @override
  PackTrashCatalog createPackTrash() => TrashCatalog(this);
  @override
  PackFiles createPackFiles() {
    final identity = owner;
    return PackFiles(
      journal: journal,
      scope: 'trash-fixture',
      isCurrent: () => identical(identity, owner),
      call: (method, path, {body}) async {
        calls.add('$method $path');
        if (method == 'GET') {
          final result = receipts[path.split('/').last];
          if (result == null) {
            throw const ApiFailure(
              'Unknown',
              code: 'pack_operation_not_found',
              status: 404,
            );
          }
          return result;
        }
        posts.add(body!);
        if (fileStarted != null && !fileStarted!.isCompleted) {
          fileStarted!.complete();
        }
        if (fileRelease != null) await fileRelease!.future;
        if (loseBefore) {
          loseBefore = false;
          throw const ApiFailure('未确认', code: 'reply_lost', status: 503);
        }
        final ids = List<String>.from(body['trash_ids']);
        final nonce = body['request_id'] as String;
        final result = FilesFixture().task('op-$nonce', 'restore', ids);
        final raw = result['result'] as Map;
        for (final item in raw['items'] as List) {
          final id = item['requested_id'] as String;
          if (failing.contains(id)) {
            item['outcome'] = 'failed';
            item['error'] = 'stale_pack_state';
          } else {
            records.remove(id);
          }
        }
        raw['failed'] = ids.where(failing.contains).length;
        raw['succeeded'] = ids.length - (raw['failed'] as int);
        raw['partial'] = raw['failed'] > 0 && raw['succeeded'] > 0;
        if (raw['succeeded'] == 0) result['status'] = 'failed';
        receipts[nonce] = result;
        receipts['op-$nonce'] = result;
        if (loseAfter) {
          loseAfter = false;
          throw const ApiFailure('未确认', code: 'reply_lost', status: 503);
        }
        return result;
      },
    );
  }

  void replaceConnection() {
    owner = Object();
    notifyListeners();
  }
}

class TrashCatalog implements PackTrashCatalog {
  TrashCatalog(this.repo) : owner = repo.owner;
  final TrashLibrary repo;
  final Object owner;
  bool disposed = false;
  int pageCancels = 0, selectionCancels = 0;
  @override
  bool get isCurrent => !disposed && identical(owner, repo.owner);
  List<PackTrashItem> matching(String search) => repo.records.values
      .where(
        (v) => v.pack.name.contains(search) || v.originalPath.contains(search),
      )
      .toList();
  @override
  Future<CatalogPage<PackTrashItem>> page({
    String search = '',
    int offset = 0,
    int limit = 24,
  }) async {
    repo.pageQueries.add((search: search, offset: offset));
    final items = matching(search);
    if (repo.pageGates[search] case final Completer<void> gate) {
      await gate.future;
    }
    if (repo.failPage) throw const LibraryFailure('目录暂不可用');
    return CatalogPage(
      items: items.skip(offset).take(limit),
      total: items.length,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<Set<String>> select(String search) async =>
      repo.selectionGate?.future ?? matching(search).map((v) => v.id).toSet();
  @override
  void cancelPages() {
    pageCancels++;
  }

  @override
  void cancelSelection() {
    selectionCancels++;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
