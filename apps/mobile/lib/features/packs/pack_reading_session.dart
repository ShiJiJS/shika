import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../library/server_api.dart' show ApiFailure;

abstract class _Pending {
  String get kind;
  String get requestId;
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
  String get requestId => command.requestId;
  @override
  Future<Object?> resolve(bool send) async =>
      send ? await reader.submit<T>(command) : await reader.receipt<T>(command);
  @override
  void apply(Object result) => accept(result as T);
}

/// The most recent live command failure, retained in memory for diagnosis.
/// It is not UI text, a persisted request log, or permission to replay a write.
class ReaderCommandFailure {
  const ReaderCommandFailure({
    required this.kind,
    required this.requestId,
    required this.receiptLookup,
    required this.failure,
  });
  final String kind, requestId;
  final bool receiptLookup;
  final ApiFailure failure;
}

/// One actual reading route. A displayed frame, not prefetch, owns progress.
class PackReadingSession extends ChangeNotifier {
  PackReadingSession(
    this.repository,
    this.entry, {
    PackReader? reader,
    this.fileCommands,
    this.returnContext,
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
  PackFiles? _files;
  final PackFiles? fileCommands;
  final PackCleanupContext? returnContext;
  PackFiles get cleanupFiles =>
      _files ??= fileCommands ?? repository.createPackFiles();
  bool get cleanupSupported =>
      repository.capabilities.packReaderCleanup &&
      repository.capabilities.packLogicalTrash;
  bool cleanupBusy = false,
      cleanupFrozen = false,
      cleanupCanResend = false,
      cleanupFinished = false;
  String cleanupError = '';
  PackFileCommand? _cleanupCommand, lastDeleteCommand;
  PackFileTask? cleanupTask, lastDeleteTask;
  ReaderCursor? _cleanupOwner;
  String? _undoPack;
  PackFileCommand? get cleanupCommand => _cleanupCommand;
  bool get hasCleanup => _cleanupCommand != null;
  bool get inputBlocked => busy || hasPending || cleanupBusy || cleanupFrozen;
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
  ReaderCommandFailure? _lastCommandFailure;

  /// Preserve the original transport phase/cause when a later receipt is 404
  /// or succeeds. Only a later command exception replaces this bounded record.
  ReaderCommandFailure? get lastCommandFailure => _lastCommandFailure;
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
  bool get hasPending => _pending != null || hasCleanup;
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

  Future<bool> start({String? resumeSessionId}) => resumeSessionId == null
      ? _run(CreatePackReading(_nonce(), entry), _install)
      : resume(resumeSessionId);

  Future<bool> resume(String identity) async {
    if (!live || busy || hasPending) return false;
    busy = true;
    error = '';
    _notify();
    try {
      final value = await reader.read(identity);
      if (!live) return false;
      if (value.finished ||
          value.source != entry.source ||
          value.random != entry.random) {
        throw const LibraryFailure('原阅读范围已结束或来源已变化，请从来源重新进入');
      }
      _install(value);
      return true;
    } catch (failure) {
      if (live) error = failure.toString();
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        _notify();
      }
    }
  }

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
        if (failure is ApiFailure) {
          _lastCommandFailure = ReaderCommandFailure(
            kind: command.kind,
            requestId: command.requestId,
            receiptLookup: !send,
            failure: failure,
          );
        }
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
    if (!live ||
        busy ||
        hasPending ||
        cleanupBusy ||
        cleanupFrozen ||
        range == null) {
      return false;
    }
    final generation = _generation;
    busy = true;
    error = '';
    cleanupError = '';
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
        cleanupBusy ||
        cleanupFrozen ||
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
        cleanupBusy ||
        cleanupFrozen ||
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
      // The opened receipt clears the durable recovery marker. Keep its
      // explanation visible for this reading view; _install resets it per pack.
      recoveryReason = value.recoveryReason ?? recoveryReason;
      if (_sameMark(mark, value.mark)) _saved = serial;
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    if (!live ||
        !opened ||
        !unsaved ||
        busy ||
        hasPending ||
        cleanupBusy ||
        cleanupFrozen ||
        needsReload) {
      return;
    }
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  Future<bool> flush({bool forCleanup = false}) async {
    _saveTimer?.cancel();
    if (!live || cleanupFrozen || (cleanupBusy && !forCleanup)) return false;
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

  Future<PackFileTask?> removeCurrent({required bool quick}) async {
    if (!cleanupSupported ||
        !live ||
        cleanupBusy ||
        cleanupFrozen ||
        hasCleanup ||
        needsReload ||
        cursor == null) {
      return null;
    }
    cleanupBusy = true;
    cleanupError = '';
    _saveTimer?.cancel();
    _notify();
    try {
      if (!await flush(forCleanup: true) ||
          !live ||
          !opened ||
          cursor == null) {
        cleanupError = '请先打开当前图片并确认阅读状态，再整理图包';
        return null;
      }
      final owner = cursor!, generation = _generation;
      final pending = await cleanupFiles.pending();
      if (!live || generation != _generation) return null;
      final existing = pending
          .where((value) => value.resources.contains('pack:${owner.packId}'))
          .firstOrNull;
      _cleanupCommand =
          existing ??
          PackFileCommand.trash(
            _nonce(),
            [owner.packId],
            reading: owner,
            advance: quick,
            label: range!.pack!.name,
            readerContext:
                (returnContext ??
                        PackCleanupContext(entry: entry, quick: quick))
                    .withQuick(quick, session: owner.sessionId),
          );
      _cleanupOwner = owner;
      cleanupTask = null;
      cleanupFinished = false;
      cleanupFrozen = true;
      _notify();
      return await _executeCleanup(submit: existing == null);
    } catch (failure) {
      if (live) cleanupError = packFileFailureMessage(failure);
      return null;
    } finally {
      if (!_disposed) {
        cleanupBusy = false;
        _notify();
        _scheduleSave();
      }
    }
  }

  Future<PackFileTask?> checkCleanup({bool resend = false}) async {
    if (!live || cleanupBusy || !hasCleanup || (resend && !cleanupCanResend)) {
      return null;
    }
    cleanupBusy = true;
    _notify();
    try {
      return await _executeCleanup(submit: resend);
    } finally {
      if (!_disposed) {
        cleanupBusy = false;
        _notify();
        _scheduleSave();
      }
    }
  }

  Future<PackFileTask?> undoDelete(PackFileTask original) async {
    if (!live ||
        cleanupBusy ||
        cleanupFrozen ||
        hasCleanup ||
        needsReload ||
        cursor == null ||
        lastDeleteTask?.id != original.id) {
      return null;
    }
    cleanupBusy = true;
    cleanupError = '';
    _saveTimer?.cancel();
    _notify();
    try {
      if (!await flush(forCleanup: true) || !live || cursor == null) {
        return null;
      }
      _cleanupOwner = cursor;
      _undoPack =
          (lastDeleteCommand!.body['pack_ids'] as List).single as String;
      _cleanupCommand = PackFileCommand.undo(
        _nonce(),
        original.id,
        readerContext: lastDeleteCommand!.readerContext,
      );
      cleanupTask = null;
      cleanupFrozen = true;
      _notify();
      return await _executeCleanup(submit: true);
    } catch (failure) {
      if (live) cleanupError = packFileFailureMessage(failure);
      return null;
    } finally {
      if (!_disposed) {
        cleanupBusy = false;
        _notify();
        _scheduleSave();
      }
    }
  }

  bool _ownsCleanup(PackFileCommand command) =>
      live && identical(command, _cleanupCommand);

  void _discardOldMark() {
    _saveTimer?.cancel();
    _generation++;
    _pageRead++;
    _queueRead++;
    reader.cancelPages();
    reader.cancelQueue();
    loadingPages = loadingQueue = false;
    _mark = null;
    _shownId = null;
    _dirty = _saved = 0;
    opened = false;
    cursor = null;
  }

  Future<bool> _ackCleanup(PackFileCommand command) async {
    await cleanupFiles.acknowledge(command);
    if (!_ownsCleanup(command)) return false;
    _cleanupCommand = null;
    cleanupCanResend = false;
    return true;
  }

  Future<PackFileTask?> _executeCleanup({required bool submit}) async {
    final command = _cleanupCommand!, owner = _cleanupOwner!;
    cleanupError = '';
    cleanupCanResend = false;
    try {
      final task = await cleanupFiles.resolve(
        command,
        submit: submit,
        keepWaiting: () => _ownsCleanup(command),
      );
      if (!_ownsCleanup(command)) return null;
      cleanupTask = task;
      if (task == null || !task.settled) {
        cleanupCanResend =
            task == null && await cleanupFiles.canResend(command);
        cleanupError = task == null
            ? '未找到原请求，核对后可明确重新提交原请求'
            : '操作尚未确认完成，请查询原结果；当前阅读位置已保留';
        return task;
      }
      final result = task.result!;
      if (result.succeeded == 0) {
        if (!await _ackCleanup(command)) return null;
        cleanupFrozen = false;
        needsReload = true;
        cleanupError = '操作未完成，请重新读取后再试';
        return task;
      }
      if (command.kind == 'trash') {
        lastDeleteCommand = command;
        lastDeleteTask = task;
        _discardOldMark();
        final advance =
            command.readingSessionId == owner.sessionId &&
            (command.body['reading'] as Map?)?['advance'] != false &&
            command.body['reading'] != null;
        final transition = result.transition;
        if (!advance || transition?.finished == true) {
          if (!await _ackCleanup(command)) return null;
          cleanupFinished = true;
          repository.packFilesChanged();
          return task;
        }
        if (transition == null ||
            transition.sessionId != owner.sessionId ||
            transition.revision <= owner.sessionRevision) {
          throw const LibraryFailure('图包已移除，原阅读范围的结果需要重新核对');
        }
        final value = await reader.read(owner.sessionId);
        if (!_ownsCleanup(command)) return null;
        if (value.finished ||
            value.revision != transition.revision ||
            value.pack?.id != transition.packId) {
          throw const LibraryFailure('图包已移除，但阅读范围位置已变化，请返回来源核对');
        }
        if (!await _ackCleanup(command)) return null;
        cleanupFrozen = cleanupBusy = false;
        _install(value);
      } else if (command.kind == 'undo') {
        if (result.readingRestored) {
          final value = await reader.read(owner.sessionId);
          if (!_ownsCleanup(command)) return null;
          if (value.finished ||
              value.revision != owner.sessionRevision + 1 ||
              value.pack?.id != _undoPack) {
            throw const LibraryFailure('内容已恢复，但原阅读位置需要重新核对');
          }
          if (!await _ackCleanup(command)) return null;
          cleanupFrozen = cleanupBusy = false;
          _install(value);
        } else {
          if (!await _ackCleanup(command)) return null;
          cleanupFrozen = false;
        }
        lastDeleteTask = null;
        lastDeleteCommand = null;
      }
      repository.packFilesChanged();
      return task;
    } catch (failure) {
      if (!_ownsCleanup(command)) return null;
      cleanupError = packFileFailureMessage(failure);
      try {
        final pending = await cleanupFiles.pending();
        if (_ownsCleanup(command) &&
            !pending.any((value) => value.requestId == command.requestId)) {
          _cleanupCommand = null;
          cleanupFrozen = false;
          needsReload = true;
        }
      } catch (_) {
        /* Unknown persistence state must retain the original command. */
      }
      return null;
    }
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
    _lastCommandFailure = null;
    _generation++;
    _saveTimer?.cancel();
    repository.removeListener(_ownerChanged);
    reader.dispose();
    _pages.clear();
    super.dispose();
  }
}
