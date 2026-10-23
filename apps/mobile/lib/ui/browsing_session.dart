import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../library/models.dart';
import '../library/repository.dart';

/// Visible selection is independent of decoder readiness and network receipts.
/// Only metadata is buffered; the player still owns at most three decoders.
class BrowsingSession extends ChangeNotifier {
  BrowsingSession(this.repository, {this.recordOpens = false}) {
    repository.addListener(_changed);
    _changed();
  }
  final LibraryRepository repository;
  final bool recordOpens;
  bool _visible = false;
  String? _lastOpened, _opening;
  int _openRevision = 0;

  /// Only a mounted viewing route enables history, never list/queue prefetch.
  void setVisible(bool visible) {
    _visible = visible;
    if (visible) _recordOpen();
  }

  void _recordOpen() {
    final id = _selected;
    if (_closed ||
        !_visible ||
        !recordOpens ||
        !repository.fixedPreview ||
        id == null ||
        repository.current?.id != id) {
      return;
    }
    final key =
        '${identityHashCode(repository.connectionIdentity)}:${repository.playbackIdentity}:$id';
    if (_lastOpened == key || _opening == key) return;
    _opening = key;
    final revision = ++_openRevision;
    unawaited(() async {
      try {
        await repository.recordVideoOpened(id);
        if (!_closed && revision == _openRevision) _lastOpened = key;
      } on RequestCancelled {
        // A later selection owns its own visible-open acknowledgement.
      } catch (_) {
        if (!_closed && _visible && revision == _openRevision) {
          message = '最近记录暂未同步，可继续观看';
          _emit();
        }
      } finally {
        if (_opening == key) _opening = null;
      }
    }());
  }

  final Map<int, String> _entries = {};
  final Map<String, LibraryVideo> _videos = {};
  final Set<String> _hidden = {};
  final Set<String> _confirmed = {};
  String? _lastReceipt;
  Future<void> _work = Future.value();
  String? _selected;
  String _identity = '';
  int _epoch = 0, _selection = 0, _fileChanges = 0, _moves = 0;
  bool _closed = false, _fetching = false;
  String? message;
  bool get deleting => _fileChanges > 0;
  int get position =>
      _entries.entries.where((e) => e.value == _selected).firstOrNull?.key ??
      repository.playbackPosition;

  List<String> get _ids {
    final keys = _entries.keys.toList()..sort();
    return keys
        .map((k) => _entries[k]!)
        .where((id) => !_hidden.contains(id) && !_confirmed.contains(id))
        .toSet()
        .toList();
  }

  LibrarySnapshot get snapshot {
    final source = repository.snapshot, ids = _ids;
    return source.copy(
      videos: {
        ...{for (final v in source.videos) v.id: v},
        ..._videos,
      }.values,
      round: ids,
      position: max(0, ids.indexOf(_selected ?? '')),
    );
  }

  LibraryVideo? get current {
    final state = snapshot;
    return state.round.isEmpty ? null : _videos[state.round[state.position]];
  }

  void _emit() {
    if (!_closed) notifyListeners();
  }

  void _changed() {
    if (_closed) return;
    final state = repository.snapshot;
    final identity =
        '${state.connected}-${state.address}:${state.port}-${repository.playbackSequenceIdentity}';
    if (_identity != identity) {
      _identity = identity;
      _epoch++;
      _entries.clear();
      _videos.clear();
      _selected = null;
      _confirmed.clear();
      _fetching = false;
    }
    for (final video in state.videos) {
      _videos[video.id] = video;
      if (video.status == VideoStatus.available) _confirmed.remove(video.id);
    }
    final receipt = state.lastDelete;
    if (receipt != null && receipt.id != _lastReceipt) {
      _lastReceipt = receipt.id;
      _confirmed.addAll(receipt.ids);
    }
    if (repository.playbackTotal == 0 && _fileChanges == 0) {
      _entries.clear();
      _selected = null;
    }
    // File tasks may shift ordinal positions. Keep the visible buffer stable
    // until the receipt is known, rather than moving it back to the old cursor.
    if (_fileChanges == 0 || _entries.isEmpty) {
      final start = repository.playbackPosition - state.position;
      for (var i = 0; i < state.round.length; i++) {
        _entries[start + i] = state.round[i];
      }
    }
    if (_moves == 0 && _fileChanges == 0) _selected = repository.current?.id;
    _selected ??= repository.current?.id;
    _emit();
    _recordOpen();
    if (state.connected && repository.libraryPreparation.value.ready) {
      unawaited(_prefetch());
    }
  }

