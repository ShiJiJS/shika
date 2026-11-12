import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/media_layout.dart';
import '../../ui/media_history.dart';
import '../../ui/media_poster.dart';
import '../../ui/paper.dart';
import '../../ui/paper_icons.dart';
import '../../ui/preferences.dart';
import '../../ui/sheets.dart';
import '../preview/video_preview_route.dart';
import 'browse_context.dart';
import 'catalog_selection.dart';
import 'library_query_controller.dart';

/// One source owns its query, selection, list window and return location.
class VideoCatalogPage extends StatefulWidget {
  const VideoCatalogPage({
    super.key,
    required this.repository,
    required this.preferences,
    required this.entry,
    required this.active,
    this.onSelectionChanged,
    required this.defaultOrder,
  });
  final LibraryRepository repository;
  final UiPreferences preferences;
  final VideoBrowseContext entry;
  final VoidCallback? onSelectionChanged;
  final bool active;
  final PlayOrder defaultOrder;
  @override
  State<VideoCatalogPage> createState() => VideoCatalogPageState();
}

class VideoCatalogPageState extends State<VideoCatalogPage> {
  LibraryRepository get repo => widget.repository;
  late final query = LibraryQueryController(repo);
  late VideoBrowseContext entry = widget.entry;
  late final search = TextEditingController(text: entry.search);
  final scroll = ScrollController();
  late final selection = CatalogSelection(
    connection: () => repo.connectionIdentity,
    cancelRead: repo.cancelVideoSelection,
  );
  Set<String> get selected => selection.ids;
  late Object selectionConnection = repo.connectionIdentity;
  late final initialOrder = widget.defaultOrder;
  bool selecting = false,
      busy = false,
      viewing = false,
      initialized = false,
      dirty = false;
  bool _refreshScheduled = false, _positioning = false;
  int generation = 0;
  String error = '';
  double width = 390;
  MediaGridGeometry? _geometry;
  ({String id, double inset, bool top, int generation})? _reflow;
  int _layoutRevision = 0;
  VideoBrowseContext? pendingReturn;
  List<String> returnIds = const [];
  VideoLibraryState get data => query.state;
  bool get recent => entry.source == BrowseSource.recent;
  int get columns => _geometry?.columns ?? (recent ? 1 : 2);
  double get stride => _geometry?.stride ?? _strideValue;
  double get _strideValue => recent
      ? _historyStride
      : MediaLayout.tile(context, width) + MediaLayout.rowGap;
  double get _historyStride => MediaLayout.historyRow(
    context,
    items: data.items.map(
      (v) => (title: v.displayTitle, subtitle: v.durationLabel),
    ),
  );
  double get listHeader => _geometry?.header ?? _listHeaderValue;
  double get _listHeaderValue => recent
      ? MediaLayout.historyHeader(context)
      : (selecting ? 12 : MediaLayout.toolbar(context)) +
            (!selecting && entry.query.count > 0
                ? MediaLayout.scope(context)
                : 0);

