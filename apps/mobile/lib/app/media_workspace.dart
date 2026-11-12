import 'dart:async';

import 'package:flutter/material.dart';

import '../features/library/browse_context.dart';
import '../features/library/pack_catalog_page.dart';
import '../features/library/tag_catalog_page.dart';
import '../features/library/video_catalog_page.dart';
import '../features/settings/scan_progress_card.dart';
import '../library/models.dart';
import '../library/repository.dart';
import '../ui/media_layout.dart';
import '../ui/paper.dart';
import '../ui/paper_icons.dart';
import '../ui/preferences.dart';
import 'app_shell.dart';

class MediaWorkspace extends StatefulWidget {
  const MediaWorkspace({
    super.key,
    required this.repository,
    required this.preferences,
    required this.destination,
    required this.active,
    required this.onNavigate,
    required this.settings,
    required this.status,
    required this.defaultOrder,
  });
  final LibraryRepository repository;
  final UiPreferences preferences;
  final String destination;
  final bool active;
  final ValueChanged<String> onNavigate;
  final Widget settings, status;
  final PlayOrder defaultOrder;
  @override
  State<MediaWorkspace> createState() => _MediaWorkspaceState();
}

class _MediaWorkspaceState extends State<MediaWorkspace> {
  final kinds = {
    'library': MediaKind.video,
    'tags': MediaKind.video,
    'recent': MediaKind.video,
  };
  final libraryVideo = GlobalKey<VideoCatalogPageState>(),
      recentVideo = GlobalKey<VideoCatalogPageState>(),
      tagsVideo = GlobalKey<VideoCatalogPageState>();
  final libraryPack = GlobalKey<PackCatalogPageState>(),
      recentPack = GlobalKey<PackCatalogPageState>(),
      tagsPack = GlobalKey<PackCatalogPageState>();
  final videoTags = GlobalKey<TagCatalogPageState>(),
      packTags = GlobalKey<TagCatalogPageState>();
  late final saved = widget.repository.savedPreviewEntry;
  late final initialLibrary = saved?.source == BrowseSource.library
      ? VideoBrowseContext(
          query: saved!.query,
          search: saved!.search,
          source: saved!.source,
          sort: saved!.sort,
        )
      : VideoBrowseContext(sort: VideoSort.name);
  late VideoBrowseContext tagResultsVideo = saved?.source == BrowseSource.tags
      ? VideoBrowseContext(
          query: saved!.query,
          search: saved!.search,
          source: BrowseSource.tags,
          sort: saved!.sort,
        )
      : VideoBrowseContext(source: BrowseSource.tags, sort: VideoSort.name);
  late final initialRecent = VideoBrowseContext(
    source: BrowseSource.recent,
    sort: VideoSort.recent,
  );
  PackBrowseContext tagResultsPack = PackBrowseContext(
    source: BrowseSource.tags,
  );
  bool showingTagResults = false;
  MediaKind get kind => kinds[widget.destination] ?? MediaKind.video;
  bool get pack => kind == MediaKind.pack;
  int get index => switch (widget.destination) {
    'settings' => 8,
    'recent' => pack ? 7 : 6,
    'tags' =>
      showingTagResults
          ? pack
                ? 5
                : 4
          : pack
          ? 3
          : 2,
    _ => pack ? 1 : 0,
  };
  VideoCatalogPageState? get currentVideo => switch (index) {
    0 => libraryVideo.currentState,
    4 => tagsVideo.currentState,
    6 => recentVideo.currentState,
    _ => null,
  };
  PackCatalogPageState? get currentPack => switch (index) {
    1 => libraryPack.currentState,
    5 => tagsPack.currentState,
    7 => recentPack.currentState,
    _ => null,
  };
  bool selectionFramePending = false;
  bool get selecting =>
      currentPack?.selecting ?? currentVideo?.selecting ?? false;
  int get selectedCount =>
      currentPack?.selected.length ?? currentVideo?.selected.length ?? 0;
  bool get selectingAll =>
      currentPack?.selection.loading ??
      currentVideo?.selection.loading ??
      false;
  bool get fullySelected =>
      selectedCount > 0 &&
      selectedCount == (currentPack?.data.total ?? currentVideo?.data.total);

