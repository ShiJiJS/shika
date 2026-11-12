import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/media_layout.dart';
import '../../ui/media_history.dart';
import '../../ui/paper.dart';
import '../packs/pack_sheets.dart';
import '../packs/pack_reader_page.dart';
import '../packs/pack_file_action.dart';
import 'browse_context.dart';
import 'catalog_selection.dart';
import 'pack_query_controller.dart';

class PackCover extends StatefulWidget {
  const PackCover({
    super.key,
    required this.pack,
    required this.repository,
    this.active = true,
  });
  final LibraryPack pack;
  final LibraryRepository repository;
  final bool active;
  @override
  State<PackCover> createState() => _PackCoverState();
}

class _PackCoverState extends State<PackCover> {
  int attempt = 0;
  Timer? retry;
  bool reloading = false;
  Future<void> reload() async {
    retry?.cancel();
    retry = null;
    if (reloading) return;
    final source = widget.pack.cover;
    if (source == null) return;
    reloading = true;
    try {
      if (!source.asset) {
        await NetworkImage(source.location, headers: source.headers).evict();
      }
      if (mounted &&
          widget.active &&
          widget.pack.cover?.location == source.location) {
        setState(() => attempt++);
      }
    } finally {
      reloading = false;
    }
  }

  @override
  void didUpdateWidget(PackCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active ||
        oldWidget.pack.cover?.location != widget.pack.cover?.location) {
      retry?.cancel();
      retry = null;
    }
    if (oldWidget.pack.cover?.location != widget.pack.cover?.location) {
      attempt = 0;
    }
  }

  @override
  void dispose() {
    retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.pack.cover;
    if (source == null) {
      return ColoredBox(
        color: Paper.of(context).soft,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.collections_outlined),
              const SizedBox(height: 6),
              Text(
                '暂无封面',
                style: TextStyle(fontSize: 11, color: Paper.of(context).muted),
              ),
            ],
          ),
        ),
      );
    }
    Widget failure(BuildContext context, Object error, StackTrace? trace) {
      if (error is NetworkImageLoadException && error.statusCode == 401) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(widget.repository.mediaUnauthorized(source)),
        );
      }
      if (widget.active &&
          error is NetworkImageLoadException &&
          (error.statusCode == 503 || error.statusCode == 429) &&
          attempt < 2 &&
          retry == null &&
          !reloading) {
        retry = Timer(
          Duration(milliseconds: 400 * (attempt + 1)),
          () => unawaited(reload()),
        );
      }
      return ColoredBox(
        color: Paper.of(context).soft,
        child: Center(
          child: IconButton(
            tooltip: '重新加载封面',
            onPressed: reloading ? null : () => unawaited(reload()),
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }

    return source.asset
        ? Image.asset(source.location, fit: BoxFit.cover, errorBuilder: failure)
        : Image.network(
            source.location,
            key: ValueKey('${source.location}-$attempt'),
            headers: source.headers,
            fit: BoxFit.cover,
            errorBuilder: failure,
          );
  }
}

class PackCatalogPage extends StatefulWidget {
  const PackCatalogPage({
    super.key,
    required this.repository,
    required this.entry,
    required this.active,
    this.onResumeReading,
  });
  final Future<void> Function(PackCleanupContext, String)? onResumeReading;
  final LibraryRepository repository;
  final PackBrowseContext entry;
  final bool active;
  @override
  State<PackCatalogPage> createState() => PackCatalogPageState();
}

class PackCatalogPageState extends State<PackCatalogPage> {
  LibraryRepository get repo => widget.repository;
  late final catalog = PackQueryController(repo);
  late PackBrowseContext entry = widget.entry;
  late final search = TextEditingController(text: entry.query.search);
  final scroll = ScrollController();
  late final selection = CatalogSelection(
    connection: () => repo.connectionIdentity,
    cancelRead: repo.cancelPackSelection,
  );
  Set<String> get selected => selection.ids;
  late Object selectionConnection = repo.connectionIdentity;
  bool selecting = false, initialized = false, dirty = false, busy = false;
  bool _positioning = false, _detailsOpen = false, _refreshScheduled = false;
  int generation = 0;
  double width = 390;
  MediaGridGeometry? _geometry;
  ({String id, double inset, bool top, int generation})? _reflow;
  int _layoutRevision = 0;
  PackBrowseContext? pendingReturn;
  List<String> returnIds = const [];
  String error = '';
  List<PackFileCommand> pendingFiles = const [];
  int _pendingFilesRead = 0;
  LibraryPack? continuation;
  String continuationError = '';
  bool continuationLoading = false;
  bool get continuationEligible =>
      entry.source == BrowseSource.library &&
      entry.query.count == 0 &&
      entry.query.search.isEmpty &&
      !selecting &&
      repo.capabilities.packReadingSessions;
  bool get hasContinuation =>
      continuationEligible &&
      (continuation != null || continuationError.isNotEmpty);
  String get continuationPosition {
    final pack = continuation, index = pack?.progress?.pageIndex;
    return pack == null
        ? ''
        : index == null
        ? '续读位置待确认 · ${pack.pageCount} 张'
        : '第 ${index + 1} / ${pack.pageCount} 张';
  }

