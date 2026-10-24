import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../library/server_api.dart' show ApiFailure;

abstract class _Pending {
  String get kind;
  Future<Object?> resolve(bool send);
  void apply(Object result);
}

class _PendingValue<T> implements _Pending {
  _PendingValue(this.reader, this.command, this.accept);
  final PackReader reader;
  final ReaderCommand<T> command;
  final void Function(T) accept;
  @override
  String get kind => command.kind;
  @override
  Future<Object?> resolve(bool send) async =>
      send ? await reader.submit<T>(command) : await reader.receipt<T>(command);
  @override
  void apply(Object result) => accept(result as T);
}

/// One actual reading route. A displayed frame, not prefetch, owns progress.
class PackReadingSession extends ChangeNotifier {
  PackReadingSession(
    this.repository,
    this.entry, {
    PackReader? reader,
    this.saveDelay = const Duration(milliseconds: 700),
    String Function()? nonce,
  }) : reader = reader ?? repository.createPackReader(),
       _nonce = nonce ?? _newKey {
    repository.addListener(_ownerChanged);
  }
  static int _counter = 0;
  static String _newKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}-${_counter++}';
  static const pageSize = 40, maximumPages = 120;
  final LibraryRepository repository;
  final PackReadingEntry entry;
  final PackReader reader;
  final Duration saveDelay;
  final String Function() _nonce;
  bool _disposed = false,
      busy = false,
      loadingPages = false,
      loadingQueue = false;
  bool manifestReady = false;
  bool invalidated = false,
      opened = false,
      canResend = false,
      needsReload = false;
  String error = '', pageError = '', queueError = '';
  String? recoveryReason;
  PackReadingRange? range;
  ReaderCursor? cursor;
  ReaderPreferences preferences = const ReaderPreferences();
  ReaderQueuePage? queuePage;
  int index = 0, _generation = 0, _pageRead = 0, _queueRead = 0;
  double offsetRatio = 0;
  bool _completed = false, _atEnd = false;
  String? _shownId;
  ReaderMark? _mark;
  int _dirty = 0, _saved = 0;
  Timer? _saveTimer;
  _Pending? _pending;
  Future<bool>? _work;
  final SplayTreeMap<int, ReaderPage> _pages = SplayTreeMap();
  Map<int, ReaderPage> get pages => UnmodifiableMapView(_pages);
  int get total => range?.pack?.pageCount ?? 0;
  int get packEpoch => _generation;
  String? get pendingKind => _pending?.kind;
  bool get hasPending => _pending != null;
  bool get unsaved => _mark != null && _dirty > _saved;
  bool get live => !_disposed && !invalidated && reader.isCurrent;
  ReaderPage? get currentPage => _pages[index];
  int get windowStart => _pages.isEmpty ? index : _pages.firstKey()!;
  int get windowEnd => _pages.isEmpty ? index : _pages.lastKey()!;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _ownerChanged() {
    if (_disposed || reader.isCurrent) return;
    invalidated = true;
    _generation++;
    _saveTimer?.cancel();
    _pages.clear();
    _shownId = null;
    _mark = null;
    error = '服务连接或管理数据已变化，请返回来源后重新打开';
    _notify();
  }

  Future<bool> start() => _run(CreatePackReading(_nonce(), entry), _install);

  void _install(PackReadingRange value) {
    _generation++;
    _pageRead++;
    _queueRead++;
    reader.cancelPages();
    reader.cancelQueue();
    _saveTimer?.cancel();
    range = value;
    cursor = value.ownership;
    queuePage = null;
    opened = false;
    manifestReady = false;
    _shownId = null;
    _mark = null;
    _dirty = _saved = 0;
    _pages.clear();
    loadingPages = loadingQueue = false;
    pageError = queueError = '';
    needsReload = false;
    final resume = value.resume;
    index = resume?.pageIndex ?? 0;
    offsetRatio = resume?.mark.offsetRatio ?? 0;
    preferences = resume?.preferences ?? const ReaderPreferences();
    recoveryReason = resume?.recoveryReason;
    _completed = resume?.mark.completed ?? false;
    _atEnd = _completed;
    if (resume != null) _pages[index] = resume.page;
    _notify();
    if (cursor != null) unawaited(ensure(index, includeWindow: true));
  }

  Future<bool> _run<T>(ReaderCommand<T> command, void Function(T) accept) {
    if (!live || busy || hasPending) return Future.value(false);
    _pending = _PendingValue(reader, command, accept);
    return _execute(true);
  }

  Future<bool> _execute(bool send) {
    if (!live || busy || _pending == null) return Future.value(false);
    final command = _pending!, generation = _generation;
    busy = true;
    error = '';
    canResend = false;
    _notify();
    final work = () async {
      var success = false;
      try {
        final result = await command.resolve(send);
        if (!live ||
            generation != _generation ||
            !identical(command, _pending)) {
          return false;
        }
        if (result == null) {
          canResend = true;
          error = '未找到这次操作的回执。可再次提交原请求，或返回来源';
          return false;
        }
        _pending = null;
        needsReload = false;
        canResend = false;
        command.apply(result);
        success = true;
        return true;
      } catch (failure) {
        if (!live || generation != _generation) return false;
        error = failure.toString();
        if (failure is ApiFailure &&
            failure.status != null &&
            failure.status! >= 400 &&
            failure.status! < 500 &&
            ![408, 429].contains(failure.status)) {
          _pending = null;
          needsReload = true;
        }
        return false;
      } finally {
        if (!_disposed) {
          busy = false;
          _work = null;
          _notify();
          if (success && live && !hasPending) {
            if (!opened && _shownId != null) {
              unawaited(_confirmFrame());
            } else {
              _scheduleSave();
            }
          }
        }
      }
    }();
    _work = work;
    return work;
  }

  /// This never submits an unknown operation. The UI exposes resend separately.
  Future<bool> checkPending() => _execute(false);
  Future<bool> resendPending() =>
      canResend ? _execute(true) : Future.value(false);

  Future<bool> reload() async {
    if (!live || busy || hasPending || range == null) return false;
    final generation = _generation;
    busy = true;
    error = '';
    _notify();
    try {
      final value = await reader.read(range!.id);
      if (!live || generation != _generation) return false;
      _install(value);
      return true;
    } catch (failure) {
      if (live && generation == _generation) error = failure.toString();
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> ensure(int target, {bool includeWindow = false}) async {
    if (!live || cursor == null || target < 0 || target >= total) return;
    if (!includeWindow && _pages.containsKey(target)) return;
    final owner = cursor!, generation = _generation, request = ++_pageRead;
    final start = target ~/ pageSize * pageSize;
    loadingPages = true;
    pageError = '';
    _notify();
    try {
      final page = await reader.pages(
        owner.packId,
        version: owner.version,
        offset: start,
        limit: pageSize,
      );
      if (!live || generation != _generation || request != _pageRead) return;
      if (page.total != total ||
          page.version != owner.version ||
          page.offset != start ||
          page.pages.isEmpty) {
        throw const LibraryFailure('图包页清单已变化，请重新读取阅读位置');
      }
      // A jump creates a new contiguous window; ordinary edge loads retain it.
      if (_pages.isNotEmpty &&
          (start > windowEnd + 1 || start + page.pages.length < windowStart)) {
        _pages.clear();
      }
      for (var i = 0; i < page.pages.length; i++) {
        _pages[start + i] = page.pages[i];
      }
      manifestReady = true;
      while (_pages.length > maximumPages) {
        final first = _pages.firstKey()!, last = _pages.lastKey()!;
        _pages.remove(
          (index - first).abs() > (last - index).abs() ? first : last,
        );
      }
    } catch (failure) {
      if (live && generation == _generation && request == _pageRead) {
        pageError = failure.toString();
      }
    } finally {
      if (!_disposed && generation == _generation && request == _pageRead) {
        loadingPages = false;
        _notify();
      }
    }
  }

  void show(int pageIndex, {double ratio = 0, bool end = false}) {
    if (!live ||
        pendingKind == 'position' ||
        pageIndex < 0 ||
        pageIndex >= total) {
      return;
    }
    final changed = pageIndex != index;
    index = pageIndex;
    offsetRatio = ratio.clamp(0, 1);
    _atEnd = end;
    if (changed) _shownId = null;
    if (_shownId != null) _rememberMark();
    _notify();
    if (!_pages.containsKey(index)) unawaited(ensure(index));
  }

  /// Called only by the current displayed widget after a real decoded frame.
  void visibleFrame(int pageIndex, String pageId, int epoch) {
    if (!live ||
        pendingKind == 'position' ||
        epoch != _generation ||
        pageIndex != index ||
        currentPage?.id != pageId ||
        currentPage?.readable != true) {
      return;
    }
    _shownId = pageId;
    _rememberMark();
    if (!opened && !busy && !hasPending) unawaited(_confirmFrame());
  }

  void _rememberMark() {
    if (_shownId == null) return;
    _completed = _completed || (index == total - 1 && _atEnd);
    final next = ReaderMark(
      _shownId!,
      offsetRatio: offsetRatio,
      completed: _completed,
    );
    if (_mark?.pageId == next.pageId &&
        _mark?.offsetRatio == next.offsetRatio &&
        _mark?.completed == next.completed) {
      return;
    }
    _mark = next;
    _dirty++;
    _scheduleSave();
  }

  bool _sameMark(ReaderMark a, ReaderMark b) =>
      a.pageId == b.pageId &&
      a.offsetRatio == b.offsetRatio &&
      a.completed == b.completed;
  Future<bool> _confirmFrame() async {
    final owner = cursor, mark = _mark;
    if (owner == null || mark == null || opened || busy || hasPending) {
      return false;
    }
    final serial = _dirty;
    return _run(OpenPackReading(_nonce(), owner, mark.pageId), (
      ReaderState value,
    ) {
      opened = true;
      cursor = ReaderCursor(
        sessionId: owner.sessionId,
        sessionRevision: value.sessionRevision!,
        packId: owner.packId,
        version: owner.version,
        progressRevision: value.revision,
      );
      preferences = value.preferences;
      recoveryReason = value.recoveryReason;
      if (_sameMark(mark, value.mark)) _saved = serial;
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    if (!live || !opened || !unsaved || busy || hasPending) return;
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  Future<bool> flush() async {
    _saveTimer?.cancel();
    if (!live) return false;
    for (var wait = 0; wait < 4 && _work != null; wait++) {
      await _work;
    }
    if (!live || hasPending || needsReload) return false;
    if (_mark == null) return true;
    if (!opened && !await _confirmFrame()) return false;
    for (var round = 0; round < 3 && unsaved; round++) {
      final owner = cursor!, mark = _mark!, serial = _dirty;
      final saved = await _run(WritePackProgress(_nonce(), owner, mark), (
        ReaderState value,
      ) {
        cursor = ReaderCursor(
          sessionId: owner.sessionId,
          sessionRevision: value.sessionRevision!,
          packId: owner.packId,
          version: owner.version,
          progressRevision: value.revision,
        );
        _saved = serial;
      });
      if (!saved || !live) return false;
    }
    return !unsaved && !hasPending;
  }

  Future<bool> setPreferences(ReaderPreferences chosen) async {
    if (!await flush() || !live || cursor == null) return false;
    preferences = chosen;
    _notify();
    return _run(WritePackPreferences(_nonce(), cursor!, chosen), (
      ReaderPreferences value,
    ) {
      preferences = value;
    });
  }

  Future<bool> move(String packId) async {
    if (!await flush() || !live || cursor == null) return false;
    return _run(
      MovePackReading(
        _nonce(),
        sessionId: cursor!.sessionId,
        revision: cursor!.sessionRevision,
        packId: packId,
      ),
      _install,
    );
  }

  Future<void> loadQueue({int offset = 0}) async {
    if (!live || cursor == null) return;
    final owner = cursor!, generation = _generation, request = ++_queueRead;
    loadingQueue = true;
    queueError = '';
    _notify();
    try {
      final page = await reader.queue(
        owner.sessionId,
        offset: offset,
        limit: pageSize,
      );
      if (!live || generation != _generation || request != _queueRead) return;
      if (page.revision != owner.sessionRevision) {
        throw const LibraryFailure('本次范围位置已变化，请重新读取');
      }
      queuePage = page;
    } catch (failure) {
      if (live && generation == _generation && request == _queueRead) {
        queueError = failure.toString();
      }
    } finally {
      if (!_disposed && generation == _generation && request == _queueRead) {
        loadingQueue = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _saveTimer?.cancel();
    repository.removeListener(_ownerChanged);
    reader.dispose();
    _pages.clear();
    super.dispose();
  }
}