  void layoutGrid(BuildContext context, double nextWidth) {
    final next = MediaGridGeometry(
      recent ? 1 : MediaLayout.columns(context),
      recent
          ? _historyStride
          : MediaLayout.tile(context, nextWidth) + MediaLayout.rowGap,
      _listHeaderValue,
    );
    final old = _geometry;
    if (old != null &&
        (old.reflows(next) || (recent && old.header != next.header)) &&
        _reflow == null &&
        !_positioning &&
        !viewing &&
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
          viewing ||
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
      nearEdge();
    });
  }

  @override
  void initState() {
    super.initState();
    query.addListener(changed);
    repo.addListener(repositoryChanged);
    selection.addListener(selectionChanged);
    scroll.addListener(nearEdge);
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(load());
      });
    }
  }

  @override
  void didUpdateWidget(VideoCatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.queryKey != widget.entry.queryKey) {
      entry = widget.entry;
      search.text = entry.search;
      selection.cancel(clear: true);
      pendingReturn = null;
      if (widget.active) scheduleLoad();
    } else if (oldWidget.active != widget.active) {
      generation++;
      if (!widget.active) {
        selecting = false;
        selection.cancel(clear: true);
        query.cancel();
      } else if (!viewing) {
        scheduleLoad(restore: initialized);
      }
    }
  }

  void scheduleLoad({bool restore = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active && !viewing) {
        unawaited(load(restore: restore));
      }
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void repositoryChanged() {
    if (!identical(selectionConnection, repo.connectionIdentity)) {
      selectionConnection = repo.connectionIdentity;
      selection.cancel(clear: true);
    }
    if (!widget.active || viewing || busy) {
      dirty = true;
      return;
    }
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (mounted && widget.active && !viewing) {
        unawaited(load(restore: initialized));
      }
    });
  }

  ({VideoBrowseContext context, List<String> ids}) position() {
    final pixels = scroll.hasClients ? scroll.offset : 0.0;
    final local = max(0, ((pixels - listHeader) / stride).floor() * columns);
    final index = local.clamp(0, max(0, data.items.length - 1)).toInt();
    return (
      context: entry.copyWith(
        scrollOffset: pixels,
        scrollAnchor: data.items.isEmpty ? null : data.items[index].id,
        scrollIndex: data.offset + index,
        scrollInset: pixels < listHeader
            ? pixels - listHeader
            : (pixels - listHeader) % stride,
      ),
      ids: data.items.skip(index).take(16).map((video) => video.id).toList(),
    );
  }

  Future<void> load({
    bool more = false,
    bool before = false,
    bool restore = false,
  }) async {
    if (!widget.active || viewing) return;
    final current = ++generation;
    final oldStart = data.offset,
        oldPixels = scroll.hasClients ? scroll.offset : 0.0;
    if (restore && pendingReturn == null && data.items.isNotEmpty) {
      final saved = position();
      pendingReturn = saved.context;
      returnIds = saved.ids;
    }
    final restoring = pendingReturn;
    int? restoredAnchor;
    _positioning = restoring != null || before;
    if (restoring != null) {
      await query.restore(restoring, anchors: returnIds);
      if (!mounted || current != generation) return;
      restoredAnchor = data.anchorIndex;
      final viewport = scroll.hasClients
          ? scroll.position.viewportDimension
          : MediaQuery.sizeOf(context).height;
      final through =
          (restoredAnchor ?? data.offset) +
          ((viewport / stride).ceil() + 1) * columns;
      while (mounted &&
          current == generation &&
          data.error.isEmpty &&
          data.hasAfter &&
          data.offset + data.items.length < through &&
          data.items.length < LibraryQueryController.maximumItems) {
        await query.load(restoring, more: true);
      }
    } else {
      await query.load(entry, more: more, before: before);
    }
    if (!mounted || current != generation) return;
    initialized = true;
    dirty = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || current != generation) return;
      if (scroll.hasClients && data.error.isEmpty) {
        double? pixels;
        if (restoring != null) {
          pixels =
              listHeader +
              ((restoredAnchor ?? data.offset) - data.offset) ~/
                  columns *
                  stride +
              restoring.scrollInset;
          pendingReturn = null;
        } else if (oldStart != data.offset) {
          pixels = oldPixels + (oldStart - data.offset) ~/ columns * stride;
        }
        if (pixels != null) {
          scroll.jumpTo(pixels.clamp(0.0, scroll.position.maxScrollExtent));
        }
      }
      _positioning = false;
      nearEdge();
    });
  }

  void nearEdge() {
    if (!widget.active ||
        viewing ||
        busy ||
        _positioning ||
        _reflow != null ||
        data.loading ||
        data.error.isNotEmpty ||
        !scroll.hasClients ||
        data.items.isEmpty) {
      return;
    }
    if (scroll.position.extentBefore < 180 && data.hasBefore) {
      unawaited(load(before: true));
    } else if (scroll.position.extentAfter < 480 && data.hasAfter) {
      unawaited(load(more: true));
    }
  }

  Future<void> changeEntry(VideoBrowseContext next) async {
    entry = next;
    pendingReturn = null;
    selection.cancel(clear: true);
    if (scroll.hasClients) scroll.jumpTo(0);
    await load();
  }

  void selectionChanged() {
    changed();
    widget.onSelectionChanged?.call();
  }

  void selectAll() {
    if (selection.loading) {
      selection.cancel();
    } else if (selected.isNotEmpty && selected.length == data.total) {
      selection.cancel(clear: true);
    } else {
      unawaited(selection.all(() => repo.selectVideoIds(entry.entry)));
    }
  }

  void toggleSelection() {
    selection.cancel(clear: true);
    setState(() => selecting = !selecting);
    widget.onSelectionChanged?.call();
  }

  void selectFromCover(String id) {
    if (busy || viewing || !widget.active || repo.backupRestorePending) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!selecting) toggleSelection();
    selection.toggle(id);
  }

  Future<void> openFolder() async {
    final result = await paperSheet<String>(
      context,
      FolderPicker(repository: repo, initial: entry.query.folder),
    );
    if (result != null && mounted) {
      await changeEntry(
        entry.copyWith(query: entry.query.copy(folder: result)),
      );
    }
  }

  Future<void> filter() async {
    final result = await paperSheet<VideoQuery>(
      context,
      ScopeSheet(repository: repo, initial: entry.query),
    );
    if (result != null && mounted) {
      await changeEntry(entry.copyWith(query: result));
    }
  }

  Future<void> editTags(Set<String> ids, {bool appendOnly = false}) async {
    if (repo.backupRestorePending) return;
    await paperSheet<bool>(
      context,
      TagEditor(repository: repo, ids: ids, appendOnly: appendOnly),
      dismissible: false,
    );
    if (mounted && widget.active) await load(restore: true);
  }

  Future<void> actions(LibraryVideo video) async {
    if (busy || viewing || selecting) return;
    final action = await paperSheet<String>(
      context,
      SheetFrame(
        title: video.displayTitle,
        children: [
          ListTile(
            title: const Text('从这里开始整理'),
            trailing: const Icon(Icons.playlist_play),
            onTap: () => Navigator.pop(context, 'quick'),
          ),
          ListTile(
            title: const Text('视频标签'),
            trailing: const Icon(Icons.sell_outlined),
            onTap: () => Navigator.pop(context, 'tags'),
          ),
          ListTile(
            title: const Text('视频详情'),
            trailing: const Icon(Icons.info_outline),
            onTap: () => Navigator.pop(context, 'details'),
          ),
          ListTile(
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
    if (!mounted || !widget.active) return;
    switch (action) {
      case 'quick':
        await open(anchor: video.id, quick: true);
      case 'tags':
        await editTags({video.id});
      case 'details':
        await paperSheet<void>(
          context,
          SheetFrame(
            title: '视频详情',
            children: [
              Text(
                video.displayTitle,
                style: Paper.of(context).title.copyWith(fontSize: 18),
              ),
              note('${video.durationLabel} · ${video.portrait ? '竖版' : '横版'}'),
              SelectableText(video.path),
            ],
          ),
        );
      case 'trash':
        await removeVideos({video.id});
    }
  }

  Future<void> removeVideos(Set<String> ids) async {
    if (busy || ids.isEmpty || ids.length > 1000 || repo.backupRestorePending) {
      return;
    }
    final connection = repo.connectionIdentity;
    final targets = Set<String>.of(ids);
    final previous = repo.snapshot.lastDelete?.id;
    final saved = position();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      // Reuse the existing logical-trash operation and its undo receipt. Media
      // files are never physically deleted by catalogue batch actions.
      await repo.deleteVideos(
        targets,
        requestId: 'catalog-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted || !identical(connection, repo.connectionIdentity)) return;
      selected.removeAll(targets);
      selection.cancel();
      final operation = repo.snapshot.lastDelete;
      ScaffoldMessenger.of(context).showSnackBar(
        PaperSnackBar(
          context: context,
          content: const Text('已移入回收站'),
          duration: const Duration(seconds: 2),
          persist: false,
          action: operation == null || operation.id == previous
              ? null
              : SnackBarAction(
                  label: '撤销',
                  onPressed: () async {
                    if (!identical(connection, repo.connectionIdentity)) return;
                    try {
                      await repo.undoDelete(operationId: operation.id);
                      if (mounted &&
                          widget.active &&
                          identical(connection, repo.connectionIdentity)) {
                        await load(restore: true);
                      }
                    } catch (failure) {
                      if (mounted &&
                          identical(connection, repo.connectionIdentity)) {
                        setState(() => error = failure.toString());
                      }
                    }
                  },
                ),
        ),
      );
    } catch (failure) {
      if (mounted && identical(connection, repo.connectionIdentity)) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (widget.active && identical(connection, repo.connectionIdentity)) {
          pendingReturn = saved.context;
          returnIds = saved.ids;
          await load(restore: true);
          unawaited(repo.refreshCatalogCounts());
        }
      }
    }
  }

  Future<void> open({String? anchor, bool quick = false}) async {
    if (busy || viewing || repo.backupRestorePending || !widget.active) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final saved = position(), connection = repo.connectionIdentity;
    final current = ++generation;
    setState(() {
      viewing = true;
      busy = true;
      error = '';
    });
    query.cancel();
    var pushed = false;
    try {
      if (!repo.capabilities.managedPlaybackDefaults) {
        await widget.preferences.ensureVideoOrder(initialOrder);
      }
      final order = await repo.defaultVideoOrder(
        widget.preferences.videoOrder ?? initialOrder,
      );
      if (!mounted ||
          current != generation ||
          !widget.active ||
          !identical(connection, repo.connectionIdentity)) {
        return;
      }
      await repo.beginPreview(entry.entry, anchor: anchor, order: order);
      if (!mounted ||
          current != generation ||
          !widget.active ||
          !identical(connection, repo.connectionIdentity)) {
        return;
      }
      setState(() => busy = false);
      pushed = true;
      final route = PaperPageRoute<void>.fade(
        builder: (context) => VideoPreviewRoute(
          repository: repo,
          preferences: widget.preferences,
          origin: saved.context,
          quick: quick,
        ),
      );
      await Navigator.of(context).push(route);
      await route.completed;
      if (mounted) {
        pendingReturn = saved.context;
        returnIds = saved.ids;
      }
    } on RequestCancelled {
      /* The entry/connection that started this request has gone. */
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) {
        setState(() {
          viewing = false;
          busy = false;
        });
        if (widget.active) {
          if (pushed) unawaited(repo.refreshCatalogCounts());
          if (pushed || dirty || pendingReturn != null) {
            unawaited(load(restore: true));
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) nearEdge();
            });
          }
        }
      }
    }
  }

  @override
  void dispose() {
    generation++;
    repo.removeListener(repositoryChanged);
    selection.removeListener(selectionChanged);
    selection.dispose();
    query.removeListener(changed);
    query.dispose();
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      layoutGrid(context, constraints.maxWidth);
      final p = Paper.of(context), recent = entry.source == BrowseSource.recent;
      return Column(
        children: [
          if (!recent && !selecting)
            MediaCatalogSearch(
              fieldKey: const Key('video-search'),
              controller: search,
              hint: '搜索视频名称、目录',
              filterLabel: '筛选视频',
              onFilter: filter,
              onChanged: (value) => changeEntry(entry.copyWith(search: value)),
            ),
          if (busy || (data.loading && data.items.isNotEmpty))
            const PaperLinearProgressIndicator(minHeight: 2),
          if (error.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      error,
                      key: const Key('operation-error'),
                      style: TextStyle(color: p.danger),
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
          if (data.error.isNotEmpty && data.items.isNotEmpty)
            MediaCatalogFailure(
              message: data.error,
              side: recent ? 20 : 16,
              retryKey: const Key('library-return-retry'),
              onRetry: () => data.retryRestore || pendingReturn != null
                  ? load(restore: pendingReturn == null)
                  : load(more: !data.beforeFailure, before: data.beforeFailure),
            ),
          Expanded(
            child: data.loading && data.items.isEmpty
                ? const Center(child: PaperCircularProgressIndicator())
                : data.error.isNotEmpty && data.items.isEmpty
                ? EmptyView(
                    data.error,
                    action: TextButton(
                      onPressed: () => load(),
                      child: const Text('重试'),
                    ),
                  )
                : CustomScrollView(
                    key: const Key('video-grid'),
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (recent)
                        SliverToBoxAdapter(
                          child: MediaHistoryHeader(
                            label: '最近预览的视频',
                            count: '${data.total} 个视频',
                            onSelect:
                                selecting || busy || repo.backupRestorePending
                                ? null
                                : toggleSelection,
                          ),
                        ),
                      if (!recent && !selecting)
                        SliverToBoxAdapter(
                          child: MediaCatalogToolbar(
                            children: [
                              Text(
                                '${data.total} 个视频',
                                key: const Key('library-count'),
                                style: TextStyle(fontSize: 13, color: p.muted),
                              ),
                              if (!recent)
                                PaperMenuButton<VideoSort>(
                                  tooltip: '视频排序',
                                  initialValue: entry.sort,
                                  onSelected: (value) =>
                                      changeEntry(entry.copyWith(sort: value)),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: VideoSort.name,
                                      child: Text('名称'),
                                    ),
                                    PopupMenuItem(
                                      value: VideoSort.newest,
                                      child: Text('最近加入'),
                                    ),
                                  ],
                                  child: MediaSortLabel(
                                    entry.sort == VideoSort.newest
                                        ? '最近加入'
                                        : '名称',
                                  ),
                                ),
                              MediaCatalogAction(
                                key: const Key('video-quick-cleanup'),
                                icon: Icons.playlist_play,
                                label: '快速整理',
                                onPressed:
                                    busy ||
                                        data.loading ||
                                        data.items.isEmpty ||
                                        repo.backupRestorePending ||
                                        !repo.libraryPreparation.value.ready
                                    ? null
                                    : () => open(quick: true),
                              ),
                              MediaCatalogAction(
                                key: const Key('catalog-select'),
                                icon: Icons.check_box_outlined,
                                label: '选择',
                                onPressed: busy || repo.backupRestorePending
                                    ? null
                                    : toggleSelection,
                              ),
                            ],
                          ),
                        ),
                      if (!recent && !selecting && entry.query.count > 0)
                        SliverToBoxAdapter(
                          child: MediaFilterSummary(
                            filters: [
                              if (entry.query.folder.isNotEmpty)
                                (
                                  id: 'video-clear-folder',
                                  label: entry.query.folder.split('/').last,
                                  remove: () => changeEntry(
                                    entry.copyWith(
                                      query: entry.query.copy(folder: ''),
                                    ),
                                  ),
                                ),
                              for (final tag in entry.query.tags)
                                (
                                  id: 'video-clear-tag-$tag',
                                  label: repo.tagName(tag),
                                  remove: () => changeEntry(
                                    entry.copyWith(
                                      query: entry.query.copy(
                                        tags: {...entry.query.tags}
                                          ..remove(tag),
                                      ),
                                    ),
                                  ),
                                ),
                              if (entry.query.orientation.isNotEmpty)
                                (
                                  id: 'video-clear-orientation',
                                  label: entry.query.orientation == 'portrait'
                                      ? '竖版'
                                      : '横版',
                                  remove: () => changeEntry(
                                    entry.copyWith(
                                      query: entry.query.copy(orientation: ''),
                                    ),
                                  ),
                                ),
                              if (entry.query.duration.isNotEmpty)
                                (
                                  id: 'video-clear-duration',
                                  label: entry.query.duration == 'short'
                                      ? '10 秒以内'
                                      : '10 秒以上',
                                  remove: () => changeEntry(
                                    entry.copyWith(
                                      query: entry.query.copy(duration: ''),
                                    ),
                                  ),
                                ),
                              if (entry.query.type.isNotEmpty)
                                (
                                  id: 'video-clear-type',
                                  label: entry.query.type,
                                  remove: () => changeEntry(
                                    entry.copyWith(
                                      query: entry.query.copy(type: ''),
                                    ),
                                  ),
                                ),
                            ],
                            clear: () => changeEntry(
                              entry.copyWith(query: VideoQuery()),
                            ),
                          ),
                        ),
                      if (recent && data.items.isEmpty && !data.loading)
                        const SliverToBoxAdapter(child: MediaHistoryEmpty()),
                      if (!recent && data.items.isEmpty && !data.loading)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                            recent
                                ? '还没有观看记录'
                                : entry.query.count > 0 ||
                                      entry.search.isNotEmpty
                                ? '没有符合条件的视频'
                                : '视频库还是空的',
                          ),
                        ),
                      if (recent)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverFixedExtentList.builder(
                            itemExtent: stride,
                            itemCount: data.items.length,
                            itemBuilder: (context, index) {
                              final video = data.items[index];
                              return MediaHistoryRow(
                                onLongPress: () => selectFromCover(video.id),
                                key: Key('recent-video-${video.id}'),
                                title: video.displayTitle,
                                subtitle: video.durationLabel,
                                cover: MediaPoster(
                                  video: video,
                                  onUnauthorized: () => unawaited(
                                    repo.mediaUnauthorized(video.source),
                                  ),
                                ),
                                selecting: selecting,
                                selected: selected.contains(video.id),
                                onTap: busy
                                    ? null
                                    : () {
                                        if (selecting) {
                                          selection.toggle(video.id);
                                        } else {
                                          unawaited(open(anchor: video.id));
                                        }
                                      },
                              );
                            },
                          ),
                        ),
                      if (!recent)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            MediaLayout.side,
                            selecting ? 12 : 0,
                            MediaLayout.side,
                            0,
                          ),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: MediaLayout.columnGap,
                                  mainAxisSpacing: MediaLayout.rowGap,
                                  mainAxisExtent: stride - MediaLayout.rowGap,
                                ),
                            itemCount: data.items.length,
                            itemBuilder: (context, index) {
                              final video = data.items[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: MediaLayout.cover(width),
                                    width: double.infinity,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        MergeSemantics(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                child: ColoredBox(
                                                  color: const Color(
                                                    0xff20261f,
                                                  ),
                                                  child: MediaPoster(
                                                    video: video,
                                                    fit: BoxFit.contain,
                                                    onUnauthorized: () =>
                                                        unawaited(
                                                          repo.mediaUnauthorized(
                                                            video.source,
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              // Paint feedback above the opaque cover without moving it.
                                              Material(
                                                type: MaterialType.transparency,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                clipBehavior: Clip.antiAlias,
                                                child: InkWell(
                                                  key: Key('tile-${video.id}'),
                                                  onLongPress: () =>
                                                      selectFromCover(video.id),
                                                  onTap: busy
                                                      ? null
                                                      : () {
                                                          if (selecting) {
                                                            selection.toggle(
                                                              video.id,
                                                            );
                                                          } else {
                                                            unawaited(
                                                              open(
                                                                anchor:
                                                                    video.id,
                                                              ),
                                                            );
                                                          }
                                                        },
                                                  child:
                                                      const SizedBox.expand(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!selecting)
                                          IgnorePointer(
                                            child: Center(
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: p.dark
                                                      ? p.background.withValues(
                                                          alpha: .87,
                                                        )
                                                      : const Color(0xe6f7f6ed),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    7,
                                                  ),
                                                  child: PaperIcon(
                                                    PaperGlyph.play,
                                                    size: 20,
                                                    color: p.dark
                                                        ? p.ink
                                                        : const Color(
                                                            0xff526347,
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
                                              child: MediaSelectionMark(
                                                selected.contains(video.id),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          right: 5,
                                          bottom: 5,
                                          child: IgnorePointer(
                                            child: ColoredBox(
                                              color: Colors.black54,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                child: Text(
                                                  video.durationLabel,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    video.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: p.title.copyWith(
                                      fontSize: 16,
                                      height: 1.5,
                                    ),
                                  ),
                                  MediaCardCaption(
                                    tagKey: Key('video-tag-names-${video.id}'),
                                    metadata: video.portrait ? '竖屏' : '横屏',
                                    tags: video.tags
                                        .map(repo.tagName)
                                        .join(' · '),
                                    menuLabel: '视频操作 ${video.name}',
                                    onMenu:
                                        selecting ||
                                            busy ||
                                            repo.backupRestorePending
                                        ? null
                                        : () => actions(video),
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
                              child: PaperCircularProgressIndicator(
                                key: Key('library-loading-more'),
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
            MediaSelectionActions(
              kind: 'video',
              addTags: selected.isEmpty || selection.loading || busy
                  ? null
                  : () => editTags({...selected}, appendOnly: true),
              trash:
                  selected.isEmpty ||
                      selected.length > 1000 ||
                      selection.loading ||
                      busy
                  ? null
                  : () => removeVideos({...selected}),
            ),
          if (selecting && selected.length > 1000)
            note('每次最多移除 1000 个视频，请减少选择'),
        ],
      );
    },
  );
}