  double get continuationExtent => MediaLayout.continuation(
    context,
    title: continuation?.displayTitle ?? '续读位置暂不可用',
    position: continuationPosition,
  );
  PackLibraryState get data => catalog.state;
  bool get recent => entry.source == BrowseSource.recent;
  int get columns => _geometry?.columns ?? (recent ? 1 : 2);
  double get stride => _geometry?.stride ?? _strideValue;
  double get _strideValue => recent
      ? _historyStride
      : MediaLayout.tile(context, width) + MediaLayout.rowGap;
  double get listHeader => _geometry?.header ?? _listHeaderValue;
  double get _listHeaderValue => recent
      ? MediaLayout.historyHeader(context)
      : (selecting ? 0 : MediaLayout.toolbar(context)) +
            (hasContinuation ? continuationExtent : 0) +
            (entry.query.count > 0 || entry.query.search.isNotEmpty
                ? MediaLayout.scope(context)
                : 0);

  void layoutGrid(BuildContext context, double nextWidth) {
    final next = MediaGridGeometry(
      recent ? 1 : MediaLayout.columns(context),
      recent
          ? _strideValue
          : MediaLayout.tile(context, nextWidth) + MediaLayout.rowGap,
      _listHeaderValue,
    );
    final old = _geometry;
    if (old != null &&
        (old.reflows(next) || (recent && old.header != next.header)) &&
        _reflow == null &&
        !_positioning &&
        !_detailsOpen &&
        scroll.hasClients &&
        data.items.isNotEmpty) {
      final saved = position();
      _reflow = (
        id: saved.ids.first,
        inset: saved.context.scrollInset,
        top: saved.context.scrollOffset == 0,
        generation: generation,
      );
    }
    width = nextWidth;
    _geometry = next;
    if (_reflow == null) return;
    final revision = ++_layoutRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _layoutRevision) return;
      final saved = _reflow;
      _reflow = null;
      if (saved == null ||
          saved.generation != generation ||
          _positioning ||
          _detailsOpen ||
          !scroll.hasClients) {
        return;
      }
      final index = data.items.indexWhere((item) => item.id == saved.id);
      if (index < 0) return;
      final inset = saved.inset < 0
          ? saved.inset
          : min(saved.inset, stride - 1);
      final pixels = saved.top
          ? 0.0
          : listHeader + index ~/ columns * stride + inset;
      scroll.jumpTo(pixels.clamp(0.0, scroll.position.maxScrollExtent));
      nearBottom();
    });
  }

  @override
  void initState() {
    super.initState();
    catalog.addListener(changed);
    repo.addListener(repositoryChanged);
    selection.addListener(changed);
    scroll.addListener(nearBottom);
    if (widget.active) scheduleLoad();
  }

  void scheduleLoad({bool restore = false}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && !busy && !_detailsOpen) {
          unawaited(load(restore: restore));
        }
      });
  @override
  void didUpdateWidget(PackCatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.queryKey != widget.entry.queryKey) {
      entry = widget.entry;
      search.text = entry.query.search;
      selection.cancel(clear: true);
      initialized = false;
      continuation = null;
      continuationError = '';
      continuationLoading = false;
      pendingFiles = const [];
      _pendingFilesRead++;
      generation++;
      pendingReturn = null;
      returnIds = const [];
      if (widget.active) scheduleLoad();
    } else if (oldWidget.active != widget.active) {
      if (!widget.active) {
        generation++;
        remember();
        selection.cancel();
        catalog.cancel();
      } else if (!initialized || dirty || pendingReturn != null) {
        scheduleLoad(restore: initialized);
      }
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void repositoryChanged() {
    if (!identical(selectionConnection, repo.connectionIdentity)) {
      selectionConnection = repo.connectionIdentity;
      continuation = null;
      continuationError = '';
      continuationLoading = false;
      pendingFiles = const [];
      _pendingFilesRead++;
      selection.cancel(clear: true);
      generation++;
      pendingReturn = null;
      returnIds = const [];
      initialized = false;
      entry = PackBrowseContext(query: entry.query, source: entry.source);
      if (scroll.hasClients) scroll.jumpTo(0);
    }
    dirty = true;
    if (!widget.active || busy || _detailsOpen || _refreshScheduled) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (mounted) scheduleLoad(restore: initialized);
    });
  }

  ({PackBrowseContext context, List<String> ids}) position() {
    final pixels = scroll.hasClients ? scroll.offset : 0.0;
    final local = max(0, ((pixels - listHeader) / stride).floor() * columns);
    final index = local.clamp(0, max(0, data.items.length - 1)).toInt();
    final ids = <String>[];
    for (
      var distance = 0;
      distance < data.items.length && ids.length < 16;
      distance++
    ) {
      if (index + distance < data.items.length) {
        ids.add(data.items[index + distance].id);
      }
      if (distance > 0 && index - distance >= 0 && ids.length < 16) {
        ids.add(data.items[index - distance].id);
      }
    }
    return (
      context: entry.copyWith(
        scrollOffset: pixels,
        scrollAnchor: data.items.isEmpty ? null : data.items[index].id,
        scrollIndex: data.offset + index,
        scrollInset: pixels < listHeader
            ? pixels - listHeader
            : (pixels - listHeader) % stride,
      ),
      ids: ids,
    );
  }

  void remember() {
    if (pendingReturn != null || data.items.isEmpty) return;
    final saved = position();
    pendingReturn = saved.context;
    returnIds = saved.ids;
  }

  Future<void> load({
    bool more = false,
    bool before = false,
    bool restore = false,
  }) async {
    if (!widget.active ||
        busy ||
        _detailsOpen ||
        ((more || before) && (data.loading || continuationLoading))) {
      return;
    }
    final current = ++generation;
    final continuationWork = !more && !before && continuationEligible
        ? readContinuation()
        : null;
    continuationLoading = continuationWork != null;
    unawaited(loadPendingFiles());
    final oldStart = data.offset,
        oldPixels = scroll.hasClients ? scroll.offset : 0.0;
    if (restore) remember();
    final restoring = pendingReturn;
    int? restoredAnchor;
    _positioning = restoring != null || before;
    if (restoring != null) {
      await catalog.restore(restoring, anchors: returnIds);
      if (!mounted || current != generation) return;
      restoredAnchor = data.anchorIndex;
      // An anchor at a page boundary needs the following visible rows before
      // jumping, otherwise ScrollPosition clamps to the incomplete window.
      final viewport = scroll.hasClients
          ? scroll.position.viewportDimension
          : MediaQuery.sizeOf(context).height;
      final through =
          (restoredAnchor ?? data.offset) +
          ((viewport / stride).ceil() + 1) * columns;
      while (mounted &&
          current == generation &&
          data.error.isEmpty &&
          data.hasMore &&
          data.offset + data.items.length < through &&
          data.items.length < PackQueryController.maximumItems) {
        await catalog.load(restoring, more: true);
      }
    } else {
      await catalog.load(entry, more: more, before: before);
    }
    final summary = await continuationWork;
    if (!mounted || current != generation) return;
    setState(() {
      if (summary != null && continuationEligible) {
        continuation = summary.pack;
        continuationError = summary.error;
      }
      continuationLoading = false;
      initialized = true;
      dirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || current != generation) return;
      if (scroll.hasClients && data.error.isEmpty) {
        double? pixels;
        if (restoring != null) {
          pixels = restoring.scrollOffset == 0 && restoring.scrollIndex == 0
              ? 0
              : listHeader +
                    ((restoredAnchor ?? data.offset) - data.offset) ~/
                        columns *
                        stride +
                    restoring.scrollInset;
          pendingReturn = null;
        } else if (oldStart != data.offset && data.items.isNotEmpty) {
          pixels = oldPixels + (oldStart - data.offset) ~/ columns * stride;
        }
        if (pixels != null) {
          scroll.jumpTo(pixels.clamp(0.0, scroll.position.maxScrollExtent));
        }
      }
      _positioning = false;
      nearBottom();
    });
  }

  void nearBottom() {
    if (widget.active &&
        !busy &&
        !_detailsOpen &&
        !_positioning &&
        scroll.hasClients &&
        !data.loading &&
        !continuationLoading &&
        data.error.isEmpty &&
        data.items.isNotEmpty) {
      if (scroll.position.extentBefore < listHeader + 180 && data.hasBefore) {
        unawaited(load(before: true));
      } else if (scroll.position.extentAfter < 480 && data.hasMore) {
        unawaited(load(more: true));
      }
    }
  }

  Future<void> change(PackQuery query) async {
    entry = entry.copyWith(query: query);
    selection.cancel(clear: true);
    pendingReturn = null;
    returnIds = const [];
    if (scroll.hasClients) scroll.jumpTo(0);
    await load();
  }

  void toggleSelection() {
    if (_detailsOpen || busy) return;
    selection.cancel(clear: true);
    final oldHeader = listHeader;
    final pixels = scroll.hasClients ? scroll.offset : 0.0;
    final saved = position();
    setState(() => selecting = !selecting);
    if (pixels >= oldHeader) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(
            (pixels + listHeader - oldHeader).clamp(
              0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
    if (!selecting) {
      if (pendingReturn == null) {
        pendingReturn = saved.context;
        returnIds = saved.ids;
      }
      unawaited(load(restore: initialized));
    }
  }

  void selectFromCover(String id) {
    if (_detailsOpen || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!selecting) toggleSelection();
    selection.toggle(id);
  }

  Future<({LibraryPack? pack, String error})> readContinuation() async {
    try {
      return (pack: await repo.loadPackContinuation(), error: '');
    } on RequestCancelled {
      return (pack: null, error: '续读摘要已取消，请重试');
    } catch (failure) {
      return (pack: null, error: failure.toString());
    }
  }

  Widget continuationHeader() {
    final p = Paper.of(context), pack = continuation;
    final index = pack?.progress?.pageIndex;
    final position = continuationPosition;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MediaLayout.side),
      child: SizedBox(
        height: continuationExtent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.line)),
          ),
          child: continuationError.isNotEmpty
              ? Row(
                  children: [
                    Icon(Icons.menu_book_outlined, color: p.muted),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '续读位置暂不可用',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13),
                          ),
                          Flexible(
                            child: Text(
                              continuationError,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: p.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: continuationLoading
                          ? null
                          : () => load(restore: initialized),
                      child: const Text('重试'),
                    ),
                  ],
                )
              : InkWell(
                  key: const Key('pack-continuation'),
                  onTap:
                      pack == null ||
                          continuationLoading ||
                          busy ||
                          data.loading ||
                          data.error.isNotEmpty ||
                          repo.backupRestorePending
                      ? null
                      : () => open(anchor: pack.id),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 11),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 58,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: PackCover(
                              pack: pack!,
                              repository: repo,
                              active: widget.active,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                continuationLoading ? '正在核对续读位置' : '继续阅读',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MediaLayout.continuationMeta.copyWith(
                                  color: p.muted,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                pack.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MediaLayout.continuationTitle.copyWith(
                                  color: p.ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                position,
                                key: const Key('pack-continuation-position'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MediaLayout.continuationMeta.copyWith(
                                  color: p.muted,
                                ),
                              ),
                              SizedBox(
                                width: double.infinity,
                                height: 2,
                                child: LinearProgressIndicator(
                                  value: index == null || pack.pageCount == 0
                                      ? 0
                                      : (index + 1) / pack.pageCount,
                                  color: p.olive,
                                  backgroundColor: p.line,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 11),
                        const Icon(Icons.chevron_right, size: 22),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> openFolder() async {
    final result = await paperSheet<String>(
      context,
      PackFolderPicker(repository: repo, initial: entry.query.folder),
    );
    if (mounted && result != null) {
      await change(entry.query.copy(folder: result));
    }
  }

  Future<void> filter() async {
    final result = await paperSheet<PackQuery>(
      context,
      PackFilterSheet(repository: repo, initial: entry.query),
    );
    if (mounted && result != null) await change(result);
  }

  Future<PackTagNames?> tags(
    Set<String> ids, {
    Set<String> initial = const {},
    Map<String, String> initialNames = const {},
    bool appendOnly = false,
  }) async {
    if (repo.backupRestorePending) return null;
    final hadPending = pendingReturn != null;
    remember();
    setState(() => busy = true);
    try {
      return await paperSheet<PackTagNames>(
        context,
        PackTagEditor(
          repository: repo,
          ids: ids,
          initial: initial,
          initialNames: initialNames,
          appendOnly: appendOnly,
        ),
        dismissible: false,
      );
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (!_detailsOpen) {
          if (dirty) {
            await load(restore: initialized);
          } else if (!hadPending) {
            pendingReturn = null;
          }
        }
      }
    }
  }

  Future<void> loadPendingFiles() async {
    final request = ++_pendingFilesRead, connection = repo.connectionIdentity;
    if (!repo.capabilities.packLogicalTrash) return;
    try {
      final pending = await repo.createPackFiles().pending();
      if (mounted &&
          request == _pendingFilesRead &&
          identical(connection, repo.connectionIdentity)) {
        setState(() => pendingFiles = pending);
      }
    } catch (failure) {
      if (mounted &&
          request == _pendingFilesRead &&
          identical(connection, repo.connectionIdentity)) {
        setState(() => error = failure.toString());
      }
    }
  }

  Future<void> checkPendingFiles() async {
    if (_detailsOpen || pendingFiles.isEmpty) return;
    var command = pendingFiles.first;
    _detailsOpen = true;
    try {
      if (pendingFiles.length > 1) {
        final selected = await paperSheet<PackFileCommand>(
          context,
          SheetFrame(
            title: '待核对的图包操作',
            children: [
              for (final value in pendingFiles)
                ListTile(
                  title: Text(
                    value.label ?? (value.kind == 'trash' ? '移除' : '图包恢复与撤销'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        );
        if (selected == null || !mounted) return;
        command = selected;
      }
      if (!mounted) return;
      final files = repo.createPackFiles();
      final outcome = await showPackFileAction(
        context,
        files: files,
        command: command,
        title: '核对图包操作',
        description: command.label,
        confirm: true,
      );
      if (outcome == null || !mounted || !files.isCurrent()) return;
      await files.acknowledge(outcome.command);
      repo.packFilesChanged();
      if (mounted &&
          outcome.command.kind == 'trash' &&
          outcome.task.result!.succeeded > 0) {
        showPackUndo(context, repo, outcome, onRestored: resumeRestored);
      } else if (mounted) {
        if (outcome.command.kind == 'undo' &&
            outcome.task.result!.readingRestored) {
          _detailsOpen = false;
          await resumeRestored(outcome);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(
            context: context,
            content: Text(
              outcome.task.result!.succeeded > 0
                  ? '图包操作已完成'
                  : '图包操作未完成，请重新读取后再试',
            ),
          ),
        );
      }
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      _detailsOpen = false;
      if (mounted && widget.active) await load(restore: initialized);
    }
  }

  Future<void> actions(LibraryPack pack) async {
    if (_detailsOpen || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _detailsOpen = true;
    String? action;
    try {
      action = await paperSheet<String>(
        context,
        SheetFrame(
          title: pack.displayTitle,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('阅读图包'),
              trailing: const Icon(Icons.chrome_reader_mode_outlined),
              onTap: () => Navigator.pop(context, 'read'),
            ),
            if (repo.capabilities.packReaderCleanup &&
                repo.capabilities.packLogicalTrash)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('从这包开始快速整理'),
                trailing: const Icon(Icons.playlist_play),
                onTap: () => Navigator.pop(context, 'quick'),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('图包标签'),
              trailing: const Icon(Icons.sell_outlined),
              onTap: () => Navigator.pop(context, 'tags'),
            ),
            if (repo.capabilities.packLogicalTrash)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '移入回收站',
                  style: TextStyle(color: Paper.of(context).danger),
                ),
                trailing: const Icon(Icons.delete_outline),
                onTap: () => Navigator.pop(context, 'trash'),
              ),
          ],
        ),
      );
    } finally {
      _detailsOpen = false;
    }
    if (!mounted || !widget.active) return;
    if (action == 'read') await details(pack);
    if (action == 'quick') await open(quick: true, anchor: pack.id);
    if (action == 'tags') {
      await tags({pack.id}, initial: pack.tags, initialNames: pack.tagNames);
    }
    if (action == 'trash') await remove(pack);
  }

  Future<void> remove(LibraryPack pack) => removePacks(
    {pack.id},
    label: pack.displayTitle,
    description: '${pack.displayTitle} · ${pack.pageCount} 张',
  );

  Future<void> removePacks(
    Set<String> ids, {
    String? label,
    String? description,
  }) async {
    if (_detailsOpen || busy || ids.isEmpty || selection.loading) return;
    final targets = Set<String>.of(ids);
    FocusManager.instance.primaryFocus?.unfocus();
    remember();
    if (repo.capabilities.packDirectoryDelete) {
      final files = repo.createPackFiles();
      final command = PackFileCommand.trash(packFileRequestId(), targets);
      try {
        await files.journal.remember(files.scope, command);
        if (!mounted || !files.isCurrent()) return;
        selected.removeAll(targets);
        selection.cancel();
        unawaited(_removeLikeVideo(files, command));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            PaperSnackBar(context: context, content: const Text('移除未完成，请重试')),
          );
        }
      }
      return;
    }
    _detailsOpen = true;
    try {
      final outcome = await showPackFileAction(
        context,
        files: repo.createPackFiles(),
        command: PackFileCommand.trash(
          packFileRequestId(),
          targets,
          label: label ?? '${targets.length} 个图包',
        ),
        title: '移入回收站？',
        description: description ?? '已选择 ${targets.length} 个图包。保留源文件，可在回收站恢复。',
      );
      if (outcome == null || !mounted || !outcome.files.isCurrent()) return;
      await outcome.files.acknowledge(outcome.command);
      selected.removeAll(
        outcome.task.result!.items
            .where((x) => x.succeeded)
            .map((x) => x.packId),
      );
      selection.cancel();
      repo.packFilesChanged();
      if (!mounted) return;
      if (outcome.task.result!.succeeded > 0) {
        showPackUndo(context, repo, outcome, onRestored: resumeRestored);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(
            context: context,
            content: const Text('图包未移除，请重新读取后再试'),
          ),
        );
      }
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(context: context, content: Text(failure.toString())),
        );
      }
    } finally {
      _detailsOpen = false;
      if (mounted && widget.active) await load(restore: initialized);
    }
  }

  Future<void> _removeLikeVideo(
    PackFiles files,
    PackFileCommand command,
  ) async {
    try {
      final task = await files.resolve(
        command,
        submit: true,
        timeout: const Duration(minutes: 10),
        keepWaiting: files.isCurrent,
      );
      if (!files.isCurrent() || task?.settled != true) return;
      await files.acknowledge(command);
      repo.packFilesChanged();
      if (!mounted) return;
      if (task!.result!.succeeded > 0) {
        showPackUndo(
          context,
          repo,
          PackFileOutcome(files, command, task),
          onRestored: resumeRestored,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(context: context, content: const Text('移除未完成，请重试')),
        );
      }
    } catch (_) {
      if (mounted && files.isCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(
          PaperSnackBar(context: context, content: const Text('移除未完成，请重试')),
        );
      }
    }
  }

  Future<void> resumeRestored(PackFileOutcome outcome) async {
    if (!mounted ||
        !outcome.files.isCurrent() ||
        !outcome.task.result!.readingRestored ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final origin = outcome.command.readerContext;
    final identity = outcome.command.readingSessionId;
    if (origin == null || identity == null) return;
    if (widget.onResumeReading != null) {
      await widget.onResumeReading!(origin, identity);
    } else if (origin.entry.source == entry.source) {
      await resumeFromCleanup(origin, identity);
    }
  }

  Future<void> resumeFromCleanup(
    PackCleanupContext origin,
    String identity,
  ) async {
    if (!mounted ||
        !widget.active ||
        _detailsOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    entry = PackBrowseContext(
      query: origin.entry.query,
      scrollOffset: origin.scrollOffset,
      scrollAnchor: origin.scrollAnchor,
      scrollIndex: origin.scrollIndex,
      scrollInset: origin.scrollInset,
    );
    search.text = entry.query.search;
    selection.cancel(clear: true);
    selecting = false;
    pendingReturn = entry;
    returnIds = origin.anchors;
    await open(origin: origin, resumeSessionId: identity, quick: origin.quick);
  }

  Future<void> open({
    bool quick = false,
    String? anchor,
    PackCleanupContext? origin,
    String? resumeSessionId,
  }) async {
    if (_detailsOpen ||
        busy ||
        !widget.active ||
        !repo.capabilities.packReadingSessions) {
      return;
    }
    if (quick &&
        (!repo.capabilities.packReaderCleanup ||
            !repo.capabilities.packLogicalTrash)) {
      return;
    }
    if (origin == null && data.items.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    remember();
    final saved = pendingReturn ?? entry;
    final returnContext =
        origin ??
        PackCleanupContext(
          entry: PackReadingEntry(
            entry.query,
            source: entry.source,
            anchorId: anchor ?? data.items.first.id,
          ),
          quick: quick,
          scrollOffset: saved.scrollOffset,
          scrollAnchor: saved.scrollAnchor,
          scrollIndex: saved.scrollIndex,
          scrollInset: saved.scrollInset,
          anchors: returnIds,
        );
    _detailsOpen = true;
    PackFileOutcome? outcome;
    try {
      outcome = await Navigator.of(context).push<PackFileOutcome>(
        PaperPageRoute<PackFileOutcome>(
          builder: (_) => PackReaderPage(
            repository: repo,
            entry: returnContext.entry,
            quick: quick,
            returnContext: returnContext,
            resumeSessionId: resumeSessionId,
            editTags: (current) => tags(
              {current.id},
              initial: current.tags,
              initialNames: current.tagNames,
            ),
          ),
        ),
      );
    } finally {
      _detailsOpen = false;
      if (mounted && widget.active) {
        unawaited(repo.refreshCatalogCounts());
        await load(restore: initialized);
      }
    }
    if (outcome != null && mounted && outcome.files.isCurrent()) {
      showPackUndo(context, repo, outcome, onRestored: resumeRestored);
    }
  }

  Future<void> details(LibraryPack pack) async {
    if (_detailsOpen || busy) return;
    if (repo.capabilities.packReadingSessions) {
      await open(anchor: pack.id);
      return;
    }

    // LF4 exposes the real catalog object. LF5 replaces this entry with its
    // fixed-scope reader once progress and recent writes exist on the service.
    var ids = {...pack.tags}, names = {...pack.tagNames};
    final owner = repo.connectionIdentity;
    var error = '';
    _detailsOpen = true;
    try {
      await paperSheet<void>(
        context,
        StatefulBuilder(
          builder: (sheetContext, local) => SheetFrame(
            title: pack.displayTitle,
            children: [
              SizedBox(
                height: 230,
                child: PackCover(pack: pack, repository: repo),
              ),
              note('${pack.pageCount} 张 · ${pack.readableCount} 张可读取'),
              Text(
                pack.path,
                style: TextStyle(fontSize: 12, color: Paper.of(context).muted),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('图包标签'),
                trailing: const Icon(Icons.chevron_right),
                subtitle: names.isEmpty ? null : Text(names.values.join('、')),
                onTap: () async {
                  if (!identical(owner, repo.connectionIdentity)) {
                    local(() => error = '服务连接已变化，请关闭后重新打开。');
                    return;
                  }
                  final result = await tags(
                    {pack.id},
                    initial: ids,
                    initialNames: names,
                  );
                  if (result != null && sheetContext.mounted) {
                    local(() {
                      ids = result.names.keys.toSet();
                      names = {...result.names};
                    });
                  }
                },
              ),
              if (error.isNotEmpty) note(error),
            ],
          ),
        ),
      );
    } finally {
      _detailsOpen = false;
      if (mounted && widget.active && dirty) await load(restore: initialized);
    }
  }

  String historyPosition(LibraryPack pack) {
    final progress = pack.progress;
    final position = progress?.pageIndex;
    return position != null
        ? '${progress!.completed ? '已读 · ' : ''}第 ${position + 1} / ${pack.pageCount} 张'
        : progress?.completed == true
        ? '已读 · ${pack.pageCount} 张'
        : progress != null
        ? '续读位置待确认 · ${pack.pageCount} 张'
        : '${pack.pageCount} 张';
  }

  double get _historyStride => MediaLayout.historyRow(
    context,
    items: data.items.map(
      (p) => (title: p.displayTitle, subtitle: historyPosition(p)),
    ),
  );

  Widget recentRow(LibraryPack pack) {
    final label = historyPosition(pack);
    return MediaHistoryRow(
      key: Key('recent-pack-${pack.id}'),
      title: pack.displayTitle,
      subtitle: label,
      subtitleKey: Key('recent-pack-progress-${pack.id}'),
      cover: PackCover(pack: pack, repository: repo, active: widget.active),
      selecting: selecting,
      selected: selected.contains(pack.id),
      onTap: busy
          ? null
          : () {
              if (selecting) {
                selection.toggle(pack.id);
              } else {
                unawaited(details(pack));
              }
            },
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      layoutGrid(context, box.maxWidth);
      final p = Paper.of(context), recent = entry.source == BrowseSource.recent;
      return Column(
        children: [
          if (!recent)
            Row(
              children: [
                Expanded(
                  child: selecting
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text('多选图包', style: TextStyle(fontSize: 13)),
                        )
                      : MediaCatalogSearch(
                          fieldKey: const Key('pack-search'),
                          controller: search,
                          hint: '搜索图包、作者、目录',
                          filterLabel: '筛选图包',
                          onFilter: filter,
                          onChanged: (value) =>
                              change(entry.query.copy(search: value)),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    key: const Key('pack-multi-select'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed:
                        busy ||
                            _detailsOpen ||
                            (!selecting && data.items.isEmpty)
                        ? null
                        : toggleSelection,
                    child: Text(
                      selecting ? '完成' : '多选',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          if (error.isNotEmpty) note(error),
          if (!repo.capabilities.packDirectoryDelete && pendingFiles.isNotEmpty)
            Row(
              children: [
                Expanded(child: note('${pendingFiles.length} 项图包操作待核对')),
                TextButton(
                  key: const Key('pack-pending-files'),
                  onPressed: checkPendingFiles,
                  child: const Text('查询结果'),
                ),
              ],
            ),
          if (data.loading && data.items.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (data.error.isNotEmpty && data.items.isNotEmpty)
            MediaCatalogFailure(
              message: data.error,
              side: recent ? 20 : 16,
              retryKey: const Key('pack-list-retry'),
              onRetry: data.loading
                  ? null
                  : () => load(
                      more: data.retryMore,
                      before: data.retryBefore,
                      restore: data.retryRestore,
                    ),
            ),
          Expanded(
            child:
                (data.loading && data.items.isEmpty) ||
                    (!initialized && continuationLoading)
                ? const Center(child: CircularProgressIndicator())
                : data.error.isNotEmpty && data.items.isEmpty
                ? EmptyView(
                    data.error,
                    action: TextButton(
                      onPressed: () => load(),
                      child: const Text('重试'),
                    ),
                  )
                : CustomScrollView(
                    key: const Key('pack-grid'),
                    controller: scroll,
                    slivers: [
                      if (hasContinuation)
                        SliverToBoxAdapter(child: continuationHeader()),
                      if (!recent &&
                          (entry.query.count > 0 ||
                              entry.query.search.isNotEmpty))
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaLayout.scope(context),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      [
                                        if (entry.query.folder.isNotEmpty)
                                          entry.query.folder,
                                        if (entry.query.tags.isNotEmpty)
                                          '${entry.query.tags.length} 个图包标签',
                                        if (entry.query.search.isNotEmpty)
                                          '“${entry.query.search}”',
                                        if (entry.query.readState !=
                                            PackReadState.all)
                                          {
                                            PackReadState.unread: '未读',
                                            PackReadState.reading: '在读',
                                            PackReadState.completed: '已读',
                                          }[entry.query.readState]!,
                                      ].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: p.olive,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      search.clear();
                                      unawaited(change(PackQuery()));
                                    },
                                    child: const Text('清除'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (recent)
                        SliverToBoxAdapter(
                          child: MediaHistoryHeader(
                            label: '最近阅读的图包',
                            count: '${data.total} 包',
                          ),
                        ),
                      if (!recent && !selecting)
                        SliverToBoxAdapter(
                          child: MediaCatalogToolbar(
                            children: [
                              Text(
                                '${data.total} 个图包',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                key: const Key('pack-count'),
                                style: TextStyle(fontSize: 13, color: p.muted),
                              ),
                              TextButton(
                                onPressed: () => change(
                                  entry.query.copy(
                                    readState:
                                        PackReadState.values[(entry
                                                    .query
                                                    .readState
                                                    .index +
                                                1) %
                                            PackReadState.values.length],
                                  ),
                                ),
                                child: Text(switch (entry.query.readState) {
                                  PackReadState.all => '阅读状态',
                                  PackReadState.unread => '未读',
                                  PackReadState.reading => '在读',
                                  PackReadState.completed => '已读',
                                }, style: const TextStyle(fontSize: 13)),
                              ),
                              PaperMenuButton<PackSort>(
                                tooltip: '图包排序',
                                initialValue: entry.query.sort,
                                onSelected: (value) =>
                                    change(entry.query.copy(sort: value)),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: PackSort.name,
                                    child: Text('名称'),
                                  ),
                                  PopupMenuItem(
                                    value: PackSort.newest,
                                    child: Text('最近加入'),
                                  ),
                                ],
                                child: Text(switch (entry.query.sort) {
                                  PackSort.name => '名称 ↓',
                                  PackSort.newest => '最近加入 ↓',
                                  PackSort.recent => '最近阅读 ↓',
                                }, style: const TextStyle(fontSize: 13)),
                              ),
                              if (repo.capabilities.packReaderCleanup &&
                                  repo.capabilities.packLogicalTrash &&
                                  !selecting)
                                TextButton(
                                  key: const Key('pack-quick-cleanup'),
                                  onPressed:
                                      data.items.isEmpty || busy || data.loading
                                      ? null
                                      : () => open(quick: true),
                                  child: const Text(
                                    '快速整理',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (recent && data.items.isEmpty)
                        const SliverToBoxAdapter(child: MediaHistoryEmpty()),
                      if (!recent && data.items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(recent ? '还没有观看记录' : '没有符合条件的图包'),
                        ),
                      if (recent)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverFixedExtentList.builder(
                            itemExtent: stride,
                            itemCount: data.items.length,
                            itemBuilder: (context, index) =>
                                recentRow(data.items[index]),
                          ),
                        ),
                      if (!recent)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 18,
                                  mainAxisExtent: stride - MediaLayout.rowGap,
                                ),
                            itemCount: data.items.length,
                            itemBuilder: (context, index) {
                              final pack = data.items[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: MediaLayout.cover(box.maxWidth),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        InkWell(
                                          key: Key('pack-tile-${pack.id}'),
                                          onLongPress: () =>
                                              selectFromCover(pack.id),
                                          onTap: () {
                                            if (selecting) {
                                              selection.toggle(pack.id);
                                            } else {
                                              unawaited(details(pack));
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                            child: PackCover(
                                              pack: pack,
                                              repository: repo,
                                              active: widget.active,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: 7,
                                          bottom: 7,
                                          child: IgnorePointer(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: const Color(0xbf18241c),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 3,
                                                    ),
                                                child: Text(
                                                  '${pack.pageCount} 张',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (pack.progress != null && !selecting)
                                          Positioned(
                                            left: 8,
                                            top: 8,
                                            child: IgnorePointer(
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: p.background
                                                      .withValues(alpha: .93),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 4,
                                                      ),
                                                  child: Text(
                                                    pack.readingBadge,
                                                    style: TextStyle(
                                                      color: p.olive,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (selecting)
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: IgnorePointer(
                                              child: Icon(
                                                selected.contains(pack.id)
                                                    ? Icons.check_circle
                                                    : Icons
                                                          .radio_button_unchecked,
                                                color:
                                                    selected.contains(pack.id)
                                                    ? p.olive
                                                    : Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    pack.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: p.title.copyWith(
                                      fontSize: 16,
                                      height: 1.5,
                                    ),
                                  ),
                                  SizedBox(
                                    height: MediaLayout.meta(context),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            pack.catalogSubtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: p.catalogMeta,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '图包操作 ${pack.displayTitle}',
                                          onPressed: () => actions(pack),
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 28,
                                          ),
                                          padding: EdgeInsets.zero,
                                          iconSize: 18,
                                          icon: const Icon(Icons.more_horiz),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    key: Key('pack-tag-names-${pack.id}'),
                                    pack.tags.isEmpty
                                        ? ''
                                        : pack.tagNames.isEmpty
                                        ? '${pack.tags.length} 个标签'
                                        : (pack.tagNames.values.toList()
                                                ..sort())
                                              .map((name) => '# $name')
                                              .join('  '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MediaLayout.cardTags.copyWith(
                                      color: p.olive,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      if (data.loading && data.items.isNotEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: CircularProgressIndicator(
                                key: Key('pack-loading-more'),
                              ),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: recent ? 20 : 18),
                      ),
                    ],
                  ),
          ),
          if (selection.error.isNotEmpty) note(selection.error),
          if (selecting)
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: const Key('pack-select-all'),
                          onPressed: selection.loading
                              ? selection.cancel
                              : () => selection.all(
                                  () => repo.selectPackIds(entry.query),
                                ),
                          child: Text(
                            selection.loading ? '取消全选' : '全选匹配项',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          selection.loading ? '正在全选…' : '已选 ${selected.length}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          key: const Key('pack-add-selected-tags'),
                          onPressed: selected.isEmpty || selection.loading
                              ? null
                              : () => tags({...selected}, appendOnly: true),
                          child: const Text(
                            '添加标签',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (repo.capabilities.packLogicalTrash)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('pack-delete-selected'),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.danger,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onError,
                          ),
                          onPressed:
                              selected.isEmpty ||
                                  selected.length > 1000 ||
                                  selection.loading ||
                                  busy ||
                                  _detailsOpen
                              ? null
                              : () => removePacks({...selected}),
                          icon: const Icon(Icons.delete_outline),
                          label: Text('移入回收站（${selected.length}）'),
                        ),
                      ),
                    ),
                  if (selected.length > 1000) note('每次最多移除1000个图包，请减少选择'),
                ],
              ),
            ),
        ],
      );
    },
  );
}
