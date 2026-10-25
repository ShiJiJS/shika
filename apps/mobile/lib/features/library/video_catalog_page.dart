import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/media_layout.dart';
import '../../ui/media_poster.dart';
import '../../ui/paper.dart';
import '../../ui/preferences.dart';
import '../../ui/player.dart' show timeLabel;
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
    required this.defaultOrder,
  });
  final LibraryRepository repository;
  final UiPreferences preferences;
  final VideoBrowseContext entry;
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
  VideoBrowseContext? pendingReturn;
  List<String> returnIds = const [];
  VideoLibraryState get data => query.state;
  double get stride =>
      MediaLayout.tile(width, scaler: MediaQuery.textScalerOf(context)) +
      MediaLayout.rowGap;
  double get listHeader =>
      MediaLayout.toolbar(context) +
      (entry.query.count > 0 || entry.search.isNotEmpty
          ? MediaLayout.scope(context)
          : 0);

  @override
  void initState() {
    super.initState();
    query.addListener(changed);
    repo.addListener(repositoryChanged);
    selection.addListener(changed);
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
        selection.cancel();
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
    final local = max(0, ((pixels - listHeader) / stride).floor() * 2);
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
    _positioning = restoring != null || before;
    if (restoring != null) {
      await query.restore(restoring, anchors: returnIds);
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
              ((data.anchorIndex ?? data.offset) - data.offset) ~/ 2 * stride +
              restoring.scrollInset;
          pendingReturn = null;
        } else if (before) {
          pixels = oldPixels + (oldStart - data.offset) ~/ 2 * stride;
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

  void toggleSelection() {
    selection.cancel();
    setState(() => selecting = !selecting);
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
    );
    if (mounted && widget.active) await load(restore: true);
  }

  Future<void> open({String? anchor, bool quick = false}) async {
    if (busy || viewing || repo.backupRestorePending || !widget.active) return;
    FocusScope.of(context).unfocus();
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
      final route = PageRouteBuilder<void>(
        transitionDuration: MediaLayout.motion(context, 240),
        reverseTransitionDuration: MediaLayout.motion(context, 160),
        pageBuilder: (context, animation, secondary) => VideoPreviewRoute(
          repository: repo,
          preferences: widget.preferences,
          origin: saved.context,
          quick: quick,
        ),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
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
    selection.removeListener(changed);
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
      width = constraints.maxWidth;
      final p = Paper.of(context), recent = entry.source == BrowseSource.recent;
      return Column(
        children: [
          if (!recent)
            MediaCatalogSearch(
              fieldKey: const Key('video-search'),
              controller: search,
              hint: '搜索视频名称、目录',
              filterLabel: '筛选视频',
              onFilter: filter,
              onChanged: (value) => changeEntry(entry.copyWith(search: value)),
            ),
          if (busy || (data.loading && data.items.isNotEmpty))
            const LinearProgressIndicator(minHeight: 2),
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
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      '当前列表已保留：${data.error}',
                      style: TextStyle(color: p.danger, fontSize: 12),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('library-return-retry'),
                  onPressed: () => pendingReturn != null
                      ? load()
                      : load(
                          more: !data.beforeFailure,
                          before: data.beforeFailure,
                        ),
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(
            child: data.loading && data.items.isEmpty
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
                    key: const Key('video-grid'),
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (entry.query.count > 0 || entry.search.isNotEmpty)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaLayout.scope(context),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      [
                                        if (entry.query.folder.isNotEmpty)
                                          entry.query.folder,
                                        ...entry.query.tags.map(
                                          (id) => '# ${repo.tagName(id)}',
                                        ),
                                        if (entry.search.isNotEmpty)
                                          '“${entry.search}”',
                                      ].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.olive,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      search.clear();
                                      await changeEntry(
                                        entry.copyWith(
                                          query: VideoQuery(),
                                          search: '',
                                        ),
                                      );
                                    },
                                    child: const Text('清除'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: MediaCatalogToolbar(
                          children: [
                            Text(
                              '${data.total} 个视频',
                              key: const Key('library-count'),
                              style: TextStyle(fontSize: 13, color: p.muted),
                            ),
                            if (!recent)
                              PopupMenuButton<VideoSort>(
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
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    entry.sort == VideoSort.newest
                                        ? '最近加入 ↓'
                                        : '名称 ↓',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            if (!selecting)
                              FilledButton.icon(
                                onPressed:
                                    busy ||
                                        data.items.isEmpty ||
                                        !repo.libraryPreparation.value.ready
                                    ? null
                                    : () => open(anchor: data.items.first.id),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(44, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.smart_display_outlined,
                                  size: 16,
                                ),
                                label: const Text(
                                  '预览此范围',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (data.items.isEmpty && !data.loading)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView(
                            recent
                                ? '还没有打开过视频'
                                : entry.query.count > 0 ||
                                      entry.search.isNotEmpty
                                ? '没有符合条件的视频'
                                : '视频库还是空的',
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MediaLayout.side,
                        ),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: MediaLayout.columnGap,
                                mainAxisSpacing: MediaLayout.rowGap,
                                mainAxisExtent: MediaLayout.tile(
                                  width,
                                  scaler: MediaQuery.textScalerOf(context),
                                ),
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
                                      InkWell(
                                        key: Key('tile-${video.id}'),
                                        onTap: busy
                                            ? null
                                            : () {
                                                if (selecting) {
                                                  selection.toggle(video.id);
                                                } else {
                                                  unawaited(
                                                    open(anchor: video.id),
                                                  );
                                                }
                                              },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                          child: ColoredBox(
                                            color: const Color(0xff20261f),
                                            child: MediaPoster(
                                              video: video,
                                              fit: BoxFit.contain,
                                              onUnauthorized: () => unawaited(
                                                repo.mediaUnauthorized(
                                                  video.source,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (!selecting)
                                        const IgnorePointer(
                                          child: Center(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Color(0xe6f7f6ed),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Padding(
                                                padding: EdgeInsets.all(7),
                                                child: Icon(
                                                  Icons.play_arrow_outlined,
                                                  size: 20,
                                                  color: Color(0xff526347),
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
                                              selected.contains(video.id)
                                                  ? Icons.check_circle
                                                  : Icons
                                                        .radio_button_unchecked,
                                              color: selected.contains(video.id)
                                                  ? p.olive
                                                  : Colors.white,
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
                                                timeLabel(
                                                  Duration(
                                                    seconds: video.seconds,
                                                  ),
                                                ),
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
                                  video.name,
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
                                          video.portrait ? '竖屏' : '横屏',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: p.muted,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '编辑标签 ${video.name}',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 28,
                                        ),
                                        iconSize: 18,
                                        onPressed: repo.backupRestorePending
                                            ? null
                                            : () => editTags({video.id}),
                                        icon: const Icon(Icons.more_horiz),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  video.tags
                                      .map((id) => '# ${repo.tagName(id)}')
                                      .join('  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
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
                                key: Key('library-loading-more'),
                              ),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 18)),
                    ],
                  ),
          ),
          if (selection.error.isNotEmpty) note(selection.error),
          if (selecting)
            SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const Key('video-select-all'),
                      onPressed: selection.loading
                          ? selection.cancel
                          : () => selection.all(
                              () => repo.selectVideoIds(entry.entry),
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
                      onPressed: selected.isEmpty || selection.loading
                          ? null
                          : () => editTags({...selected}, appendOnly: true),
                      child: const Text('追加标签', textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
