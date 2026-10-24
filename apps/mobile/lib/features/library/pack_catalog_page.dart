import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/media_layout.dart';
import '../../ui/paper.dart';
import '../packs/pack_sheets.dart';
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
        child: const Center(child: Icon(Icons.collections_outlined)),
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
  });
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
  PackBrowseContext? pendingReturn;
  List<String> returnIds = const [];
  String error = '';
  PackLibraryState get data => catalog.state;
  double get stride =>
      MediaLayout.tile(width, scaler: MediaQuery.textScalerOf(context)) +
      MediaLayout.rowGap;
  double get listHeader =>
      MediaLayout.toolbar(context) +
      (entry.query.count > 0 || entry.query.search.isNotEmpty
          ? MediaLayout.scope(context)
          : 0);
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
    final local = max(0, ((pixels - listHeader) / stride).floor() * 2);
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
        ((more || before) && data.loading)) {
      return;
    }
    final current = ++generation;
    final oldStart = data.offset,
        oldPixels = scroll.hasClients ? scroll.offset : 0.0;
    if (restore) remember();
    final restoring = pendingReturn;
    _positioning = restoring != null || before;
    if (restoring != null) {
      await catalog.restore(restoring, anchors: returnIds);
    } else {
      await catalog.load(entry, more: more, before: before);
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
        } else if (oldStart != data.offset && data.items.isNotEmpty) {
          pixels = oldPixels + (oldStart - data.offset) ~/ 2 * stride;
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
    selection.cancel();
    setState(() => selecting = !selecting);
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

  Future<void> details(LibraryPack pack) async {
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
            title: pack.name,
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
                title: const Text('整包标签'),
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

  @override
  void dispose() {
    generation++;
    repo.removeListener(repositoryChanged);
    selection.removeListener(changed);
    selection.dispose();
    catalog.removeListener(changed);
    catalog.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      width = box.maxWidth;
      final p = Paper.of(context), recent = entry.source == BrowseSource.recent;
      return Column(
        children: [
          if (!recent)
            SizedBox(
              height: MediaLayout.search(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    iconAction('筛选图包', Icons.filter_list, filter),
                    Expanded(
                      child: TextField(
                        key: const Key('pack-search'),
                        controller: search,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: '搜索图包名称、目录',
                          isDense: true,
                          contentPadding: EdgeInsets.all(12),
                        ),
                        onChanged: (value) =>
                            change(entry.query.copy(search: value)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (error.isNotEmpty) note(error),
          if (data.loading && data.items.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (data.error.isNotEmpty && data.items.isNotEmpty)
            Row(
              children: [
                Expanded(child: note('当前列表已保留：${data.error}')),
                TextButton(
                  key: const Key('pack-list-retry'),
                  onPressed: data.loading
                      ? null
                      : () => load(
                          more: data.retryMore,
                          before: data.retryBefore,
                          restore: data.retryRestore,
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
                    key: const Key('pack-grid'),
                    controller: scroll,
                    slivers: [
                      if (entry.query.count > 0 ||
                          entry.query.search.isNotEmpty)
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
                      SliverToBoxAdapter(
                        child: MediaCatalogToolbar(
                          children: [
                            Text(
                              '${data.total} 个图包',
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
                            PopupMenuButton<PackSort>(
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
                              child: Text(
                                entry.query.sort == PackSort.name
                                    ? '名称 ↓'
                                    : '最近加入 ↓',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (data.items.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyView('没有符合条件的图包'),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 18,
                                mainAxisExtent: MediaLayout.tile(
                                  box.maxWidth,
                                  scaler: MediaQuery.textScalerOf(context),
                                ),
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
                                                '${pack.pageCount} 张',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (pack.progress != null)
                                        Positioned(
                                          left: 5,
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
                                                  pack.progress!.completed
                                                      ? '已读'
                                                      : '在读',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
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
                                              color: selected.contains(pack.id)
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
                                  pack.name,
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
                                          '${pack.readableCount} 张可读',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: p.muted,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '图包操作 ${pack.name}',
                                        onPressed: () => details(pack),
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
                                Text(
                                  key: Key('pack-tag-names-${pack.id}'),
                                  pack.tags.isEmpty
                                      ? ''
                                      : pack.tagNames.isEmpty
                                      ? '${pack.tags.length} 个标签'
                                      : (pack.tagNames.values.toList()..sort())
                                            .map((name) => '# $name')
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
                                key: Key('pack-loading-more'),
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
                      onPressed: selected.isEmpty || selection.loading
                          ? null
                          : () => tags({...selected}, appendOnly: true),
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