  void selectionChanged() {
    // Child activation can clear a selection during layout. Refresh the shared
    // header after the frame, never setState on an ancestor during its build.
    if (selectionFramePending) return;
    selectionFramePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      selectionFramePending = false;
      if (mounted) setState(() {});
    });
  }

  void toggleSelection() {
    FocusManager.instance.primaryFocus?.unfocus();
    pack ? currentPack?.toggleSelection() : currentVideo?.toggleSelection();
    selectionChanged();
  }

  void endSelection() {
    if (selecting) toggleSelection();
  }

  void selectAll() {
    pack ? currentPack?.selectAll() : currentVideo?.selectAll();
  }

  void navigate(String destination) {
    FocusScope.of(context).unfocus();
    if (destination != widget.destination) endSelection();
    if (destination != 'tags') showingTagResults = false;
    widget.onNavigate(destination);
  }

  void kindChanged(MediaKind value) {
    FocusScope.of(context).unfocus();
    if (value != kind) endSelection();
    setState(() => kinds[widget.destination] = value);
    if (widget.destination == 'library' &&
        widget.repository.catalogCounts.value == null) {
      unawaited(widget.repository.refreshCatalogCounts());
    }
  }

  Future<void> resumePack(PackCleanupContext origin, String identity) async {
    if (!mounted ||
        !widget.active ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final destination = switch (origin.entry.source) {
      BrowseSource.library => 'library',
      BrowseSource.tags => 'tags',
      BrowseSource.recent => 'recent',
    };
    setState(() {
      kinds[destination] = MediaKind.pack;
      showingTagResults = destination == 'tags';
      if (showingTagResults) {
        tagResultsPack = PackBrowseContext(query: origin.entry.query);
      }
    });
    widget.onNavigate(destination);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || widget.destination != destination || !widget.active) return;
    final page = switch (destination) {
      'tags' => tagsPack.currentState,
      'recent' => recentPack.currentState,
      _ => libraryPack.currentState,
    };
    await page?.resumeFromCleanup(origin, identity);
  }

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    final media = MediaQuery.of(context);
    final compactKeyboard =
        media.viewInsets.bottom > 0 &&
        media.size.height - media.viewInsets.bottom - media.padding.vertical <
            MediaLayout.headerExtent(context) +
                MediaLayout.kindExtent(context) +
                MediaLayout.search(context) +
                MediaLayout.scope(context) +
                MediaLayout.toolbar(context);
    final title = switch (widget.destination) {
      'settings' => '设置',
      'recent' => '最近看过',
      'tags' => showingTagResults ? '标签结果' : '标签',
      _ => '媒体库',
    };
    bool active(int slot) => widget.active && index == slot;
    return PopScope<void>(
      canPop:
          !widget.active ||
          (widget.destination == 'library' && !showingTagResults && !selecting),
      onPopInvokedWithResult: (didPop, result) {
        // Offstage preserves catalogue state, but must not handle a management
        // page's return or mutate its destination before that page handles it.
        if (didPop || !widget.active) return;
        if (selecting) {
          endSelection();
        } else if (showingTagResults) {
          setState(() => showingTagResults = false);
        } else {
          navigate('library');
        }
      },
      child: AppShell(
        showNavigation: !selecting,
        navigationExtent: MediaLayout.navigation,
        navigationWidth: 320,
        selected: widget.destination,
        onNavigate: navigate,
        destinations: const [
          AppDestination(
            'library',
            '媒体库',
            Icons.grid_view,
            glyph: PaperGlyph.grid,
          ),
          AppDestination(
            'tags',
            '标签',
            Icons.sell_outlined,
            glyph: PaperGlyph.tag,
          ),
          AppDestination(
            'recent',
            '最近',
            Icons.history,
            glyph: PaperGlyph.history,
          ),
          AppDestination(
            'settings',
            '设置',
            Icons.settings_outlined,
            glyph: PaperGlyph.settings,
          ),
        ],
        header: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compactKeyboard)
              Container(
                height: MediaLayout.headerExtent(context),
                padding: const EdgeInsets.only(left: 20, right: 12),
                decoration: BoxDecoration(
                  border: selecting
                      ? Border(bottom: BorderSide(color: p.line))
                      : null,
                ),
                child: Row(
                  children: [
                    if (selecting)
                      TextButton(
                        key: const Key('catalog-selection-cancel'),
                        onPressed: endSelection,
                        child: const Text('取消'),
                      ),
                    if (!selecting &&
                        widget.destination == 'tags' &&
                        showingTagResults)
                      iconAction(
                        '返回标签选择',
                        Icons.arrow_back,
                        () => setState(() => showingTagResults = false),
                      ),
                    Expanded(
                      child: Align(
                        alignment: selecting
                            ? Alignment.center
                            : Alignment.centerLeft,
                        child: AnimatedSwitcher(
                          duration: MediaLayout.motion(context, 160),
                          child: Text(
                            key: ValueKey(selecting),
                            selecting ? '已选 $selectedCount' : title,
                            style: selecting
                                ? const TextStyle(fontSize: 16)
                                : p.title.copyWith(fontSize: 24),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    if (widget.destination == 'tags' && !showingTagResults)
                      iconAction(
                        '新建${pack ? '图包' : '视频'}标签',
                        Icons.add,
                        widget.repository.backupRestorePending
                            ? null
                            : () => (pack ? packTags : videoTags).currentState
                                  ?.form(),
                      ),
                    if (selecting)
                      TextButton(
                        key: ValueKey(
                          pack ? 'pack-select-all' : 'video-select-all',
                        ),
                        onPressed: widget.repository.backupRestorePending
                            ? null
                            : selectAll,
                        child: Text(
                          selectingAll || fullySelected ? '取消全选' : '全选',
                        ),
                      ),
                  ],
                ),
              ),
            widget.status,
            if (widget.destination == 'library' && !compactKeyboard)
              ValueListenableBuilder<LibraryPreparation>(
                valueListenable: widget.repository.libraryPreparation,
                builder: (context, state, _) {
                  final roots = widget.repository.snapshot.roots;
                  final attention =
                      state.scanning ||
                      state.syncError != null ||
                      (!widget.repository.capabilities.rootScanProgress &&
                          state.legacyNeedsAttention) ||
                      (widget.repository.capabilities.rootScanProgress &&
                          roots.any(
                            (r) => r.enabled && !state.rootProgress(r.id).known,
                          )) ||
                      roots.any(
                        (r) =>
                            r.enabled &&
                            state.rootProgress(r.id).needsAttention,
                      );
                  if (!attention) return const SizedBox();
                  return Padding(
                    key: const Key('library-scan-notice'),
                    padding: const EdgeInsets.only(left: 20, right: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            scanActivityLabel(
                              state,
                              roots,
                              precise: widget
                                  .repository
                                  .capabilities
                                  .rootScanProgress,
                            ),
                            style: TextStyle(fontSize: 12, color: p.olive),
                          ),
                        ),
                        TextButton(
                          onPressed: () => navigate('roots'),
                          child: const Text('查看进度'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            if (widget.destination != 'settings' && !selecting)
              SizedBox(
                width: double.infinity,
                height: MediaLayout.kindExtent(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ValueListenableBuilder<MediaCatalogCounts?>(
                    valueListenable: widget.repository.catalogCounts,
                    builder: (context, counts, _) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final value in MediaKind.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 24),
                              child: InkWell(
                                key: Key('kind-${value.name}'),
                                onTap: () => kindChanged(value),
                                child: AnimatedContainer(
                                  constraints: const BoxConstraints(
                                    minWidth: 56,
                                  ),
                                  duration: MediaLayout.motion(context, 160),
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: kind == value
                                            ? p.olive
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        value == MediaKind.video ? '视频' : '图包',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: kind == value
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: kind == value
                                              ? p.ink
                                              : p.muted,
                                        ),
                                      ),
                                      if (widget.destination == 'library' &&
                                          widget
                                              .repository
                                              .capabilities
                                              .mediaCatalogCounts) ...[
                                        const SizedBox(width: 7),
                                        Tooltip(
                                          message: counts == null
                                              ? '数量暂不可用，点选分类重试'
                                              : '全部可浏览的${value == MediaKind.video ? '视频' : '图包'}',
                                          child: Text(
                                            counts?.forKind(value).toString() ??
                                                '—',
                                            key: Key(
                                              'catalog-count-${value.name}',
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: p.muted,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        content: IndexedStack(
          index: index,
          children: [
            VideoCatalogPage(
              key: libraryVideo,
              repository: widget.repository,
              preferences: widget.preferences,
              entry: initialLibrary,
              onSelectionChanged: selectionChanged,
              active: active(0),
              defaultOrder: widget.defaultOrder,
            ),
            PackCatalogPage(
              key: libraryPack,
              onResumeReading: resumePack,
              repository: widget.repository,
              entry: PackBrowseContext(),
              onSelectionChanged: selectionChanged,
              active: active(1),
            ),
            TagCatalogPage(
              key: videoTags,
              repository: widget.repository,
              kind: MediaKind.video,
              active: active(2),
              initial: saved?.source == BrowseSource.tags
                  ? saved!.query.tags
                  : const {},
              onView: (tags) => setState(() {
                tagResultsVideo = VideoBrowseContext(
                  query: VideoQuery(tags: tags),
                  source: BrowseSource.tags,
                  sort: VideoSort.name,
                );
                showingTagResults = true;
              }),
            ),
            TagCatalogPage(
              key: packTags,
              repository: widget.repository,
              kind: MediaKind.pack,
              active: active(3),
              onView: (tags) => setState(() {
                tagResultsPack = PackBrowseContext(
                  query: PackQuery(tags: tags),
                  source: BrowseSource.tags,
                );
                showingTagResults = true;
              }),
            ),
            VideoCatalogPage(
              key: tagsVideo,
              repository: widget.repository,
              preferences: widget.preferences,
              entry: tagResultsVideo,
              onSelectionChanged: selectionChanged,
              active: active(4),
              defaultOrder: widget.defaultOrder,
            ),
            PackCatalogPage(
              key: tagsPack,
              onResumeReading: resumePack,
              repository: widget.repository,
              entry: tagResultsPack,
              onSelectionChanged: selectionChanged,
              active: active(5),
            ),
            VideoCatalogPage(
              key: recentVideo,
              repository: widget.repository,
              preferences: widget.preferences,
              entry: initialRecent,
              onSelectionChanged: selectionChanged,
              active: active(6),
              defaultOrder: widget.defaultOrder,
            ),
            PackCatalogPage(
              key: recentPack,
              onResumeReading: resumePack,
              repository: widget.repository,
              entry: PackBrowseContext(source: BrowseSource.recent),
              onSelectionChanged: selectionChanged,
              active: active(7),
            ),
            widget.settings,
          ],
        ),
      ),
    );
  }
}
