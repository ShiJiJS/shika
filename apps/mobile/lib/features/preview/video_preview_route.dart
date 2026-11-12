import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/browsing_session.dart';
import '../../ui/media_poster.dart';
import '../../ui/media_layout.dart';
import '../../ui/paper.dart';
import '../../ui/paper_icons.dart';
import '../../ui/playback_session.dart';
import '../../ui/player.dart';
import '../../ui/preferences.dart';
import '../../ui/sheets.dart';
import '../library/browse_context.dart';

/// A secondary destination. Its entry context belongs to the page underneath.
class VideoPreviewRoute extends StatefulWidget {
  const VideoPreviewRoute({
    super.key,
    required this.repository,
    required this.preferences,
    required this.origin,
    this.quick = false,
  });
  final LibraryRepository repository;
  final UiPreferences preferences;
  final VideoBrowseContext origin;
  final bool quick;
  @override
  State<VideoPreviewRoute> createState() => _VideoPreviewRouteState();
}

class _VideoPreviewRouteState extends State<VideoPreviewRoute>
    with WidgetsBindingObserver {
  LibraryRepository get repo => widget.repository;
  late final browsing = BrowsingSession(repo, recordOpens: true);
  final playback = PlaybackSession();
  late bool quick = widget.quick;
  bool busy = false, obscured = false;
  String error = '', notice = '';
  Timer? noticeTimer;
  String? noticeRequest;
  DeleteOperation? undo;
  bool leaving = false;
  bool closing = false;
  LibrarySnapshot get data => browsing.snapshot;
  late final String sourceLabel = describeSource();
  String describeSource() {
    final entry = widget.origin;
    return [
      switch (entry.source) {
        BrowseSource.library => '媒体库',
        BrowseSource.tags => '标签',
        BrowseSource.recent => '最近',
      },
      if (entry.query.count == 0 && entry.search.isEmpty)
        entry.source == BrowseSource.recent ? '最近看过的视频' : '全部视频',
      if (entry.query.folder.isNotEmpty) basename(entry.query.folder),
      ...entry.query.tags.map((tag) => '# ${repo.tagName(tag)}'),
      if (entry.search.isNotEmpty) '“${entry.search}”',
      if (entry.query.orientation.isNotEmpty)
        entry.query.orientation == 'portrait' ? '竖版' : '横版',
      if (entry.query.duration.isNotEmpty)
        entry.query.duration == 'short' ? '10 秒以内' : '10 秒以上',
      if (entry.query.type.isNotEmpty) entry.query.type,
    ].join(' · ');
  }

  Future<void> leave() async {
    if (closing) return;
    setState(() => closing = true);
    browsing.setVisible(false);
    // Unmount native views before releasing their platform player IDs. The
    // route can still rebuild while its reverse transition is on screen.
    await WidgetsBinding.instance.endOfFrame;
    await playback.close();
    if (!mounted) return;
    setState(() => leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    browsing.addListener(changed);
    widget.preferences.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) browsing.setVisible(true);
    });
  }

  void changed() {
    if (!mounted) return;
    if (!data.connected) {
      unawaited(leave());
      return;
    }
    setState(() {
      if (browsing.message != null) {
        error = browsing.message!;
        browsing.message = null;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      browsing.setVisible(state == AppLifecycleState.resumed && !obscured);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    noticeTimer?.cancel();
    widget.preferences.removeListener(changed);
    browsing.removeListener(changed);
    browsing.dispose();
    unawaited(playback.close());
    super.dispose();
  }

  Future<bool> run(Future<void> Function() action) async {
    if (busy || repo.backupRestorePending) return false;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
      return true;
    } on RequestCancelled {
      return false;
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<T?> sheet<T>(
    Widget child, {
    BoxConstraints? constraints,
    bool dismissible = true,
  }) async {
    setState(() => obscured = true);
    browsing.setVisible(false);
    try {
      return await paperSheet<T>(
        context,
        child,
        constraints: constraints,
        dismissible: dismissible,
      );
    } finally {
      if (mounted) {
        setState(() => obscured = false);
        browsing.setVisible(true);
      }
    }
  }

  Future<void> tags() async {
    final id = browsing.current?.id;
    if (id == null) return;
    await sheet<bool>(
      TagEditor(repository: repo, ids: {id}, initial: browsing.current!.tags),
      dismissible: false,
    );
  }

  Future<void> queue() => sheet<void>(
    PreviewQueueSheet(
      repository: repo,
      sourceLabel: sourceLabel,
      onOrder: (order) => browsing.changeOrder(order),
      onPick: browsing.choose,
    ),
    constraints: const BoxConstraints(maxWidth: double.infinity),
  );

  Future<bool> step(int delta) async {
    if (busy || obscured || browsing.current == null) return false;
    if (delta > 0 && browsing.position + 1 >= repo.playbackTotal) {
      unawaited(
        browsing.finish().catchError((Object failure) {
          if (mounted && failure is! RequestCancelled) {
            setState(() => error = failure.toString());
          }
        }),
      );
      if (!mounted) return false;
      final action = await sheet<String>(
        SheetFrame(
          title: '本次范围已到末尾',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: Paper.of(context).olive,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    Text(sourceLabel),
                    Text('共 ${repo.playbackTotal} 个视频'),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('preview-restart'),
                    onPressed: () => Navigator.pop(context, 'restart'),
                    child: const Text('再看一遍'),
                  ),
                ),
                Expanded(
                  child: FilledButton(
                    key: const Key('preview-end-return'),
                    onPressed: () => Navigator.pop(context, 'return'),
                    child: const Text('返回来源'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      if (!mounted) return false;
      if (action == 'return') {
        await leave();
      }
      if (action == 'restart') {
        await run(() => browsing.changeOrder(data.order, restart: true));
      }
      return false;
    }
    return browsing.step(delta);
  }

  Future<void> remove(String id) async {
    final key = 'delete-${DateTime.now().microsecondsSinceEpoch}';
    final previous = repo.snapshot.lastDelete?.id;
    noticeTimer?.cancel();
    setState(() {
      noticeRequest = key;
      notice = '正在移入回收站…';
      undo = null;
    });
    noticeTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          notice = '';
          undo = null;
        });
      }
    });
    var completed = false;
    try {
      await browsing.delete({id}, key);
      completed = true;
    } on RequestCancelled {
      return;
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = repo.fileOperationPending
              ? '删除结果待确认，可返回设置查询结果'
              : '删除未完成：$failure',
        );
      }
    }
    if (!mounted || noticeRequest != key) return;
    final operation = repo.snapshot.lastDelete;
    setState(() {
      if (operation != null && operation.id != previous && notice.isNotEmpty) {
        notice = completed ? '已移入回收站' : '部分内容已移入回收站';
        undo = operation;
      } else if (!completed) {
        notice = '';
      }
    });
  }

  Future<void> more() async {
    final action = await sheet<String>(
      SheetFrame(
        title: '视频操作',
        children: [
          ListTile(
            title: const Text('视频详情'),
            onTap: () => Navigator.pop(context, 'details'),
          ),
          ListTile(
            title: Text(widget.preferences.dark ? '切换浅色模式' : '切换暗黑模式'),
            onTap: () => Navigator.pop(context, 'theme'),
          ),
          ListTile(
            title: const Text('本次预览范围'),
            onTap: () => Navigator.pop(context, 'queue'),
          ),
          ListTile(
            title: Text(quick ? '退出快速整理' : '进入快速整理'),
            onTap: () => Navigator.pop(context, 'quick'),
          ),
          ListTile(
            title: Text(
              '移入回收站',
              style: TextStyle(color: Paper.of(context).danger),
            ),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final video = browsing.current;
    switch (action) {
      case 'theme':
        await run(() => widget.preferences.setDark(!widget.preferences.dark));
      case 'queue':
        await queue();
      case 'quick':
        setState(() => quick = !quick);
      case 'tags':
        await tags();
      case 'details':
        if (video != null) {
          await sheet<void>(
            SheetFrame(
              title: '视频详情',
              children: [
                Text(
                  video.name,
                  style: Paper.of(context).title.copyWith(fontSize: 18),
                ),
                note(
                  '${video.portrait ? '竖版' : '横版'} · ${video.seconds} 秒 · ${video.type}',
                ),
                SelectableText(video.path),
                note(
                  video.tags
                      .map(repo.tagName)
                      .map((name) => '# $name')
                      .join(' · '),
                ),
              ],
            ),
          );
        }
      case 'delete':
        if (video != null) {
          final confirmed = await sheet<bool>(
            SheetFrame(
              title: '移入回收站',
              children: [
                Text(video.name),
                note('从媒体库和当前预览中移除，保留源文件和标签，可以在回收站恢复。'),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('移入回收站'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
          if (confirmed == true && mounted) await remove(video.id);
        }
    }
  }

  Widget tool(
    PaperGlyph icon,
    String label,
    VoidCallback action, {
    bool selected = false,
    Key? key,
  }) => Expanded(
    child: TextButton(
      key: key,
      onPressed: busy ? null : action,
      style: TextButton.styleFrom(
        backgroundColor: selected ? Paper.of(context).soft : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        padding: const EdgeInsets.symmetric(vertical: 7),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaperIcon(icon),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final current = browsing.current, p = Paper.of(context);
    final enlarged = MediaQuery.textScalerOf(context).scale(12) > 16;
    final disabled = busy || current == null || repo.backupRestorePending;
    final quickTag = TextButton(
      onPressed: disabled ? null : tags,
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: const TextStyle(fontSize: 13),
      ),
      child: const Text('打标签'),
    );
    final quickDelete = TextButton(
      key: const Key('preview-quick-delete'),
      onPressed: disabled ? null : () => remove(current.id),
      style: TextButton.styleFrom(
        foregroundColor: p.danger,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: const TextStyle(fontSize: 13),
      ),
      child: const Text('移入回收站'),
    );
    return PopScope<void>(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: Scaffold(
        key: const Key('video-preview-route'),
        backgroundColor: p.background,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.line)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('preview-back'),
                      tooltip: '返回来源',
                      onPressed: leave,
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    ),
                    Expanded(
                      child: Text(
                        '视频预览',
                        style: p.title.copyWith(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      tooltip: '视频操作',
                      onPressed: busy ? null : more,
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ],
                ),
              ),
              InkWell(
                key: const Key('preview-scope'),
                onTap: busy ? null : queue,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sourceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.olive, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${current == null ? 0 : browsing.position + 1} / ${repo.playbackTotal}',
                        key: const Key('preview-position'),
                        style: p.title.copyWith(color: p.olive, fontSize: 14),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.grid_view, size: 19),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    closing
                        ? const ColoredBox(color: Colors.black)
                        : current == null || !data.connected
                        ? EmptyView(
                            data.connected ? '本次范围已没有可播放的视频' : '连接已失效，请返回重新连接',
                            action: TextButton(
                              onPressed: leave,
                              child: const Text('返回来源'),
                            ),
                          )
                        : Theme(
                            data: Paper.darkTheme,
                            child: MovieStage(
                              key: ValueKey(repo.playbackIdentity),
                              videos: [
                                for (final id in data.round)
                                  data.videos.firstWhere(
                                    (video) => video.id == id,
                                  ),
                              ],
                              index: data.position,
                              onStep: step,
                              suspended: obscured || repo.backupRestorePending,
                              session: playback,
                              inlineControls: true,
                              preloadAdjacent:
                                  widget.preferences.preloadAdjacent,
                              onUnauthorized: (source) =>
                                  unawaited(repo.mediaUnauthorized(source)),
                              onPlaybackFailure: (video) async {
                                final identity = repo.playbackIdentity;
                                final message = await repo.playbackFailure(
                                  video.source,
                                );
                                // Recovery can dispose the failed page while
                                // selecting its successor. Keep the explanation
                                // on this route, after the old decoder is gone.
                                if (mounted &&
                                    !closing &&
                                    repo.playbackIdentity == identity &&
                                    message != null &&
                                    browsing.current?.id != video.id) {
                                  setState(() => error = message);
                                }
                                return message;
                              },
                            ),
                          ),
                    if (notice.isNotEmpty)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Material(
                          color: p.soft.withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    notice,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (undo != null)
                                  TextButton(
                                    onPressed: () async {
                                      final operation = undo!;
                                      if (await run(
                                            () => repo.undoDelete(
                                              operationId: operation.id,
                                            ),
                                          ) &&
                                          mounted) {
                                        setState(() {
                                          notice = '';
                                          undo = null;
                                        });
                                      }
                                    },
                                    child: const Text('撤销'),
                                  )
                                else
                                  const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (error.isNotEmpty)
                Material(
                  color: p.soft,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text(
                            error,
                            key: const Key('preview-error'),
                            style: TextStyle(fontSize: 12, color: p.danger),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭提示',
                        onPressed: () => setState(() => error = ''),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    tool(
                      PaperGlyph.shuffle,
                      data.order == PlayOrder.random ? '随机预览' : '顺序预览',
                      queue,
                    ),
                    if (!quick) tool(PaperGlyph.tag, '视频标签', tags),
                    tool(
                      PaperGlyph.filter,
                      '快速整理',
                      () => setState(() => quick = !quick),
                      selected: quick,
                      key: const Key('preview-quick'),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                alignment: Alignment.topCenter,
                child: quick
                    ? Container(
                        key: const Key('preview-cleanup'),
                        color: p.soft,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            if (!enlarged) ...[
                              const Text(
                                '快速整理',
                                style: TextStyle(fontSize: 13),
                              ),
                              const Spacer(),
                              quickTag,
                              const SizedBox(width: 7),
                              quickDelete,
                            ] else ...[
                              Expanded(flex: 2, child: quickTag),
                              const SizedBox(width: 8),
                              Expanded(flex: 3, child: quickDelete),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 6),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.line)),
                ),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('preview-previous'),
                      onPressed: disabled || browsing.position == 0
                          ? null
                          : () => step(-1),
                      child: const Row(
                        children: [
                          Icon(Icons.keyboard_arrow_up, size: 18),
                          Text('上一条'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        browsing.position + 1 >= repo.playbackTotal
                            ? '本次范围最后一条'
                            : '上下滑动切换',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                    ),
                    TextButton(
                      key: const Key('preview-next'),
                      onPressed: disabled ? null : () => step(1),
                      child: Row(
                        children: [
                          Text(
                            browsing.position + 1 >= repo.playbackTotal
                                ? '结束'
                                : '下一条',
                          ),
                          const Icon(Icons.keyboard_arrow_down, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Random-access paging keeps long queues bounded to four metadata pages.
class PreviewQueueSheet extends StatefulWidget {
  const PreviewQueueSheet({
    super.key,
    required this.repository,
    required this.sourceLabel,
    required this.onOrder,
    required this.onPick,
  });
  final LibraryRepository repository;
  final String sourceLabel;
  final Future<void> Function(PlayOrder) onOrder;
  final Future<void> Function(String) onPick;
  @override
  State<PreviewQueueSheet> createState() => _PreviewQueueSheetState();
}

class _PreviewQueueSheetState extends State<PreviewQueueSheet> {
  static const pageSize = 48;
  LibraryRepository get repo => widget.repository;
  final pages = <int, List<LibraryVideo>>{}, failures = <int, String>{};
  final loading = <int>{};
  final scroll = ScrollController();
  final summaryKey = GlobalKey();
  double rowExtent = 80;
  (double, double)? geometry;
  bool locateScheduled = false;

  void locateCurrent() {
    if (locateScheduled) return;
    locateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      locateScheduled = false;
      if (!mounted || !scroll.hasClients) return;
      final prefix = summaryKey.currentContext?.size?.height;
      if (prefix == null) return;
      final target = repo.playbackPosition == 0
          ? 0.0
          : prefix + repo.playbackPosition * rowExtent;
      scroll.jumpTo(target.clamp(0.0, scroll.position.maxScrollExtent));
    });
  }

  late String sequence;
  late int total;
  int generation = 0;
  bool busy = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    sequence = repo.playbackSequenceIdentity;
    total = repo.playbackTotal;
    repo.addListener(changed);
  }

  @override
  void dispose() {
    generation++;
    repo.removeListener(changed);
    scroll.dispose();
    super.dispose();
  }

  void changed() {
    if (!mounted) return;
    setState(() {
      if (sequence != repo.playbackSequenceIdentity ||
          total != repo.playbackTotal) {
        sequence = repo.playbackSequenceIdentity;
        generation++;
        pages.clear();
        failures.clear();
        loading.clear();
        total = repo.playbackTotal;
        locateCurrent();
      }
    });
  }

  void ensure(int page) {
    if (pages.containsKey(page) ||
        failures.containsKey(page) ||
        !loading.add(page)) {
      return;
    }
    final epoch = generation;
    scheduleMicrotask(() async {
      try {
        final result = await repo.loadPlaybackVideos(
          offset: page,
          limit: pageSize,
        );
        if (!mounted || epoch != generation) return;
        setState(() {
          total = result.total;
          if (result.items.isEmpty && page < total) {
            failures[page] = '队列已变化，请重试';
          } else {
            pages[page] = result.items;
          }
          while (pages.length > 4) {
            pages.remove(pages.keys.first);
          }
        });
      } on RequestCancelled {
        if (mounted && epoch == generation) {
          setState(() => failures[page] = '队列已变化，请重试');
        }
      } catch (failure) {
        if (mounted && epoch == generation) {
          setState(() => failures[page] = failure.toString());
        }
      } finally {
        if (epoch == generation) loading.remove(page);
      }
    });
  }

  Future<void> action(
    Future<void> Function() work, {
    bool close = false,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await work();
      if (mounted && close) Navigator.pop(context);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextGeometry = (
      MediaQuery.sizeOf(context).width,
      MediaQuery.textScalerOf(context).scale(14),
    );
    rowExtent =
        (MediaLayout.line(context, '视频名称 Aa', const TextStyle(fontSize: 14)) *
                    2 +
                24)
            .clamp(81.0, double.infinity);
    if (geometry != nextGeometry) {
      geometry = nextGeometry;
      locateCurrent();
    }
    final p = Paper.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      key: const Key('preview-queue-frame'),
      constraints: BoxConstraints(
        maxHeight: height * (height <= 700 ? .92 : .88),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final style = p.title.copyWith(fontSize: 23);
                        final measure = TextPainter(
                          text: TextSpan(
                            text: '本次预览范围',
                            style: DefaultTextStyle.of(context).style
                                .merge(style),
                          ),
                          textScaler: MediaQuery.textScalerOf(context),
                          textDirection: Directionality.of(context),
                          locale: Localizations.maybeLocaleOf(context),
                        )..layout();
                        final wrap = measure.width > constraints.maxWidth;
                        measure.dispose();
                        return Text(
                          wrap ? '本次预览\n范围' : '本次预览范围',
                          key: const Key('preview-queue-title'),
                          semanticsLabel: '本次预览范围',
                          style: style,
                        );
                      },
                    ),
                  ),
                  iconAction('关闭面板', Icons.close, () => Navigator.pop(context)),
                ],
              ),
              Flexible(
                child: CustomScrollView(
                  key: const Key('preview-queue'),
                  controller: scroll,
                  shrinkWrap: true,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        key: summaryKey,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5, bottom: 20),
                            child: DefaultTextStyle(
                              style: DefaultTextStyle.of(context).style.merge(
                                TextStyle(
                                  fontSize: 13,
                                  height: 1.7,
                                  color: p.catalogMeta,
                                ),
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(widget.sourceLabel),
                                  Text(
                                    '$total 个视频',
                                    key: const Key('preview-queue-count'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 10,
                            children: [
                              for (final order in [
                                PlayOrder.sequential,
                                PlayOrder.random,
                              ])
                                PaperChoiceChip(
                                  key: Key('queue-order-${order.name}'),
                                  label: Text(
                                    order == PlayOrder.random ? '随机' : '顺序',
                                  ),
                                  selected: repo.snapshot.order == order,
                                  showCheckmark: false,
                                  selectedColor: p.olive,
                                  backgroundColor: p.background,
                                  shape: const StadiumBorder(),
                                  side: BorderSide(
                                    color: repo.snapshot.order == order
                                        ? p.olive
                                        : p.olive.withValues(alpha: .35),
                                  ),
                                  labelStyle: TextStyle(
                                    color: repo.snapshot.order == order
                                        ? p.background
                                        : p.olive,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  onSelected: busy
                                      ? null
                                      : (_) =>
                                            action(() => widget.onOrder(order)),
                                ),
                            ],
                          ),
                          if (error.isNotEmpty) note(error),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                    if (total == 0)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('本次范围已没有可播放的视频'),
                        ),
                      )
                    else
                      SliverFixedExtentList(
                        itemExtent: rowExtent,
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final page = (index ~/ pageSize) * pageSize;
                          ensure(page);
                          final cached = pages[page];
                          final local = index - page;
                          final video = cached != null && local < cached.length
                              ? cached[local]
                              : null;
                          if (video == null) {
                            return Center(
                              child: failures[page] == null
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: () => setState(() {
                                        failures.remove(page);
                                      }),
                                      child: const Text('队列读取失败，重试'),
                                    ),
                            );
                          }
                          return Material(
                            color: repo.current?.id == video.id
                                ? Paper.of(context).soft
                                : Colors.transparent,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: p.line),
                                ),
                              ),
                              child: InkWell(
                                key: Key('queue-video-${video.id}'),
                                onTap: busy
                                    ? null
                                    : () => action(
                                        () => widget.onPick(video.id),
                                        close: true,
                                      ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 27,
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 42,
                                        height: 56,
                                        child: MediaPoster(video: video),
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Text(
                                          video.displayTitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (repo.current?.id == video.id)
                                        const Text(
                                          '当前',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }, childCount: total),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 4),
                        child: Text(
                          '修改标签不改变本次范围；返回后更新筛选结果。',
                          key: const Key('preview-queue-note'),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.8,
                            color: p.catalogMeta,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
