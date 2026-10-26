import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../library/models.dart';
import '../library/management_archives.dart';
import '../library/backup_file_picker.dart';
import '../features/settings/archive_backup_page.dart';
import '../app/app_shell.dart';
import '../app/media_workspace.dart';
import '../features/library/browse_context.dart';
import '../features/library/library_query_controller.dart';
import '../features/preview/video_preview_route.dart';
import '../features/packs/pack_trash_page.dart';
import '../features/settings/maintenance_tasks_page.dart';
import 'paper_management.dart';
import '../features/settings/default_settings_sheet.dart';
import '../features/settings/media_root_sheet.dart';
import '../features/settings/missing_media_page.dart';
import '../library/repository.dart';
import 'trash_layout.dart';
import 'paper.dart';
import 'paper_form.dart';
import 'media_layout.dart';
import 'preference_switch.dart';
import 'player.dart';
import 'sheets.dart';
import 'preferences.dart';
import 'media_poster.dart';
import 'playback_session.dart';
import 'browsing_session.dart';

abstract interface class BackupFiles {
  Future<bool> save(String text);
  Future<String?> open();
}

class NativeBackupFiles implements BackupFiles {
  @override
  Future<bool> save(String text) async =>
      await FilePicker.saveFile(
        dialogTitle: '导出管理数据备份',
        fileName: 'video-viewer-backup.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(text)),
      ) !=
      null;
  @override
  Future<String?> open() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    final size = await file.length();
    if (size == null || size > 32 * 1024 * 1024) {
      throw const LibraryFailure('备份文件过大或无法读取');
    }
    try {
      return utf8.decode(await file.readAsBytes());
    } on FormatException {
      throw const LibraryFailure('备份文件不是有效的 UTF-8 文本');
    }
  }
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({
    super.key,
    required this.repository,
    this.initialError,
    this.backupFiles,
    this.backupArchiveFiles = const NativeBackupArchiveFiles(),
    required this.preferences,
    this.initializeRepository = false,
  });
  final LibraryRepository repository;
  final String? initialError;
  final BackupFiles? backupFiles;
  final BackupArchiveFiles backupArchiveFiles;
  final UiPreferences preferences;
  final bool initializeRepository;
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  final _playback = PlaybackSession();
  LibraryRepository get repo => widget.repository;
  late final _browsing = BrowsingSession(repo);
  LibrarySnapshot get data => _browsing.snapshot;
  bool get libraryFirst => repo.supportsFixedPreviews;
  String get landing => libraryFirst ? 'library' : 'browse';
  late String page = data.connected ? landing : 'connection';
  bool _lastConnected = false;
  VideoBrowseContext libraryContext = VideoBrowseContext(sort: VideoSort.name);
  Object? _entryConnection;
  PlayOrder? _initialEntryOrder;
  PlayOrder get entryOrder =>
      widget.preferences.videoOrder ?? _initialEntryOrder ?? data.order;
  bool viewing = false;
  VideoQuery get entryQuery => libraryFirst ? libraryContext.query : data.query;
  late String error = widget.initialError ?? '';
  bool _busy = false, review = false, selecting = false, obscured = false;
  Timer? _deleteNoticeTimer;
  String? _deleteNotice, _deleteNoticeRequest;
  DeleteOperation? _undoNotice;
  bool get busy => _busy || repo.backupRestorePending;
  String search = '', tagSearch = '';
  late final videoSearch = TextEditingController(text: search);
  Set<String> selected = {};
  int playerEpoch = 0;
  late final _library = LibraryQueryController(repo);
  List<LibraryVideo> get libraryItems => _library.state.items;
  int get libraryTotal => _library.state.total;
  bool get libraryLoading => _library.state.loading;
  String get libraryError => _library.state.error;
  final libraryScroll = ScrollController();
  VideoBrowseContext? _pendingReturn;
  List<String> _returnAnchors = const [];
  bool _restoringLibrary = false;
  int _libraryViewGeneration = 0;
  int _previewGeneration = 0;
  String previousScope = '';
  List<LibraryVideo> trashItems = [];
  int trashTotal = 0, trashGeneration = 0;
  MediaKind trashKind = MediaKind.video;
  bool trashLoading = false;
  bool selectingAllTrash = false, restoringTrash = false;
  bool purgingTrash = false, queryingFiles = false, cleaningMissing = false;
  Timer? _roundNoticeTimer;
  bool _roundNotice = false;
  String trashError = '';
  List<LibraryVideo> missingItems = [];
  int missingTotal = 0, missingGeneration = 0;
  bool missingLoading = false;
  String missingError = '';
  late final BackupFiles files = widget.backupFiles ?? NativeBackupFiles();
  final address = TextEditingController(),
      port = TextEditingController(),
      passphrase = TextEditingController();
  String get title => {
    'browse': review ? '快速整理' : '浏览',
    'library': '视频库',
    'tags': '标签',
    'settings': '设置',
    'roots': '媒体目录',
    'trash': '回收站',
    'backup': '备份与恢复',
    'tasks': '操作任务',
    'connection': data.connected ? '服务器连接' : '连接',
  }[page]!;
  bool get mediaPage => page == 'browse' || page == 'library';
  bool get primaryPage =>
      ['browse', 'library', 'tags', 'settings'].contains(page);
  bool get compactTrashKeyboard {
    final media = MediaQuery.of(context);
    return page == 'trash' &&
        media.viewInsets.bottom > 0 &&
        media.size.height -
                media.viewInsets.bottom -
                media.viewPadding.vertical <
            300;
  }

  EdgeInsets get snackMargin => EdgeInsets.fromLTRB(
    12,
    0,
    12,
    page == 'browse'
        ? (review ? 180 : 120)
        : ['library', 'trash'].contains(page)
        ? 100
        : 16,
  );
  @override
  void initState() {
    super.initState();
    _lastConnected = data.connected;
    _browsing.addListener(changed);
    _library.addListener(libraryChanged);
    repo.libraryPreparation.addListener(preparationChanged);
    libraryScroll.addListener(loadNearBottom);
    address.text = data.address;
    port.text = '${data.port}';
    previousScope = jsonEncode(data.query.toJson());
    restoreEntryForConnection();
    if (repo is DemoControls) passphrase.text = 'demo';
    if (widget.initializeRepository) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final connected = await perform(repo.initialize);
        if (!mounted) return;
        address.text = data.address;
        port.text = '${data.port}';
        if (connected && data.connected) {
          go(repo.backupRestorePending ? 'backup' : landing);
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && page == 'library' && !libraryFirst) {
        unawaited(loadLibrary());
      }
    });
  }

  void changed() {
    if (!mounted) return;
    final message = _browsing.message;
    if (message != null) {
      _browsing.message = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => notice(message));
    }
    final nextScope = jsonEncode(data.query.toJson());
    setState(() {
      restoreEntryForConnection();
      if (nextScope != previousScope) {
        selected = {};
        previousScope = nextScope;
      }
      if (!data.connected && page != 'connection') page = 'connection';
      if (!data.connected && repo.connectionError != null) {
        error = repo.connectionError!;
      }
      if (!_lastConnected && data.connected && page == 'connection') {
        page = landing;
        error = '';
        selected = {};
        selecting = viewing = false;
      }
      _lastConnected = data.connected;
    });
    if (page == 'library' && !viewing && !libraryFirst) {
      if (libraryFirst &&
          _pendingReturn == null &&
          libraryItems.isNotEmpty &&
          libraryContext.copyWith(query: entryQuery, search: search).queryKey ==
              _library.state.context.queryKey) {
        final position = captureLibraryPosition();
        _pendingReturn = position.context;
        _returnAnchors = position.anchors;
      }
      unawaited(loadLibrary());
    }
    if (page == 'trash') unawaited(loadTrash());
    if (page == 'roots' && !repo.capabilities.packMissingCleanup) {
      unawaited(loadMissing());
    }
  }

  void restoreEntryForConnection() {
    if (!data.connected ||
        !libraryFirst ||
        identical(_entryConnection, repo.connectionIdentity)) {
      return;
    }
    _entryConnection = repo.connectionIdentity;
    _initialEntryOrder = widget.preferences.videoOrder ?? data.order;
    final entry = repo.savedPreviewEntry;
    libraryContext = VideoBrowseContext(
      query: entry?.query,
      search: entry?.search ?? '',
      source: entry?.source ?? BrowseSource.library,
      sort: entry?.sort ?? VideoSort.name,
    );
    search = libraryContext.search;
    videoSearch.text = search;
    _pendingReturn = null;
    _returnAnchors = const [];
    _restoringLibrary = false;
  }

  void preparationChanged() {
    if (mounted) setState(() {});
  }

  void loadNearBottom() {
    if (page == 'library' &&
        !viewing &&
        !_restoringLibrary &&
        libraryScroll.hasClients &&
        !libraryLoading &&
        libraryError.isEmpty &&
        libraryItems.isNotEmpty) {
      if (libraryScroll.position.extentBefore < 180 &&
          _library.state.hasBefore) {
        unawaited(loadLibrary(before: true));
      } else if (libraryScroll.position.extentAfter < 480 &&
          _library.state.hasAfter) {
        unawaited(loadLibrary(more: true));
      }
    }
  }

  Future<void> loadMissing({bool more = false}) async {
    if (page != 'roots' || (more && missingLoading)) return;
    final generation = ++missingGeneration;
    setState(() {
      missingLoading = true;
      missingError = '';
    });
    try {
      final result = await repo.loadMissing(
        offset: more ? missingItems.length : 0,
      );
      if (!mounted || generation != missingGeneration || page != 'roots') {
        return;
      }
      setState(() {
        missingItems = more ? [...missingItems, ...result.items] : result.items;
        missingTotal = result.total;
      });
    } on RequestCancelled {
      // A newer page owns the result.
    } catch (e) {
      if (mounted && generation == missingGeneration) {
        setState(() => missingError = e.toString());
      }
    } finally {
      if (mounted && generation == missingGeneration) {
        setState(() => missingLoading = false);
      }
    }
  }

  Future<void> loadTrash({bool more = false}) async {
    if (page != 'trash' ||
        trashKind != MediaKind.video ||
        (more && trashLoading)) {
      return;
    }
    final generation = ++trashGeneration;
    setState(() {
      trashLoading = true;
      trashError = '';
    });
    try {
      final result = await repo.loadTrash(offset: more ? trashItems.length : 0);
      if (!mounted || generation != trashGeneration || page != 'trash') return;
      setState(() {
        trashItems = more ? [...trashItems, ...result.items] : result.items;
        trashTotal = result.total;
        selected.removeWhere((id) => !trashItems.any((v) => v.id == id));
      });
    } on RequestCancelled {
      // A newer page owns the list.
    } catch (e) {
      if (mounted && generation == trashGeneration) {
        setState(() => trashError = e.toString());
      }
    } finally {
      if (mounted && generation == trashGeneration) {
        setState(() => trashLoading = false);
      }
    }
  }

  void libraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> loadLibrary({bool more = false, bool before = false}) async {
    if (page != 'library' || viewing || ((more || before) && libraryLoading)) {
      return;
    }
    final generation = ++_libraryViewGeneration;
    final next = VideoBrowseContext(
      query: entryQuery,
      search: search,
      source: libraryFirst ? libraryContext.source : BrowseSource.library,
      sort: libraryFirst ? libraryContext.sort : VideoSort.path,
      scrollOffset: libraryScroll.hasClients ? libraryScroll.offset : 0,
    );
    libraryContext = next;
    if (_pendingReturn?.queryKey != next.queryKey) _pendingReturn = null;
    if (next.queryKey != _library.state.context.queryKey) {
      setState(() => selected = {});
    }
    final restoring = _pendingReturn;
    final oldStart = _library.state.offset;
    final oldPixels = libraryScroll.hasClients ? libraryScroll.offset : 0.0;
    _restoringLibrary = restoring != null || before;
    if (restoring != null) {
      await _library.restore(restoring, anchors: _returnAnchors);
    } else {
      await _library.load(next, more: more, before: before);
    }
    if (generation != _libraryViewGeneration) return;
    if (mounted && page == 'library') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _libraryViewGeneration) return;
        if (_library.state.context.queryKey == next.queryKey &&
            libraryError.isEmpty &&
            libraryScroll.hasClients) {
          double? pixels;
          if (restoring != null && identical(restoring, _pendingReturn)) {
            final anchor = _library.state.anchorIndex ?? _library.state.offset;
            pixels =
                ((anchor - _library.state.offset) ~/ 2) * 308 +
                restoring.scrollInset;
            setState(() => _pendingReturn = null);
          } else if (before) {
            pixels =
                oldPixels + ((oldStart - _library.state.offset) ~/ 2) * 308;
          }
          if (pixels != null) {
            libraryScroll.jumpTo(
              pixels.clamp(0.0, libraryScroll.position.maxScrollExtent),
            );
          }
        }
        _restoringLibrary = false;
        loadNearBottom();
      });
    } else {
      _restoringLibrary = false;
    }
  }

  Future<void> setEntryQuery(VideoQuery query) async {
    if (!libraryFirst) return repo.setScope(query);
    setState(() {
      libraryContext = libraryContext.copyWith(query: query);
      selected = {};
    });
    await loadLibrary();
  }

  ({VideoBrowseContext context, List<String> anchors})
  captureLibraryPosition() {
    final offset = libraryScroll.hasClients ? libraryScroll.offset : 0.0;
    final first = libraryItems.isEmpty
        ? null
        : libraryItems[((offset ~/ 308) * 2).clamp(0, libraryItems.length - 1)]
              .id;
    final localIndex = ((offset ~/ 308) * 2).clamp(
      0,
      (libraryItems.length - 1).clamp(0, libraryItems.length),
    );
    final anchors = [
      ...libraryItems.skip(localIndex).take(8).map((item) => item.id),
      ...libraryItems
          .take(localIndex)
          .toList()
          .reversed
          .take(8)
          .map((item) => item.id),
    ];
    return (
      context: libraryContext.copyWith(
        query: entryQuery,
        search: search,
        scrollOffset: offset,
        scrollAnchor: first,
        scrollIndex: _library.state.offset + localIndex,
        scrollInset: offset % 308,
      ),
      anchors: anchors,
    );
  }

  Future<void> openPreview({String? anchor, bool quick = false}) async {
    if (viewing || busy || page != 'library') return;
    final generation = ++_previewGeneration;
    final connection = repo.connectionIdentity;
    FocusScope.of(context).unfocus();
    final position = captureLibraryPosition();
    final origin = position.context, anchors = position.anchors;
    viewing = true;
    _libraryViewGeneration++;
    _restoringLibrary = false;
    _library.cancel();
    var pushed = false;
    try {
      if (!await perform(() async {
        if (!repo.capabilities.managedPlaybackDefaults) {
          await widget.preferences.ensureVideoOrder(entryOrder);
        }
        final order = await repo.defaultVideoOrder(entryOrder);
        if (!mounted ||
            generation != _previewGeneration ||
            !identical(connection, repo.connectionIdentity)) {
          throw const RequestCancelled();
        }
        await repo.beginPreview(origin.entry, anchor: anchor, order: order);
      })) {
        return;
      }
      if (!mounted ||
          generation != _previewGeneration ||
          !identical(connection, repo.connectionIdentity) ||
          !data.connected ||
          page != 'library') {
        return;
      }
      final route = PageRouteBuilder<void>(
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        pageBuilder: (context, animation, secondary) => VideoPreviewRoute(
          repository: repo,
          preferences: widget.preferences,
          origin: origin,
          quick: quick,
        ),
        transitionsBuilder: (context, animation, secondary, child) =>
            MediaQuery.disableAnimationsOf(context)
            ? child
            : FadeTransition(opacity: animation, child: child),
      );
      pushed = true;
      await Navigator.of(context).push(route);
      await route.completed;
      if (!mounted) return;
      libraryContext = origin;
      viewing = false;
      _pendingReturn = origin;
      _returnAnchors = anchors;
      await loadLibrary();
    } finally {
      viewing = false;
      if (mounted && !pushed && _pendingReturn != null && page == 'library') {
        unawaited(loadLibrary());
      } else if (mounted && !pushed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) loadNearBottom();
        });
      }
    }
  }

  @override
  void dispose() {
    _deleteNoticeTimer?.cancel();
    _roundNoticeTimer?.cancel();
    unawaited(_playback.close());
    _library.removeListener(libraryChanged);
    _library.dispose();
    trashGeneration++;
    missingGeneration++;
    repo.cancelTrashRead();
    repo.cancelMissingRead();
    _browsing.removeListener(changed);
    _browsing.dispose();
    repo.libraryPreparation.removeListener(preparationChanged);
    libraryScroll.dispose();
    address.dispose();
    port.dispose();
    passphrase.dispose();
    videoSearch.dispose();
    super.dispose();
  }

  void go(String next) {
    _previewGeneration++;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      page = next;
      selected = {};
      selecting = false;
    });
    if (next == 'library') {
      if (!libraryFirst) unawaited(loadLibrary());
    } else {
      _libraryViewGeneration++;
      _restoringLibrary = false;
      _library.cancel();
    }
    if (next == 'trash') {
      trashItems = [];
      unawaited(loadTrash());
    } else {
      trashGeneration++;
      repo.cancelTrashRead();
    }
    if (next == 'roots') {
      missingItems = [];
      if (!repo.capabilities.packMissingCleanup) unawaited(loadMissing());
    } else {
      missingGeneration++;
      repo.cancelMissingRead();
    }
  }

  void notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(margin: snackMargin, content: Text(text)));
  }

  Future<bool> perform(
    Future<void> Function() action, {
    bool allowMaintenance = false,
  }) async {
    if (_busy || (!allowMaintenance && repo.backupRestorePending)) return false;
    setState(() {
      _busy = true;
      error = '';
    });
    try {
      await action();
      return true;
    } on RequestCancelled {
      return false;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T?> sheet<T>(Widget child, {bool dismissible = true}) async {
    setState(() => obscured = true);
    try {
      return await paperSheet<T>(context, child, dismissible: dismissible);
    } finally {
      if (mounted) setState(() => obscured = false);
    }
  }

  Future<void> scope({bool quick = false}) async {
    final q = await sheet<VideoQuery>(
      ScopeSheet(
        repository: repo,
        review: quick,
        initial: page == 'library' ? entryQuery : data.query,
      ),
    );
    if (q != null) {
      if (libraryFirst && page == 'library') {
        await setEntryQuery(q);
        return;
      }
      await perform(() async {
        await repo.setScope(q);
        _browsing.followRepository();
        playerEpoch++;
      });
    }
  }

  Future<void> folder() async {
    final value = await sheet<String>(
      FolderPicker(
        repository: repo,
        initial: page == 'library' ? entryQuery.folder : data.query.folder,
      ),
    );
    if (value != null) {
      if (libraryFirst && page == 'library') {
        await setEntryQuery(entryQuery.copy(folder: value));
        return;
      }
      await perform(() async {
        await repo.setScope(data.query.copy(folder: value));
        _browsing.followRepository();
        playerEpoch++;
      });
    }
  }

  Future<void> order() async {
    if (libraryFirst && repo.capabilities.managedPlaybackDefaults) {
      await sheet<void>(
        DefaultSettingsSheet(
          repository: repo,
          local: widget.preferences,
          video: true,
        ),
      );
      return;
    }
    final mode = await sheet<PlayOrder>(
      SheetFrame(
        title: libraryFirst ? '默认播放顺序' : '播放模式',
        children: [
          if (libraryFirst) note('只影响下一次进入预览，不改变当前范围。'),
          for (final value in PlayOrder.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                value == PlayOrder.random
                    ? Icons.shuffle
                    : Icons.format_list_numbered,
              ),
              title: Text(value == PlayOrder.random ? '随机播放' : '顺序播放'),
              subtitle: Text(
                libraryFirst
                    ? value == PlayOrder.random
                          ? '范围内随机排列'
                          : '沿用入口列表的排序'
                    : value == PlayOrder.random
                    ? '本轮向前不重复，允许回看'
                    : '按目录和文件名排列',
              ),
              trailing: (libraryFirst ? entryOrder : data.order) == value
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (mode != null) {
      if (libraryFirst) {
        await perform(() => widget.preferences.setVideoOrder(mode));
        return;
      }
      await perform(() async {
        await repo.setScope(data.query, order: mode);
        _browsing.followRepository();
        playerEpoch++;
      });
    }
  }

  Future<bool> step(int delta) async {
    if (data.round.isEmpty || busy || obscured) return false;
    // The adjacent window may have no next playable entry even when a missing
    // tail is still included in the server's candidate count until a scan.
    if (delta > 0 && data.position == data.round.length - 1) {
      if (_browsing.position + 1 < repo.playbackTotal) {
        return _browsing.step(delta);
      }
      if (!mounted) return false;
      _roundNoticeTimer?.cancel();
      setState(() => _roundNotice = true);
      _roundNoticeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _roundNotice = false);
      });
      return false;
    }
    return _browsing.step(delta);
  }

  Future<void> tag(Set<String> ids) async {
    final saved = await sheet<bool>(TagEditor(repository: repo, ids: {...ids}));
    if (saved == true) {
      _browsing.followRepository();
      setState(() {
        selected = {};
        selecting = false;
      });
      notice('标签已保存');
    }
  }

  Future<void> remove(Set<String> ids) async {
    final requestId = 'delete-${DateTime.now().microsecondsSinceEpoch}';
    _deleteNoticeTimer?.cancel();
    setState(() {
      _deleteNoticeRequest = requestId;
      _deleteNotice = '正在移入回收站…';
      _undoNotice = null;
    });
    _deleteNoticeTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _deleteNotice = null;
          _undoNotice = null;
        });
      }
    });
    final previous = data.lastDelete?.id;
    var completed = false;
    try {
      final work = _browsing.delete({...ids}, requestId);
      setState(() {
        selected.removeAll(ids);
        selecting = false;
      });
      await work;
      completed = true;
    } on RequestCancelled {
      return;
    } catch (e) {
      if (mounted) {
        notice(
          repo.fileOperationPending
              ? '删除结果待确认，可继续浏览，稍后在设置中查询结果'
              : '删除未完成，未成功的视频已恢复：$e',
        );
      }
    }
    if (!mounted) return;
    final operation = data.lastDelete;
    if (operation != null &&
        operation.id != previous &&
        _deleteNoticeRequest == requestId &&
        _deleteNotice != null) {
      setState(() {
        selected.removeAll(operation.ids);
        if (completed) selecting = false;
      });
      setState(() {
        _deleteNotice = completed
            ? '已移入回收站'
            : '已移入 ${operation.ids.length} 个，其余未完成';
        _undoNotice = operation;
      });
    } else if (!completed && _deleteNoticeRequest == requestId && mounted) {
      setState(() => _deleteNotice = null);
    }
  }

  Future<bool> confirm(String heading, String text, String action) async {
    setState(() => obscured = true);
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                heading,
                style: Paper.of(context).title.copyWith(fontSize: 21),
              ),
              content: Text(text),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    foregroundColor: Paper.of(context).danger,
                  ),
                  child: Text(action),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      if (mounted) setState(() => obscured = false);
    }
  }

  Future<void> menu(String action) async {
    setState(() => obscured = false);
    final current = _browsing.current;
    switch (action) {
      case 'theme':
        await perform(
          () => widget.preferences.setDark(!widget.preferences.dark),
        );
      case 'tag':
        if (current != null) await tag({current.id});
      case 'undo':
        final operation = data.lastDelete;
        if (operation != null) {
          await perform(() async {
            await repo.undoDelete(operationId: operation.id);
            _browsing.followRepository();
          });
        }
      case 'details':
        if (current != null) {
          await sheet<void>(
            SheetFrame(
              title: '视频详情',
              children: [
                Text(
                  current.name,
                  style: Paper.of(context).title.copyWith(fontSize: 17),
                ),
                note(
                  '${current.portrait ? '竖版' : '横版'} · ${current.seconds} 秒 · ${current.type}',
                ),
                SelectableText(
                  current.path,
                  style: TextStyle(
                    fontSize: 12,
                    color: Paper.of(context).olive,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      case 'review':
        setState(() {
          review = !review;
          page = 'browse';
        });
      case 'round':
        await perform(() async {
          await repo.newRound();
          _browsing.followRepository();
          playerEpoch++;
        });
      case 'delete':
        if (current != null) await remove({current.id});
      default:
        go(action);
    }
  }

  Widget managementStatus({bool separator = true}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (separator || _busy)
        SizedBox(
          height: page == 'trash' && !_busy ? 1 : 2,
          width: page == 'trash' ? double.infinity : null,
          child: _busy
              ? const LinearProgressIndicator(
                  key: Key('management-loading'),
                  minHeight: 2,
                )
              : ColoredBox(color: Paper.of(context).line),
        ),
      if (error.isNotEmpty)
        Container(
          color: Theme.of(context).colorScheme.errorContainer,
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  error,
                  key: const Key('operation-error'),
                  style: TextStyle(
                    color: Paper.of(context).danger,
                    fontSize: 12,
                  ),
                ),
              ),
              iconAction(
                '关闭错误提示',
                Icons.close,
                () => setState(() => error = ''),
              ),
            ],
          ),
        ),
      if (data.connected &&
          repo.fileOperationPending &&
          !_browsing.deleting &&
          !restoringTrash &&
          !purgingTrash)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: repo.fileStatus,
                  builder: (_, status, _) => Text(
                    status ?? '文件操作结果待确认',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              TextButton(
                onPressed: queryingFiles ? null : queryFileResult,
                child: Text(queryingFiles ? '正在查询…' : '查询结果'),
              ),
            ],
          ),
        ),
      if (data.connected && repo.backupRestorePending)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text('恢复结果待确认', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                key: const Key('backup-query'),
                onPressed: _busy
                    ? null
                    : () => perform(
                        repo.reconcileBackupRestore,
                        allowMaintenance: true,
                      ),
                child: const Text('查询恢复结果'),
              ),
            ],
          ),
        ),
      if (data.connected && (busy || page == 'roots'))
        ValueListenableBuilder<String?>(
          valueListenable: repo.scanStatus,
          builder: (context, message, _) => message == null || message == error
              ? const SizedBox()
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      message,
                      key: const Key('scan-status'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!data.connected || !libraryFirst) return legacyBuild(context);
    final primary = ['library', 'tags', 'recent', 'settings'].contains(page);
    return Stack(
      children: [
        Offstage(
          offstage: !primary,
          child: TickerMode(
            enabled: primary,
            child: MediaWorkspace(
              key: ObjectKey(repo.connectionIdentity),
              repository: repo,
              preferences: widget.preferences,
              destination: primary ? page : 'settings',
              active: primary,
              onNavigate: go,
              settings: settings(),
              status: managementStatus(separator: false),
              defaultOrder: entryOrder,
            ),
          ),
        ),
        if (!primary) legacyBuild(context),
      ],
    );
  }

  Widget legacyBuild(BuildContext context) => PopScope<void>(
    canPop: page == 'browse' && !review,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      if (!primaryPage) {
        go('settings');
      } else if (page == 'browse') {
        setState(() => review = false);
      } else {
        go('browse');
      }
    },
    child: AppShell(
      showNavigation: primaryPage,
      navigationEnabled: !_busy || viewing,
      selected: page,
      onNavigate: go,
      destinations: const [
        AppDestination('browse', '浏览', Icons.smart_display_outlined),
        AppDestination('library', '视频库', Icons.grid_view),
        AppDestination('tags', '标签', Icons.sell_outlined),
        AppDestination('settings', '设置', Icons.settings_outlined),
      ],
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (page == 'backup' || page == 'tasks')
            PaperManagementHeader(
              title: title,
              onClose: _busy ? null : () => go('settings'),
            )
          else if (!compactTrashKeyboard)
            SizedBox(
              key: const Key('management-header'),
              height: MediaLayout.headerExtent(context),
              child: Padding(
                padding: EdgeInsets.only(
                  left: page == 'trash' ? 20 : 16,
                  right: 12,
                ),
                child: Row(
                  children: [
                    if (!primaryPage && page != 'trash')
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: iconAction(
                          '返回设置',
                          Icons.arrow_back,
                          _busy ? null : () => go('settings'),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Paper.of(context).title,
                      ),
                    ),
                    if (mediaPage) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: Text(
                          !repo.libraryPreparation.value.ready
                              ? '准备中'
                              : '${data.round.isEmpty ? '00' : (_browsing.position + 1).toString().padLeft(2, '0')} / ${repo.playbackTotal.toString().padLeft(2, '0')}',
                          key: const Key('round-position'),
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 13,
                            color: Paper.of(context).olive,
                          ),
                        ),
                      ),
                      iconAction(
                        '选择文件夹',
                        Icons.folder_outlined,
                        busy ? null : folder,
                      ),
                      iconAction(
                        '播放模式',
                        data.order == PlayOrder.random
                            ? Icons.shuffle
                            : Icons.format_list_numbered,
                        busy ? null : order,
                      ),
                    ],
                    if (page == 'trash')
                      iconAction(
                        '返回设置',
                        Icons.close,
                        _busy ? null : () => go('settings'),
                      ),
                    if (page != 'trash')
                      PopupMenuButton<String>(
                        tooltip: '更多',
                        enabled: !busy,
                        onOpened: () => setState(() => obscured = true),
                        onCanceled: () => setState(() => obscured = false),
                        onSelected: menu,
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_horiz),
                        constraints: const BoxConstraints(minWidth: 190),
                        itemBuilder: (_) => [
                          if (data.lastDelete != null)
                            const PopupMenuItem(
                              value: 'undo',
                              child: Text('撤销上次删除'),
                            ),
                          PopupMenuItem(
                            value: 'theme',
                            child: actionLabel(
                              widget.preferences.dark
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              widget.preferences.dark ? '切换浅色模式' : '切换暗黑模式',
                            ),
                          ),
                          ...(page == 'browse'
                              ? [
                                  if (_browsing.current != null)
                                    const PopupMenuItem(
                                      value: 'tag',
                                      child: Text('打标签'),
                                    ),
                                  if (_browsing.current != null)
                                    const PopupMenuItem(
                                      value: 'details',
                                      child: Text('视频详情'),
                                    ),
                                  PopupMenuItem(
                                    value: 'review',
                                    child: Text(review ? '返回日常浏览' : '进入快速整理'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'round',
                                    child: Text('开始新一轮'),
                                  ),
                                  if (_browsing.current != null)
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        '移入回收站',
                                        style: TextStyle(
                                          color: Paper.of(context).danger,
                                        ),
                                      ),
                                    ),
                                ]
                              : const [
                                  PopupMenuItem(
                                    value: 'roots',
                                    child: Text('媒体目录'),
                                  ),
                                  PopupMenuItem(
                                    value: 'trash',
                                    child: Text('回收站'),
                                  ),
                                  PopupMenuItem(
                                    value: 'backup',
                                    child: Text('备份与恢复'),
                                  ),
                                ]),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          managementStatus(separator: page != 'backup' && page != 'tasks'),
        ],
      ),
      content: Stack(
        fit: StackFit.expand,
        children: [
          switch (page) {
            'browse' => TweenAnimationBuilder<double>(
              key: ValueKey(repo.libraryPreparation.value.ready),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              child: browsing(),
              builder: (_, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
            ),
            'library' => library(),
            'tags' => tags(),
            'settings' => settings(),
            'roots' => roots(),
            'trash' => trash(),
            'backup' => backup(),
            'tasks' => MaintenanceTasksPage(
              repository: repo,
              saveBackup: files.save,
              archiveFiles: widget.backupArchiveFiles,
              onOpenBackup: () => go('backup'),
            ),
            'connection' => connection(),
            _ => const SizedBox(),
          },
          if (_deleteNotice != null || _roundNotice)
            Positioned(top: 8, left: 12, right: 12, child: floatingNotices()),
        ],
      ),
    ),
  );

  Widget floatingNotices() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_deleteNotice != null)
        Container(
          key: const Key('delete-notice'),
          padding: const EdgeInsets.only(left: 16, right: 4),
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh
                .withValues(alpha: .94),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _deleteNotice!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_undoNotice != null)
                TextButton(
                  onPressed: () async {
                    final operation = _undoNotice!;
                    setState(() {
                      _deleteNotice = null;
                      _undoNotice = null;
                    });
                    _deleteNoticeTimer?.cancel();
                    await perform(() async {
                      if (data.lastDelete?.id != operation.id) {
                        throw const LibraryFailure('这次删除已失效，请在回收站查看');
                      }
                      await repo.undoDelete(operationId: operation.id);
                      _browsing.followRepository();
                    });
                  },
                  child: const Text('撤销'),
                ),
              IconButton(
                tooltip: '关闭删除提示',
                iconSize: 18,
                onPressed: () {
                  _deleteNoticeTimer?.cancel();
                  setState(() => _deleteNotice = null);
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      if (_roundNotice)
        Container(
          key: const Key('round-notice'),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh
                .withValues(alpha: .94),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text('本轮已看完', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () async {
                  setState(() => _roundNotice = false);
                  await perform(() async {
                    await repo.newRound();
                    _browsing.followRepository();
                    playerEpoch++;
                  });
                },
                child: const Text('开始新一轮'),
              ),
            ],
          ),
        ),
    ],
  );

  Widget browseCaption(LibraryVideo video) {
    final tags = {...video.tags, ...data.query.tags};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          video.name,
          key: const Key('browse-video-name'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            shadows: [Shadow(blurRadius: 5)],
          ),
        ),
        if (tags.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                for (final tag in tags)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4),
                    child: TextButton(
                      key: Key('filter-tag-$tag'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(40, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        backgroundColor: data.query.tags.contains(tag)
                            ? const Color(0xb353664a)
                            : const Color(0x55000000),
                        side: data.query.tags.contains(tag)
                            ? const BorderSide(color: Colors.white54)
                            : BorderSide.none,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: busy
                          ? null
                          : () => perform(() async {
                              final chosen = {...data.query.tags};
                              chosen.contains(tag)
                                  ? chosen.remove(tag)
                                  : chosen.add(tag);
                              await repo.setScope(
                                data.query.copy(tags: chosen),
                              );
                              _browsing.followRepository();
                              playerEpoch++;
                            }),
                      child: Text(
                        '${data.query.tags.contains(tag) ? '✓' : '#'} ${repo.tagName(tag)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget preparationCard({bool locked = false}) {
    final state = repo.libraryPreparation.value;
    final p = Paper.of(context);
    final active = state.scanning && state.syncError == null;
    String bytes(int count) {
      final unit = count >= 1024 * 1024 * 1024
          ? 1024 * 1024 * 1024
          : 1024 * 1024;
      return '${(count / unit).toStringAsFixed(1)} ${unit == 1024 * 1024 ? 'MB' : 'GB'}';
    }

    return Container(
      key: const Key('library-preparation'),
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.soft.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                locked ? Icons.lock_outline : Icons.folder_copy_outlined,
                size: 20,
                color: p.olive,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  locked ? '视频库正在准备' : '目录扫描',
                  style: p.title.copyWith(fontSize: 20),
                ),
              ),
              if (active)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            state.summary,
            key: const Key('preparation-progress'),
            style: TextStyle(fontSize: 13, color: p.olive),
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          if (state.bytesTotal > 0)
            Text(
              '${bytes(state.bytesProcessed)} / ${bytes(state.bytesTotal)} 已核对',
              style: TextStyle(fontSize: 11, color: p.muted),
            ),
          if (state.failed > 0 ||
              state.thumbnailFailed > 0 ||
              state.deferred > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                [
                  if (state.failed > 0) '${state.failed} 个视频信息读取失败',
                  if (state.thumbnailFailed > 0)
                    '${state.thumbnailFailed} 个缩略图待补充（不影响入库）',
                  if (state.deferred > 0) '${state.deferred} 个等待文件稳定',
                ].join('\n'),
                style: TextStyle(fontSize: 11, color: p.muted),
              ),
            ),
          if (state.failureDetail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                state.failureDetail,
                style: TextStyle(fontSize: 11, color: p.muted, height: 1.5),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            state.syncError ??
                (locked
                    ? '首次扫描完成后自动开放播放。可以先查看目录、标签和设置，进度会自动同步。'
                    : state.scanning
                    ? '已有视频可以继续播放，新增内容在扫描完成后入库。'
                    : '扫描记录保存在服务端，关闭应用不会中断扫描。'),
            style: TextStyle(fontSize: 12, color: p.muted, height: 1.6),
          ),
          if (locked || !state.scanning)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  if (!state.scanning)
                    OutlinedButton(
                      onPressed: busy ? null : () => perform(repo.requestScan),
                      child: const Text('重新扫描'),
                    ),
                  if (locked)
                    TextButton(
                      onPressed: () => go('roots'),
                      child: const Text('查看媒体目录'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String rootScanLabel(MediaRoot root) {
    if (!root.enabled) return '已停用 · 标签与阅读记录保留';
    final state = repo.libraryPreparation.value;
    final detail = state.roots[root.id];
    final scan = detail?['scan'] as Map?;
    if (detail?['available'] == false || !root.available) return '目录暂不可用';
    if (state.scanning && scan != null) {
      if (scan['status'] == 'unavailable') return '目录暂不可用';
      if (scan['status'] == 'discovering') {
        return '正在查找 · 已发现 ${scan['discovered'] ?? 0} 个';
      }
      if (scan['status'] == 'completed') {
        return '本目录已核对 · ${scan['processed'] ?? 0} 个';
      }
      return '正在核对 · ${scan['processed'] ?? 0} / ${scan['discovered'] ?? 0} 个';
    }
    if (detail?['ready'] == false) return '首次扫描尚未完成';
    return '可访问 · ${root.lastScan}';
  }

  Widget rootMetadata(MediaRoot root) {
    final label = rootScanLabel(root);
    final separateDate =
        MediaLayout.largeText(context) && label == '可访问 · ${root.lastScan}';
    return Text(
      '${root.kind == MediaKind.video ? '视频' : '图包'} · ${root.enabled ? '已启用 · ' : ''}${separateDate ? '可访问\n${root.lastScan}' : label}',
      style: TextStyle(
        fontSize: 12,
        height: 1.7,
        color: !root.enabled || root.available
            ? Paper.of(context).catalogMeta
            : Paper.of(context).danger,
      ),
    );
  }

  Widget browsing() {
    if (!repo.libraryPreparation.value.ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: preparationCard(locked: true),
        ),
      );
    }
    final current = _browsing.current;
    return Column(
      children: [
        Expanded(
          child: current == null
              ? EmptyView(
                  data.query.count > 0 ? '没有符合条件的可播放视频' : '当前没有可播放的视频',
                  action: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => perform(() => repo.setScope(VideoQuery())),
                    child: const Text('清除筛选'),
                  ),
                )
              : MovieStage(
                  key: ValueKey('player-$playerEpoch'),
                  videos: [
                    for (final id in data.round)
                      data.videos.firstWhere((video) => video.id == id),
                  ],
                  index: data.position,
                  onStep: step,
                  onUnauthorized: (source) =>
                      unawaited(repo.mediaUnauthorized(source)),
                  suspended: obscured || repo.backupRestorePending,
                  preloadAdjacent: widget.preferences.preloadAdjacent,
                  session: _playback,
                  onPlaybackFailure: (video) async {
                    final message = await repo.playbackFailure(video.source);
                    if (mounted &&
                        page == 'browse' &&
                        message != null &&
                        _browsing.current?.id != video.id) {
                      notice(message);
                    }
                    return message;
                  },
                  footerBuilder: browseCaption,
                ),
        ),
        if (review)
          Container(
            key: const Key('review-actions'),
            padding: const EdgeInsets.fromLTRB(12, 7, 16, 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Paper.of(context).line)),
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: busy ? null : () => scope(quick: true),
                  child: actionLabel(
                    Icons.filter_list,
                    '筛选${data.query.count > 0 ? ' ${data.query.count}' : ''}',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy || current == null
                        ? null
                        : () => tag({current.id}),
                    child: actionLabel(Icons.sell_outlined, '打标签'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('quick-delete'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Paper.of(context).danger,
                    ),
                    onPressed: busy || current == null
                        ? null
                        : () => remove({current.id}),
                    child: actionLabel(Icons.delete_outline, '删除'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget library() {
    final results = libraryItems;
    final total = libraryTotal;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  !repo.libraryPreparation.value.ready
                      ? '建库中 · 已入库 $total 个，数量仍在更新'
                      : libraryLoading && results.isEmpty
                      ? '正在加载…'
                      : '$total 个视频',
                  key: const Key('library-count'),
                  style: TextStyle(
                    color: Paper.of(context).olive,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : libraryFirst
                    ? () => openPreview(quick: true)
                    : () => setState(() {
                        review = true;
                        page = 'browse';
                      }),
                child: const Text('快速整理'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  selecting = !selecting;
                  selected = {};
                }),
                child: Text(selecting ? '取消多选' : '多选'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
          child: Row(
            children: [
              iconAction('筛选视频', Icons.filter_list, () => scope()),
              Expanded(
                child: TextField(
                  key: const Key('video-search'),
                  controller: videoSearch,
                  decoration: const InputDecoration(hintText: '搜索视频'),
                  onChanged: (v) {
                    setState(() {
                      search = v;
                      selected = {};
                    });
                    unawaited(loadLibrary());
                  },
                ),
              ),
              const SizedBox(width: 9),
              OutlinedButton(
                onPressed:
                    busy ||
                        !repo.libraryPreparation.value.ready ||
                        results.isEmpty
                    ? null
                    : libraryFirst
                    ? () => openPreview(anchor: results.first.id)
                    : () async {
                        if (await perform(
                          () => repo.openVideo(results.first.id),
                        )) {
                          go('browse');
                        }
                      },
                child: Text(libraryFirst ? '预览此范围' : '播放'),
              ),
            ],
          ),
        ),
        if (entryQuery.count > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (entryQuery.folder.isNotEmpty) entryQuery.folder,
                      ...entryQuery.tags.map((t) => '# ${repo.tagName(t)}'),
                      if (entryQuery.orientation.isNotEmpty)
                        entryQuery.orientation == 'portrait' ? '竖版' : '横版',
                      if (entryQuery.duration.isNotEmpty)
                        entryQuery.duration == 'short' ? '10 秒以内' : '10 秒以上',
                      entryQuery.type,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: Paper.of(context).olive,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => perform(() => setEntryQuery(VideoQuery())),
                  child: const Text('清除'),
                ),
              ],
            ),
          ),
        if ((_pendingReturn != null || _library.state.beforeFailure) &&
            results.isNotEmpty)
          libraryLoading
              ? const LinearProgressIndicator(minHeight: 2)
              : libraryError.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_pendingReturn != null ? '返回位置未能刷新' : '前面的内容未能加载'}，当前列表已保留：$libraryError',
                        ),
                      ),
                      TextButton(
                        key: const Key('library-return-retry'),
                        onPressed: () =>
                            loadLibrary(before: _library.state.beforeFailure),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        Expanded(
          child: libraryLoading && results.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : libraryError.isNotEmpty && results.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    note(libraryError),
                    TextButton(
                      onPressed: () => loadLibrary(),
                      child: const Text('重试'),
                    ),
                  ],
                )
              : results.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    note(
                      data.roots.isNotEmpty &&
                              data.roots.every((root) => !root.available)
                          ? '媒体目录暂不可用，请检查挂载后刷新'
                          : entryQuery.count > 0 || search.isNotEmpty
                          ? '没有符合条件的视频'
                          : '视频库还是空的',
                    ),
                    TextButton(
                      onPressed: busy ? null : () => perform(repo.requestScan),
                      child: const Text('刷新'),
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: () => perform(repo.requestScan),
                  child: CustomScrollView(
                    key: const Key('video-grid'),
                    controller: libraryScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 18,
                                mainAxisExtent: 290,
                              ),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final v = results[i];
                            return InkWell(
                              key: Key('tile-${v.id}'),
                              onTap:
                                  busy ||
                                      (!selecting &&
                                          !repo.libraryPreparation.value.ready)
                                  ? null
                                  : () async {
                                      if (selecting) {
                                        setState(
                                          () => selected.contains(v.id)
                                              ? selected.remove(v.id)
                                              : selected.add(v.id),
                                        );
                                      } else if (libraryFirst) {
                                        await openPreview(anchor: v.id);
                                      } else if (await perform(
                                        () => repo.openVideo(v.id),
                                      )) {
                                        _browsing.followRepository();
                                        playerEpoch++;
                                        go('browse');
                                      }
                                    },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        MediaPoster(
                                          video: v,
                                          onUnauthorized: () => unawaited(
                                            repo.mediaUnauthorized(v.source),
                                          ),
                                        ),
                                        Positioned(
                                          right: 5,
                                          bottom: 5,
                                          child: Container(
                                            color: Colors.black54,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              timeLabel(
                                                Duration(seconds: v.seconds),
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (selecting)
                                          Positioned(
                                            left: 6,
                                            top: 6,
                                            child: CircleAvatar(
                                              radius: 12,
                                              backgroundColor:
                                                  selected.contains(v.id)
                                                  ? Paper.of(context).olive
                                                  : Paper.of(context)
                                                        .background,
                                              child: Icon(
                                                selected.contains(v.id)
                                                    ? Icons.check
                                                    : Icons.circle_outlined,
                                                size: 18,
                                                color: selected.contains(v.id)
                                                    ? Paper.of(context)
                                                          .background
                                                    : Paper.of(context).olive,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    v.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Paper.of(context).title
                                        .copyWith(fontSize: 14),
                                  ),
                                  Text(
                                    '${v.portrait ? '竖版' : '横版'} · ${v.type}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Paper.of(context).olive,
                                    ),
                                  ),
                                  Text(
                                    v.tags
                                        .map((t) => '# ${repo.tagName(t)}')
                                        .join('   '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Paper.of(context).olive,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 16,
                          ),
                          child: libraryError.isNotEmpty
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        libraryError,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Paper.of(context).muted,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => loadLibrary(
                                        more:
                                            _pendingReturn == null &&
                                            !_library.state.beforeFailure,
                                        before: _library.state.beforeFailure,
                                      ),
                                      child: const Text('重试'),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (libraryLoading) ...[
                                      const SizedBox(
                                        key: Key('library-loading-more'),
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.8,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Text(
                                      libraryLoading
                                          ? '正在加载视频'
                                          : !_library.state.hasAfter
                                          ? '已显示全部视频'
                                          : '继续向下浏览',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Paper.of(context).muted,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (selecting) batchBar(),
      ],
    );
  }

  Widget batchBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '已选 ${selected.length}',
            style: TextStyle(fontSize: 12, color: Paper.of(context).olive),
          ),
        ),
        TextButton(
          onPressed: busy || libraryLoading || selected.isEmpty
              ? null
              : () => tag(selected),
          child: const Text('打标签'),
        ),
        TextButton(
          onPressed: busy || libraryLoading || selected.isEmpty
              ? null
              : () => remove(selected),
          style: TextButton.styleFrom(
            foregroundColor: Paper.of(context).danger,
          ),
          child: const Text('移入回收站'),
        ),
      ],
    ),
  );
  Widget tags() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索标签',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => tagSearch = v),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: busy ? null : () => tagForm(),
              child: const Text('新建标签'),
            ),
          ],
        ),
      ),
      Expanded(
        child: data.tags.isEmpty
            ? const EmptyView('还没有标签')
            : ListView(
                children: data.tags
                    .where((t) => repo.tagName(t).contains(tagSearch))
                    .map(
                      (t) => ListTile(
                        leading: Text(
                          '#',
                          style: TextStyle(
                            color: Paper.of(context).olive,
                            fontSize: 19,
                          ),
                        ),
                        title: Text(
                          repo.tagName(t),
                          style: Paper.of(context).title.copyWith(fontSize: 17),
                        ),
                        subtitle: Text('${repo.tagVideoCount(t)} 个视频'),
                        onTap: busy
                            ? null
                            : () async {
                                if (libraryFirst) {
                                  setState(() {
                                    libraryContext = VideoBrowseContext(
                                      query: VideoQuery(tags: {t}),
                                      source: BrowseSource.tags,
                                      sort: VideoSort.name,
                                    );
                                    search = '';
                                    videoSearch.clear();
                                  });
                                  go('library');
                                  return;
                                }
                                if (await perform(
                                  () =>
                                      repo.setScope(data.query.copy(tags: {t})),
                                )) {
                                  go('library');
                                }
                              },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            iconAction(
                              '重命名标签 ${repo.tagName(t)}',
                              Icons.edit_outlined,
                              () => tagForm(t),
                            ),
                            iconAction(
                              '删除标签 ${repo.tagName(t)}',
                              Icons.close,
                              () async {
                                if (await confirm(
                                  '删除这个标签？',
                                  '将解除「${repo.tagName(t)}」与视频的关联，不会删除视频。',
                                  '删除标签',
                                )) {
                                  await perform(
                                    () =>
                                        repo.editTag(original: t, delete: true),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );
  Future<void> tagForm([String? original]) async {
    final input = TextEditingController(
      text: original == null ? '' : repo.tagName(original),
    );
    String formError = '';
    bool saving = false;
    await sheet<void>(
      StatefulBuilder(
        builder: (context, local) => SheetFrame(
          title: original == null ? '新建标签' : '重命名标签',
          children: [
            const SizedBox(height: 12),
            TextField(
              key: const Key('tag-name'),
              controller: input,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '标签名称'),
            ),
            if (formError.isNotEmpty) note(formError),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      local(() {
                        saving = true;
                        formError = '';
                      });
                      try {
                        await repo.editTag(
                          original: original,
                          name: input.text,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          local(() => formError = e.toString());
                        }
                      } finally {
                        if (context.mounted) local(() => saving = false);
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
  }

  Widget settingRow(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action, {
    bool allowDuringRestore = false,
  }) {
    final p = Paper.of(context);
    final enabled =
        !_busy && (allowDuringRestore || !repo.backupRestorePending);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: InkWell(
        onTap: enabled ? action : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, height: 23 / 15),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.7,
                            color: p.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                const Icon(Icons.chevron_right, size: 19),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget settingsHeading(String label, {bool first = false}) => Padding(
    padding: EdgeInsets.only(top: first ? 8 : 18, bottom: 6),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        height: 18.5 / 13,
        color: Paper.of(context).muted,
      ),
    ),
  );
  Widget settings() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      settingsHeading('连接与文件', first: true),
      settingRow(
        Icons.link,
        '服务连接',
        '${data.address}:${data.port}',
        () => go('connection'),
        allowDuringRestore: true,
      ),
      settingRow(
        Icons.folder_outlined,
        '媒体目录',
        repo.capabilities.typedRoots
            ? '${data.roots.length} 个目录 · 视频与图包分别接入'
            : '${data.roots.length} 个目录 · ${repo.missingCount} 个缺失视频',
        () => go('roots'),
      ),
      settingsHeading('数据维护'),
      settingRow(
        Icons.delete_outline,
        '回收站',
        repo.capabilities.packLogicalTrash
            ? '视频与图包分别管理 · 不会自动清空'
            : '${repo.trashCount} 个视频 · 不会自动清空',
        () => go('trash'),
      ),
      settingRow(
        Icons.save_outlined,
        '备份与恢复',
        repo.capabilities.backupV2 ? '标签、目录映射、回收站与阅读记录' : '导出标签和管理记录',
        () => go('backup'),
        allowDuringRestore: true,
      ),
      settingRow(
        Icons.history,
        '操作任务',
        (repo.maintenancePendingCount ?? 0) > 0
            ? '${repo.maintenancePendingCount} 项结果待核对'
            : repo.maintenanceNeedsCheck
            ? '有操作记录需要核对'
            : '扫描、恢复与删除结果',
        () => go('tasks'),
        allowDuringRestore: true,
      ),
      settingsHeading('偏好'),
      PaperPreferenceSwitch(
        key: const Key('dark-mode-setting'),
        icon: Icons.dark_mode_outlined,
        title: '暗黑模式',
        value: widget.preferences.dark,
        onChanged: busy
            ? null
            : (value) => perform(() => widget.preferences.setDark(value)),
      ),
      const Divider(height: 1),
      PaperPreferenceSwitch(
        key: const Key('preload-setting'),
        icon: Icons.slow_motion_video,
        title: '准备相邻视频',
        subtitle: '前后各一条；关闭可减少网络与解码占用',
        value: widget.preferences.preloadAdjacent,
        onChanged: busy
            ? null
            : (value) =>
                  perform(() => widget.preferences.setPreloadAdjacent(value)),
      ),
      const Divider(height: 1),
      settingRow(
        Icons.shuffle,
        libraryFirst ? '默认播放顺序' : '播放顺序',
        libraryFirst && repo.capabilities.managedPlaybackDefaults
            ? '保存在服务端 · 只影响新预览范围'
            : (libraryFirst ? entryOrder : data.order) == PlayOrder.random
            ? '随机播放'
            : '顺序播放',
        order,
      ),
      if (repo.capabilities.packReadingSessions)
        settingRow(
          Icons.menu_book_outlined,
          '阅读偏好',
          '默认阅读方式 · 每包单独记忆',
          () => sheet<void>(
            DefaultSettingsSheet(
              repository: repo,
              local: widget.preferences,
              video: false,
            ),
          ),
        ),
      if (kDebugMode && repo is DemoControls) ...[
        const SizedBox(height: 26),
        note('开发工具'),
        settingRow(
          Icons.science_outlined,
          '演示场景',
          '复位演示数据并切换可重复的状态',
          scenarios,
        ),
      ],
    ],
  );
  Widget connection() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (!data.connected) Text('连接你的视频库', style: Paper.of(context).title),
      note('视频和图包共用同一媒体服务。'),
      const SizedBox(height: 12),
      PaperField(
        label: '服务地址',
        child: TextField(
          key: const Key('connection-address'),
          controller: address,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(),
        ),
      ),
      const SizedBox(height: 20),
      PaperField(
        label: '端口',
        child: TextField(
          key: const Key('connection-port'),
          controller: port,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(),
        ),
      ),
      const SizedBox(height: 20),
      PaperField(
        label: '个人口令',
        child: TextField(
          key: const Key('connection-passphrase'),
          controller: passphrase,
          enabled: !_busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(),
        ),
      ),
      note('口令不进入管理数据备份。'),
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('connection-save'),
        onPressed: _busy
            ? null
            : () async {
                if (await perform(
                  () => repo.connect(
                    address.text,
                    int.tryParse(port.text) ?? 0,
                    passphrase.text,
                  ),
                  allowMaintenance: true,
                )) {
                  passphrase.clear();
                  go(repo.backupRestorePending ? 'backup' : landing);
                }
              },
        child: Text(
          _busy
              ? '正在连接…'
              : data.connected
              ? '连接并保存'
              : '连接',
        ),
      ),
    ],
  );
  bool get rootScanNeedsAttention {
    final state = repo.libraryPreparation.value;
    return !state.ready ||
        state.scanning ||
        state.syncError != null ||
        state.failed > 0 ||
        state.thumbnailFailed > 0 ||
        state.deferred > 0 ||
        state.failureDetail.isNotEmpty;
  }

  Widget roots() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    children: [
      if (repo is! DemoControls && rootScanNeedsAttention) ...[
        preparationCard(),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(child: note('扫描包含子目录')),
          TextButton(
            onPressed: busy ? null : () => rootForm(),
            child: const Text('添加目录'),
          ),
        ],
      ),
      for (final r in data.roots)
        Container(
          key: Key('root-${r.id}'),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Paper.of(context).line)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: Paper.of(context).title
                          .copyWith(fontSize: 15, height: 1.6),
                    ),
                    Text(
                      r.path,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.7,
                        color: Paper.of(context).catalogMeta,
                      ),
                    ),
                    rootMetadata(r),
                  ],
                ),
              ),
              iconAction(
                '编辑目录 ${r.name}',
                Icons.edit_outlined,
                busy ? null : () => rootForm(r),
              ),
            ],
          ),
        ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: busy || repo.libraryPreparation.value.scanning
            ? null
            : () async {
                if (await perform(repo.requestScan)) notice('扫描已提交，进度会自动同步');
              },
        child: actionLabel(
          Icons.refresh,
          repo.libraryPreparation.value.scanning ? '同步进行中' : '同步外部变更',
        ),
      ),
      if (repo is! DemoControls && !rootScanNeedsAttention)
        ExpansionTile(
          key: const Key('root-scan-details'),
          tilePadding: EdgeInsets.zero,
          title: Text(
            repo.libraryPreparation.value.summary,
            key: const Key('root-scan-summary'),
            style: TextStyle(
              fontSize: 13,
              color: Paper.of(context).catalogMeta,
            ),
          ),
          children: [preparationCard()],
        ),
      if (repo.capabilities.packMissingCleanup)
        settingRow(
          Icons.broken_image_outlined,
          '缺失内容',
          '视频与图包分别核对 · 离线和停用目录保留记录',
          () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => MissingMediaPage(repository: repo),
              ),
            );
          },
        ),
      if (!repo.capabilities.packMissingCleanup &&
          (missingTotal > 0 || missingItems.isNotEmpty)) ...[
        const SizedBox(height: 30),
        Text('缺失视频', style: Paper.of(context).title.copyWith(fontSize: 20)),
        note('保留标签记录，重新找到同一文件后继续关联。'),
        TextButton(
          key: const Key('forget-missing'),
          onPressed: cleaningMissing || repo.libraryPreparation.value.scanning
              ? null
              : clearMissing,
          child: Text(cleaningMissing ? '正在清理…' : '清除失效记录 ($missingTotal)'),
        ),
        for (final v in missingItems)
          ListTile(
            key: Key('missing-${v.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(v.name),
            subtitle: Text(
              '${v.path}\n${v.tags.map(repo.tagName).join(' · ')}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              '缺失',
              style: TextStyle(color: Paper.of(context).danger),
            ),
          ),
        if (missingItems.length < missingTotal)
          TextButton(
            onPressed: missingLoading ? null : () => loadMissing(more: true),
            child: const Text('加载更多缺失视频'),
          ),
      ],
      if (missingLoading) const LinearProgressIndicator(),
      if (missingError.isNotEmpty) ...[
        note(missingError),
        TextButton(
          onPressed: () => loadMissing(),
          child: const Text('重试读取缺失记录'),
        ),
      ],
      note('图包目录的直属文件夹识别为包，包内递归读取图片；不会改变源文件位置。'),
      const SizedBox(height: 20),
    ],
  );
  Future<void> rootForm([MediaRoot? root]) =>
      sheet<void>(MediaRootSheet(repository: repo, root: root));

  Future<void> queryFileResult() async {
    if (queryingFiles) return;
    setState(() => queryingFiles = true);
    try {
      await repo.reconcileFileOperation();
      if (mounted) {
        notice(repo.fileOperationPending ? '任务仍在后台处理，可继续浏览' : '结果已同步');
      }
    } on RequestCancelled {
      return;
    } catch (e) {
      notice(e.toString());
    } finally {
      if (mounted) setState(() => queryingFiles = false);
    }
  }

  Future<void> clearMissing() async {
    if (!await confirm(
      '清除失效视频记录？',
      '只清除扫描已确认缺失的记录及标签关联，不删除任何磁盘文件。暂时离线的目录不会清理；清理后找回视频不会恢复原标签。',
      '清除记录',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => cleaningMissing = true);
    try {
      final count = await repo.forgetMissingVideos();
      _browsing.followRepository();
      if (mounted && page == 'roots') await loadMissing();
      notice('已清除 $count 条失效记录');
    } catch (e) {
      notice(e.toString());
    } finally {
      if (mounted) setState(() => cleaningMissing = false);
    }
  }

  Future<void> purgeTrash(Set<String> ids) async {
    if (purgingTrash) return;
    setState(() => purgingTrash = true);
    try {
      await repo.permanentlyDelete(ids);
      if (!mounted) return;
      setState(() => selected.removeAll(ids));
      if (page == 'trash') await loadTrash();
      notice('已永久删除');
    } on RequestCancelled {
      return;
    } catch (e) {
      notice('删除结果待确认：$e');
    } finally {
      if (mounted) setState(() => purgingTrash = false);
    }
  }

  Future<void> selectAllTrash() async {
    if (selectingAllTrash || restoringTrash || purgingTrash || trashLoading) {
      return;
    }
    if (selected.length == trashTotal && trashTotal > 0) {
      setState(() => selected.clear());
      return;
    }
    final generation = ++trashGeneration;
    setState(() => selectingAllTrash = true);
    try {
      final all = <LibraryVideo>[];
      var total = trashTotal;
      do {
        final batch = await repo.loadTrash(offset: all.length, limit: 200);
        if (!mounted || page != 'trash' || generation != trashGeneration) {
          return;
        }
        all.addAll(batch.items);
        total = batch.total;
        if (batch.items.isEmpty) break;
      } while (all.length < total);
      setState(() {
        trashItems = all;
        trashTotal = total;
        selected = all.map((v) => v.id).toSet();
      });
    } on RequestCancelled {
      return;
    } catch (e) {
      notice('全选未完成：$e');
    } finally {
      if (mounted) setState(() => selectingAllTrash = false);
    }
  }

  Future<void> restoreSelectedTrash({Set<String>? only}) async {
    final ids = {...?only, if (only == null) ...selected};
    if (restoringTrash || purgingTrash || ids.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => restoringTrash = true);
    try {
      final failures = await repo.restoreVideos(ids);
      if (!mounted) return;
      setState(() {
        selected.removeAll(ids);
        error = failures.join('\n');
      });
      if (page == 'trash') await loadTrash();
      if (failures.isEmpty) notice('已恢复，标签保留');
    } on RequestCancelled {
      return;
    } catch (e) {
      notice('恢复结果待确认：$e');
    } finally {
      if (mounted) setState(() => restoringTrash = false);
    }
  }

  Widget trash() {
    if (!repo.capabilities.packLogicalTrash || !repo.capabilities.imagePacks) {
      return videoTrash();
    }
    final p = Paper.of(context);
    return Column(
      children: [
        if (!compactTrashKeyboard)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                for (final kind in MediaKind.values)
                  Padding(
                    padding: EdgeInsets.zero,
                    child: TextButton(
                      key: Key('trash-kind-${kind.name}'),
                      onPressed: () {
                        if (trashKind == kind) return;
                        setState(() => trashKind = kind);
                        trashGeneration++;
                        repo.cancelTrashRead();
                        if (kind == MediaKind.video) unawaited(loadTrash());
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: kind == trashKind
                            ? p.ink
                            : p.catalogMeta,
                        padding: const EdgeInsets.only(right: 22),
                        alignment: Alignment.centerLeft,
                        textStyle: TextStyle(
                          fontSize: 15,
                          fontWeight: kind == trashKind
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        minimumSize: const Size(44, 44),
                        shape: const RoundedRectangleBorder(),
                        side: BorderSide.none,
                      ),
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: kind == trashKind
                                  ? p.olive
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(kind == MediaKind.video ? '视频' : '图包'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: IndexedStack(
            index: trashKind == MediaKind.video ? 0 : 1,
            children: [
              videoTrash(),
              PackTrashPage(
                repository: repo,
                active: trashKind == MediaKind.pack,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget videoTrash() {
    final p = Paper.of(context);
    final locked = busy || restoringTrash || purgingTrash || selectingAllTrash;
    return TrashLayout(
      listKey: const Key('video-trash-list'),
      topInset:
          repo.capabilities.packLogicalTrash && repo.capabilities.imagePacks
          ? 0
          : 18,
      loading:
          trashLoading || restoringTrash || purgingTrash || selectingAllTrash,
      onRefresh: () => loadTrash(),
      actions: TrashActions(
        count: selected.length,
        restoreKey: const Key('video-trash-restore'),
        permanentKey: const Key('video-trash-permanent'),
        onRestore: locked || selected.isEmpty ? null : restoreSelectedTrash,
        onPermanent: locked || selected.isEmpty
            ? null
            : () async {
                final ids = {...selected};
                if (await confirm(
                  '永久删除这些视频？',
                  '将永久删除所选 ${ids.length} 个视频，无法撤销。',
                  '永久删除',
                )) {
                  await purgeTrash(ids);
                }
              },
        restoring: restoringTrash,
      ),
      children: [
        Text(
          '只作标记，原文件仍在原位置；恢复时保留标签。不会自动清空。',
          style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
        ),
        if (trashError.isNotEmpty) ...[
          Text(trashError, style: TextStyle(height: 1.7, color: p.danger)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('video-trash-retry'),
              onPressed: trashLoading ? null : () => loadTrash(),
              child: const Text('重试'),
            ),
          ),
        ],
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              trashItems.isNotEmpty || (!trashLoading && trashError.isEmpty)
                  ? '共 $trashTotal 个视频'
                  : '视频回收站',
              style: TextStyle(fontSize: 12, color: p.catalogMeta),
            ),
            TextButton(
              key: const Key('trash-select-all'),
              onPressed: locked || trashLoading ? null : selectAllTrash,
              child: Text(
                selectingAllTrash
                    ? '正在全选…'
                    : selected.length == trashTotal && trashTotal > 0
                    ? '取消全选'
                    : '全选',
              ),
            ),
          ],
        ),
        if (restoringTrash || purgingTrash)
          ValueListenableBuilder<String?>(
            valueListenable: repo.fileStatus,
            builder: (_, status, _) => Text(
              status ?? (purgingTrash ? '正在删除，可继续浏览' : '正在恢复，可继续浏览'),
              style: TextStyle(fontSize: 12, height: 1.7, color: p.catalogMeta),
            ),
          ),
        if (trashItems.isEmpty && !trashLoading && trashError.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('回收站是空的', textAlign: TextAlign.center),
          ),
        for (final v in trashItems)
          TrashEntryRow(
            key: Key('trash-${v.id}'),
            title: v.displayTitle,
            path: v.originalPath ?? v.path,
            selected: selected.contains(v.id),
            onToggle: locked
                ? null
                : () => setState(
                    () => selected.contains(v.id)
                        ? selected.remove(v.id)
                        : selected.add(v.id),
                  ),
            restoreKey: Key('video-trash-row-restore-${v.id}'),
            onRestore: locked ? null : () => restoreSelectedTrash(only: {v.id}),
          ),
        if (trashItems.length < trashTotal)
          TextButton(
            onPressed: trashLoading ? null : () => loadTrash(more: true),
            child: Text(trashLoading ? '正在加载…' : '加载更多'),
          ),
      ],
    );
  }

  Widget backup() {
    final Object archives = repo;
    if (archives is ManagementArchiveRepository &&
        archives.archiveBackupsAvailable) {
      return ArchiveBackupPage(
        key: ObjectKey(repo.connectionIdentity),
        repository: repo,
        archives: archives,
        files: widget.backupArchiveFiles,
        onOpenTasks: () => go('tasks'),
      );
    }
    return legacyBackup();
  }

  Widget legacyBackup() {
    final p = Paper.of(context);
    return ListView(
      key: const PageStorageKey('legacy-backup-content'),
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 22),
      children: [
        const Text('保存你的整理成果', style: TextStyle(fontSize: 14, height: 1.6)),
        const SizedBox(height: 12),
        Text(
          '备份视频标签与关联、目录映射、回收站索引和播放轮次。不包含媒体文件与个人口令。',
          style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: repo.backupStatus,
          builder: (context, message, _) => message == null
              ? const SizedBox()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    message,
                    key: const Key('backup-status'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: p.catalogMeta,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 20),
        PaperActionRow(
          key: const Key('backup-export'),
          title: '导出备份',
          trailing: const Icon(Icons.keyboard_arrow_down, size: 20),
          onTap: busy
              ? null
              : () async {
                  bool saved = false;
                  if (await perform(
                    () async =>
                        saved = await files.save(await repo.exportBackupFile()),
                  )) {
                    notice(saved ? '已导出管理数据备份' : '保存已取消，可在操作任务下载原备份');
                  }
                },
        ),
        PaperActionRow(
          key: const Key('backup-pick'),
          title: '选择备份文件',
          onTap: busy
              ? null
              : () async {
                  String? text;
                  BackupPreview? preview;
                  if (await perform(() async {
                        text = await files.open();
                        if (text != null) {
                          preview = await repo.inspectBackupFile(text!);
                        }
                      }) &&
                      text != null &&
                      preview != null) {
                    await restoreForm(text!, preview!);
                  }
                },
        ),
        const SizedBox(height: 24),
        Text(
          '先校验，再核对目录映射。恢复前保留当前管理数据快照。已永久删除的源文件不会从备份恢复，也不会回滚磁盘上的文件移动。',
          style: TextStyle(fontSize: 13, height: 1.8, color: p.catalogMeta),
        ),
      ],
    );
  }

  Future<void> restoreForm(String text, BackupPreview preview) async {
    if (!mounted) return;
    final mappings = {
      for (final r in preview.snapshot.roots)
        r.id: preview.suggestedMappings.containsKey(r.id)
            ? preview.suggestedMappings[r.id] ?? ''
            : r.path,
    };
    bool checked = false, restoring = false;
    String formError = '';
    final errorAnchor = GlobalKey();
    await sheet<void>(
      StatefulBuilder(
        builder: (context, local) => PopScope(
          canPop: !restoring,
          child: SheetFrame(
            title: '恢复备份',
            closeEnabled: !restoring,
            footer: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('restore-cancel'),
                  onPressed: restoring ? null : () => Navigator.pop(context),
                  child: Text(repo.backupRestorePending ? '关闭' : '取消'),
                ),
                FilledButton(
                  key: const Key('restore-submit'),
                  onPressed:
                      restoring || (!checked && !repo.backupRestorePending)
                      ? null
                      : () async {
                          if (!repo.backupRestorePending && !checked) {
                            local(() => formError = '请确认替换现有管理数据');
                            return;
                          }
                          local(() {
                            restoring = true;
                            formError = '';
                          });
                          final completed = await perform(() async {
                            if (repo.backupRestorePending) {
                              await repo.reconcileBackupRestore();
                            } else {
                              await repo.restoreBackup(text, mappings);
                            }
                          }, allowMaintenance: true);
                          if (!context.mounted) return;
                          if (completed) {
                            Navigator.pop(context);
                            notice('管理数据已恢复');
                          } else {
                            local(() => formError = error);
                            revealFormError(errorAnchor);
                          }
                          if (context.mounted) local(() => restoring = false);
                        },
                  child: Text(
                    restoring
                        ? '正在恢复…'
                        : repo.backupRestorePending
                        ? '查询恢复结果'
                        : '确认恢复',
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '校验通过。请核对媒体目录映射，恢复前将保留当前数据快照。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: Paper.of(context).catalogMeta,
                  ),
                ),
              ),
              if (preview.counts.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Paper.of(context).soft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '视频 ${preview.counts['videos'] ?? 0} · 标签 ${preview.counts['tags'] ?? 0} · 回收站 ${preview.counts['trash_items'] ?? 0}',
                    style: const TextStyle(fontSize: 13, height: 1.7),
                  ),
                ),
              for (final r in preview.snapshot.roots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PaperField(
                        label:
                            '${r.name} · ${r.kind == MediaKind.pack ? '图包' : '视频'}',
                        child: TextFormField(
                          key: Key('mapping-${r.id}'),
                          initialValue: mappings[r.id],
                          enabled: !restoring && !repo.backupRestorePending,
                          maxLines: null,
                          scrollPhysics: const NeverScrollableScrollPhysics(),
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            hintText: preview.importId == null
                                ? null
                                : '留空表示暂不映射',
                          ),
                          onChanged: (value) => mappings[r.id] = value,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '原目录：${r.path}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.7,
                          color: Paper.of(context).catalogMeta,
                        ),
                      ),
                    ],
                  ),
                ),
              CheckboxListTile(
                key: const Key('restore-confirm'),
                contentPadding: EdgeInsets.zero,
                value: checked,
                onChanged: restoring || repo.backupRestorePending
                    ? null
                    : (v) => local(() => checked = v!),
                title: const Text(
                  '我知道恢复会替换现有管理数据',
                  style: TextStyle(fontSize: 13, height: 1.8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '恢复不会回滚磁盘文件删除，也不修改连接口令、本机暗黑模式和相邻视频准备。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: Paper.of(context).catalogMeta,
                  ),
                ),
              ),
              if (formError.isNotEmpty)
                Text(
                  formError,
                  key: errorAnchor,
                  style: TextStyle(
                    color: Paper.of(context).danger,
                    height: 1.7,
                  ),
                ),
            ],
          ),
        ),
      ),
      dismissible: false,
    );
  }

  Future<void> scenarios() async {
    final controls = repo is DemoControls ? repo as DemoControls : null;
    if (controls == null) return;
    final chosen = await sheet<DemoScenario>(
      SheetFrame(
        title: '演示场景',
        children: [
          note('切换会复位本 App 的演示数据，不会读写 NAS。'),
          for (final entry in <DemoScenario, String>{
            DemoScenario.normal: '正常 / 复位',
            DemoScenario.empty: '空视频库',
            DemoScenario.offline: '服务不可达',
            DemoScenario.unavailable: '媒体目录不可用',
            DemoScenario.writeFailure: '文件操作失败',
            DemoScenario.storageFailure: '保存失败',
            DemoScenario.conflict: '恢复同名冲突',
            DemoScenario.changedFiles: '外部改名、移动与找回',
            DemoScenario.identityConflict: '同路径替换与重复副本',
          }.entries)
            ListTile(
              title: Text(entry.value),
              onTap: () => Navigator.pop(context, entry.key),
            ),
        ],
      ),
    );
    if (chosen != null &&
        await perform(() => controls.reset(scenario: chosen))) {
      setState(() {
        review = false;
        selected = {};
        search = '';
        videoSearch.clear();
        error = '';
        _browsing.followRepository();
        playerEpoch++;
        page = chosen == DemoScenario.offline ? 'connection' : 'browse';
      });
      notice('演示数据已复位');
    }
  }
}