  Future<void> _prefetch({bool force = false}) async {
    if (_closed || _fetching || _fileChanges > 0 || _entries.isEmpty) return;
    final position =
        _entries.entries.where((e) => e.value == _selected).firstOrNull?.key ??
        repository.playbackPosition;
    final offset = max(0, position - 8);
    final end = min(repository.playbackTotal, offset + 48);
    if (!force &&
        [for (var i = max(0, position - 3); i < min(end, position + 16); i++) i]
            .every(_entries.containsKey)) {
      return;
    }
    final epoch = _epoch;
    _fetching = true;
    try {
      final page = await repository.loadPlaybackVideos(
        offset: offset,
        limit: 48,
      );
      if (_closed || epoch != _epoch || _fileChanges > 0) return;
      for (var i = 0; i < page.items.length; i++) {
        final video = page.items[i];
        _entries[page.offset + i] = video.id;
        _videos[video.id] = video;
      }
      // Keep a bounded metadata window around the visible item.
      _entries.removeWhere(
        (key, value) => key < position - 48 || key > position + 96,
      );
      final retained = _entries.values.toSet();
      _videos.removeWhere((key, value) => !retained.contains(key));
      _emit();
    } on RequestCancelled {
      // A changed scope/session owns its own prefetch.
    } catch (_) {
      // Poster/list prefetch is optional; it must never disable navigation.
    } finally {
      if (epoch == _epoch) _fetching = false;
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _work.then((_) => action());
    _work = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  Future<void> changeOrder(PlayOrder order, {bool restart = false}) {
    final connection = repository.connectionIdentity;
    final identity = repository.playbackIdentity;
    return _enqueue(() async {
      if (_closed ||
          !identical(connection, repository.connectionIdentity) ||
          identity != repository.playbackIdentity) {
        throw const RequestCancelled();
      }
      await repository.changePreviewOrder(order, restart: restart);
    });
  }

  Future<void> choose(String id) {
    final connection = repository.connectionIdentity;
    final identity = repository.playbackIdentity;
    ++_selection;
    _moves++;
    return _enqueue(() async {
      try {
        if (_closed ||
            !identical(connection, repository.connectionIdentity) ||
            identity != repository.playbackIdentity) {
          throw const RequestCancelled();
        }
        await repository.moveToVideo(id);
      } finally {
        _moves--;
        if (!_closed && identical(connection, repository.connectionIdentity)) {
          followRepository();
        }
      }
    });
  }

  Future<void> finish() {
    final connection = repository.connectionIdentity;
    final identity = repository.playbackIdentity;
    return _enqueue(() async {
      if (_closed ||
          !identical(connection, repository.connectionIdentity) ||
          identity != repository.playbackIdentity) {
        throw const RequestCancelled();
      }
      await repository.finishPreview();
    });
  }

  bool step(int delta) {
    final ids = _ids, index = ids.indexOf(_selected ?? '') + delta;
    if (index < 0 || index >= ids.length) {
      unawaited(_prefetch(force: true));
      return false;
    }
    _selected = ids[index];
    final id = _selected!, epoch = _epoch, selection = ++_selection;
    _moves++;
    _emit();
    unawaited(_prefetch());
    unawaited(
      _enqueue(() async {
        try {
          if (_closed ||
              epoch != _epoch ||
              selection != _selection ||
              _hidden.contains(id)) {
            return;
          }
          await repository.moveToVideo(id);
          if (!_closed && epoch == _epoch && selection == _selection) {
            _recordOpen();
          }
        } on RequestCancelled {
          return;
        } catch (_) {
          if (!_closed && epoch == _epoch && selection == _selection) {
            message = '播放位置暂未同步，可继续浏览';
            _emit();
          }
        } finally {
          _moves--;
        }
      }),
    );
    return true;
  }

  Future<void> delete(Set<String> requested, String requestId) {
    final ids = requested.difference(_hidden), before = _ids;
    if (ids.isEmpty) return Future.value();
    final oldIndex = max(0, before.indexOf(_selected ?? ''));
    final previousReceipt = repository.snapshot.lastDelete?.id;
    _hidden.addAll(ids);
    _fileChanges++;
    if (ids.contains(_selected)) {
      final remaining = _ids;
      _selected = remaining.isEmpty
          ? null
          : remaining[min(oldIndex, remaining.length - 1)];
    }
    _emit();
    final connection = repository.connectionIdentity;
    return _enqueue(() async {
      Set<String> succeeded = {};
      try {
        if (_closed ||
            !repository.snapshot.connected ||
            !identical(connection, repository.connectionIdentity)) {
          throw const RequestCancelled();
        }
        // An uncertain earlier receipt must be reconciled, never overwritten.
        if (repository.fileOperationPending) {
          await repository.reconcileFileOperation();
        }
        await repository.deleteVideos(ids, requestId: requestId);
        succeeded = ids;
      } catch (_) {
        final receipt = repository.snapshot.lastDelete;
        if (receipt != null && receipt.id != previousReceipt) {
          succeeded = receipt.ids.toSet().intersection(ids);
        }
        rethrow;
      } finally {
        _hidden.removeAll(ids);
        _confirmed.addAll(succeeded);
        _entries.removeWhere((key, id) => succeeded.contains(id));
        _fileChanges--;
        // Compress cached ordinals after confirmed removals; fresh metadata
        // will replace this estimate without changing the selected identity.
        final order = _entries.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        if (order.isNotEmpty) {
          _entries.clear();
          for (var i = 0; i < order.length; i++) {
            _entries[order.first.key + i] = order[i].value;
          }
        }
        _emit();
        if (!_closed && _fileChanges == 0) unawaited(_prefetch(force: true));
      }
    });
  }

  /// Explicit navigation such as opening a library item or undoing a delete
  /// follows the authoritative selection, unlike routine background receipts.
  void followRepository() {
    _entries.clear();
    _confirmed.clear();
    _selected = null;
    _epoch++;
    _fetching = false;
    _changed();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    repository.removeListener(_changed);
    super.dispose();
  }
}
