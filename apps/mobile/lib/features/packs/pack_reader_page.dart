import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/media_layout.dart';
import '../../ui/paper.dart';
import 'pack_reading_session.dart';
import 'reader_images.dart';

class PackReaderPage extends StatefulWidget {
  const PackReaderPage({
    super.key,
    required this.repository,
    required this.entry,
    required this.editTags,
  });
  final LibraryRepository repository;
  final PackReadingEntry entry;
  final Future<void> Function(LibraryPack) editTags;
  @override
  State<PackReaderPage> createState() => PackReaderPageState();
}

class PackReaderPageState extends State<PackReaderPage>
    with WidgetsBindingObserver {
  late final session = PackReadingSession(widget.repository, widget.entry);
  final images = ReaderImages();
  bool controls = true, zoomed = false, leaving = false, _framePending = false;
  int jumpEpoch = 0, zoomReset = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(changed);
    unawaited(session.start());
  }

  String get scopeLabel {
    final query = widget.entry.query;
    final conditions = <String>[
      if (query.folder.isNotEmpty) query.folder.split('/').last,
      if (query.search.isNotEmpty) '搜索：${query.search}',
      if (query.tags.isNotEmpty) '${query.tags.length} 个标签',
      if (query.readState != PackReadState.all)
        switch (query.readState) {
          PackReadState.unread => '未读',
          PackReadState.reading => '在读',
          PackReadState.completed => '已读',
          PackReadState.all => '',
        },
    ];
    return conditions.isEmpty ? '全部图包' : conditions.join(' · ');
  }

  void changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_framePending) return;
      _framePending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _framePending = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(session.flush());
  }

  Future<bool> leave() async {
    if (leaving) return false;
    if (zoomed) {
      setState(() {
        zoomReset++;
        zoomed = false;
      });
      return false;
    }
    if (!controls) {
      setState(() => controls = true);
      return false;
    }
    leaving = true;
    try {
      if (session.invalidated ||
          session.range?.pack == null ||
          await session.flush()) {
        return true;
      }
      if (!mounted) return false;
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('阅读状态尚未确认保存'),
              content: const Text('可留在这里查询保存结果，或返回来源。下次打开会使用服务端已确认的位置和设置。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('留在阅读器'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('返回来源'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      leaving = false;
    }
  }

  Future<void> close() async {
    if (await leave() && mounted) Navigator.pop(context);
  }

  void jump(int index) {
    if (index < 0 || index >= session.total) return;
    session.show(
      index,
      end:
          index == session.total - 1 &&
          session.preferences.mode == ReaderMode.horizontal,
    );
    setState(() {
      jumpEpoch++;
      zoomReset++;
      zoomed = false;
    });
  }

  Future<void> move(String packId) async {
    if (await session.move(packId) && mounted) {
      setState(() {
        jumpEpoch++;
        zoomReset++;
        zoomed = false;
        controls = true;
      });
    }
  }

  Future<void> settings() async {
    await paperSheet<void>(
      context,
      AnimatedBuilder(
        animation: session,
        builder: (context, _) => SheetFrame(
          title: '阅读设置',
          children: [
            Text(
              session.range?.pack?.name ?? '',
              style: TextStyle(fontSize: 13, color: Paper.of(context).muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in ReaderMode.values)
                  ChoiceChip(
                    label: Text(
                      mode == ReaderMode.horizontal ? '横向翻页' : '纵向拼接',
                    ),
                    selected: session.preferences.mode == mode,
                    onSelected: session.busy || session.hasPending
                        ? null
                        : (_) async {
                            await session.setPreferences(
                              session.preferences.copy(mode: mode),
                            );
                            if (mounted) {
                              setState(() {
                                jumpEpoch++;
                                zoomReset++;
                                zoomed = false;
                              });
                            }
                          },
                  ),
              ],
            ),
            if (session.preferences.mode == ReaderMode.horizontal) ...[
              DropdownButtonFormField<ReaderDirection>(
                decoration: const InputDecoration(labelText: '翻页方向'),
                initialValue: session.preferences.direction,
                items: const [
                  DropdownMenuItem(
                    value: ReaderDirection.ltr,
                    child: Text('从左向右'),
                  ),
                  DropdownMenuItem(
                    value: ReaderDirection.rtl,
                    child: Text('从右向左'),
                  ),
                ],
                onChanged: session.busy || session.hasPending
                    ? null
                    : (value) {
                        if (value != null) {
                          unawaited(
                            session.setPreferences(
                              session.preferences.copy(direction: value),
                            ),
                          );
                        }
                      },
              ),
              DropdownButtonFormField<ReaderFit>(
                decoration: const InputDecoration(labelText: '图片适配'),
                initialValue: session.preferences.fit,
                items: const [
                  DropdownMenuItem(
                    value: ReaderFit.contain,
                    child: Text('完整显示'),
                  ),
                  DropdownMenuItem(value: ReaderFit.width, child: Text('铺满宽度')),
                ],
                onChanged: session.busy || session.hasPending
                    ? null
                    : (value) {
                        if (value != null) {
                          unawaited(
                            session.setPreferences(
                              session.preferences.copy(fit: value),
                            ),
                          );
                        }
                      },
              ),
            ] else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('图片之间留间距'),
                value: session.preferences.gap,
                onChanged: session.busy || session.hasPending
                    ? null
                    : (value) => unawaited(
                        session.setPreferences(
                          session.preferences.copy(gap: value),
                        ),
                      ),
              ),
            const SizedBox(height: 14),
            Text(
              session.preferences.mode == ReaderMode.horizontal
                  ? '左右滑动翻页，轻点图片收起工具。双击放大，再次双击复原。'
                  : '上下滑动连续阅读，切换模式仍停在当前图片。',
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
            status(context),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('继续阅读'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> overview() async {
    if (widget.repository.backupRestorePending) return;
    await paperSheet<void>(
      context,
      _ReaderOverview(
        repository: widget.repository,
        session: session,
        images: images,
        jump: (index) {
          jump(index);
          Navigator.pop(context);
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> details() async {
    final pack = session.range?.pack;
    if (pack == null) return;
    await paperSheet<void>(
      context,
      SheetFrame(
        title: '图包详情',
        children: [
          Text(
            pack.name,
            style: Paper.of(context).title.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 12),
          Text('${pack.pageCount} 张 · ${pack.readableCount} 张可读取'),
          const SizedBox(height: 16),
          const Text('原目录', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          SelectableText(
            pack.path,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 16),
          const Text('整包标签', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            pack.tagNames.values.isEmpty
                ? '尚未添加标签'
                : pack.tagNames.values.join(' · '),
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> queue() async {
    unawaited(
      session.loadQueue(offset: (session.range?.cursor ?? 0) ~/ 40 * 40),
    );
    await paperSheet<void>(
      context,
      AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          final page = session.queuePage;
          return SheetFrame(
            title: '本次图包范围',
            children: [
              Text(
                '${session.range?.candidateCount ?? 0} 个图包 · 只在这次范围内切换',
                style: const TextStyle(fontSize: 13),
              ),
              if (session.loadingQueue) const LinearProgressIndicator(),
              if (session.queueError.isNotEmpty) ...[
                Text(session.queueError),
                TextButton(
                  onPressed: () => session.loadQueue(offset: page?.offset ?? 0),
                  child: const Text('重试'),
                ),
              ],
              if (page != null) ...[
                for (final entry in page.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected: entry.pack.id == session.range?.pack?.id,
                    leading: Text(
                      '${entry.ordinal + 1}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    title: Text(
                      entry.pack.name,
                      style: const TextStyle(fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: entry.available ? null : const Text('暂不可读取'),
                    onTap:
                        entry.available && !session.busy && !session.hasPending
                        ? () async {
                            Navigator.pop(context);
                            await move(entry.pack.id);
                          }
                        : null,
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: page.offset > 0 && !session.loadingQueue
                          ? () => session.loadQueue(
                              offset: max(0, page.offset - 40),
                            )
                          : null,
                      child: const Text('上一页'),
                    ),
                    TextButton(
                      onPressed:
                          page.offset + page.entries.length < page.total &&
                              !session.loadingQueue
                          ? () => session.loadQueue(offset: page.offset + 40)
                          : null,
                      child: const Text('下一页'),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget status(BuildContext context) {
    if (session.error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              session.error,
              style: TextStyle(fontSize: 12, color: Paper.of(context).danger),
            ),
            Wrap(
              spacing: 8,
              children: [
                if (session.hasPending)
                  TextButton(
                    onPressed: session.busy ? null : session.checkPending,
                    child: const Text('查询操作结果'),
                  ),
                if (session.canResend)
                  TextButton(
                    onPressed: session.busy ? null : session.resendPending,
                    child: const Text('再次提交原请求'),
                  ),
                if (session.needsReload && session.range != null)
                  TextButton(
                    onPressed: session.busy ? null : session.reload,
                    child: const Text('重新读取位置'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (session.pageError.isNotEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(
              session.pageError,
              style: TextStyle(fontSize: 12, color: Paper.of(context).danger),
            ),
          ),
          TextButton(
            onPressed: () => session.ensure(session.index, includeWindow: true),
            child: const Text('重试'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget picture(
    ReaderPage page,
    int index,
    Size size, {
    bool thumbnail = false,
    bool Function()? visible,
  }) {
    final epoch = session.packEpoch;
    return ReaderImage(
      page: page,
      images: images,
      viewport: size,
      thumbnail: thumbnail,
      widthFit: session.preferences.fit == ReaderFit.width && !thumbnail,
      onFrame: thumbnail
          ? null
          : () {
              if (mounted &&
                  ModalRoute.of(context)?.isCurrent == true &&
                  (visible?.call() ?? true)) {
                session.visibleFrame(index, page.id, epoch);
              }
            },
      onSkip: thumbnail ? null : () => jump(min(session.total - 1, index + 1)),
      onUnauthorized: () {
        if (session.live && !thumbnail) {
          unawaited(widget.repository.mediaUnauthorized(page.image!));
        }
      },
    );
  }

  Widget end() => _PackEnd(
    next: session.range?.next == null
        ? null
        : () => move(session.range!.next!.packId),
    back: close,
    previous: () => jump(max(0, session.total - 1)),
    enabled: !session.busy && !session.hasPending,
  );

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context), pack = session.range?.pack;
    final usable = pack != null && session.live;
    final darkBars =
        !controls || Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: controls ? p.background : const Color(0xff11150f),
        statusBarIconBrightness: darkBars ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: controls
            ? p.background
            : const Color(0xff11150f),
        systemNavigationBarIconBrightness: darkBars
            ? Brightness.light
            : Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(close());
        },
        child: Scaffold(
          key: const Key('pack-reader-route'),
          backgroundColor: controls ? p.background : const Color(0xff11150f),
          body: SafeArea(
            child: Column(
              children: [
                chrome(
                  controls
                      ? ColoredBox(
                          color: p.background,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 52),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: '返回来源',
                                  onPressed: close,
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pack?.name ?? '图包阅读',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: p.title.copyWith(fontSize: 20),
                                        ),
                                        Text(
                                          '${session.total} 张',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: p.muted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '阅读设置',
                                  onPressed: usable ? settings : null,
                                  icon: const Icon(Icons.tune),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: '图包更多',
                                  onSelected: (value) async {
                                    if (value == 'details') await details();
                                    if (value == 'previous') {
                                      await move(
                                        session.range!.previous!.packId,
                                      );
                                    }
                                    if (value == 'tags' &&
                                        session.range?.pack != null &&
                                        await session.flush()) {
                                      await widget.editTags(
                                        session.range!.pack!,
                                      );
                                      if (session.live) await session.reload();
                                    }
                                    if (value == 'queue') await queue();
                                  },
                                  itemBuilder: (_) => [
                                    if (usable)
                                      const PopupMenuItem(
                                        value: 'details',
                                        child: Text('图包详情'),
                                      ),
                                    if (usable)
                                      const PopupMenuItem(
                                        value: 'tags',
                                        child: Text('整包标签'),
                                      ),
                                    if (session.range?.previous != null)
                                      const PopupMenuItem(
                                        value: 'previous',
                                        child: Text('上一包'),
                                      ),
                                    if (usable)
                                      const PopupMenuItem(
                                        value: 'queue',
                                        child: Text('本次图包范围'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (controls)
                  ColoredBox(color: p.background, child: status(context)),
                if (session.recoveryReason != null && controls)
                  ColoredBox(
                    color: p.background,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        session.recoveryReason == 'page_removed'
                            ? '上次阅读的图片已移除，已定位到附近可读图片'
                            : '上次阅读的图片不可读取，已定位到附近图片',
                        style: TextStyle(fontSize: 12, color: p.olive),
                      ),
                    ),
                  ),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xff11150f),
                    child: !usable
                        ? Center(
                            child: session.busy
                                ? const CircularProgressIndicator()
                                : Text(
                                    session.invalidated
                                        ? session.error
                                        : session.range == null
                                        ? '正在准备阅读范围'
                                        : '本次范围暂无可读取的图包',
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                          )
                        : Stack(
                            children: [
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final size = constraints.biggest;
                                    return session.preferences.mode ==
                                            ReaderMode.horizontal
                                        ? _HorizontalReader(
                                            key: ValueKey(
                                              'horizontal-${session.packEpoch}',
                                            ),
                                            session: session,
                                            jumpEpoch: jumpEpoch,
                                            resetZoom: zoomReset,
                                            size: size,
                                            picture: picture,
                                            end: end,
                                            tap: () => setState(
                                              () => controls = !controls,
                                            ),
                                            onZoom: (value) {
                                              if (mounted && zoomed != value) {
                                                setState(() => zoomed = value);
                                              }
                                            },
                                          )
                                        : _VerticalReader(
                                            key: ValueKey(
                                              'vertical-${session.packEpoch}',
                                            ),
                                            session: session,
                                            jumpEpoch: jumpEpoch,
                                            size: size,
                                            picture: picture,
                                            end: end,
                                            tap: () => setState(
                                              () => controls = !controls,
                                            ),
                                          );
                                  },
                                ),
                              ),
                              if (!controls)
                                Positioned(
                                  right: 16,
                                  bottom: 12,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => controls = true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 7,
                                      ),
                                      color: Colors.black54,
                                      child: Text(
                                        '${session.index + 1} / ${session.total}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                chrome(
                  controls && usable
                      ? ColoredBox(
                          color: p.background,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: '上一张',
                                      onPressed: session.index > 0
                                          ? () => jump(session.index - 1)
                                          : null,
                                      icon: const Icon(Icons.chevron_left),
                                    ),
                                    Expanded(
                                      child: Slider(
                                        value: session.index.toDouble(),
                                        min: 0,
                                        max: max(
                                          1,
                                          session.total - 1,
                                        ).toDouble(),
                                        onChanged: session.total > 1
                                            ? (value) => jump(value.round())
                                            : null,
                                      ),
                                    ),
                                    Text(
                                      '${session.index + 1} / ${session.total}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    IconButton(
                                      tooltip: '下一张',
                                      onPressed:
                                          session.index < session.total - 1
                                          ? () => jump(session.index + 1)
                                          : null,
                                      icon: const Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    tool(
                                      '总览',
                                      Icons.grid_view_outlined,
                                      overview,
                                    ),
                                    tool(
                                      session.preferences.mode ==
                                              ReaderMode.horizontal
                                          ? '横向翻页'
                                          : '纵向拼接',
                                      session.preferences.mode ==
                                              ReaderMode.horizontal
                                          ? Icons.chrome_reader_mode_outlined
                                          : Icons.view_day_outlined,
                                      settings,
                                    ),
                                    tool('整包标签', Icons.sell_outlined, () async {
                                      if (await session.flush()) {
                                        await widget.editTags(
                                          session.range!.pack!,
                                        );
                                        if (session.live) {
                                          await session.reload();
                                        }
                                      }
                                    }),
                                    tool(
                                      '沉浸',
                                      Icons.fullscreen,
                                      () => setState(() => controls = false),
                                    ),
                                  ],
                                ),
                                Divider(height: 8, color: p.line),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: queue,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${switch (widget.entry.source) {
                                                  BrowseSource.library => '媒体库',
                                                  BrowseSource.tags => '标签',
                                                  BrowseSource.recent => '最近',
                                                }} · $scopeLabel',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${(session.range!.cursor ?? 0) + 1} / ${session.range!.candidateCount}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (session.range?.next != null)
                                      TextButton(
                                        onPressed:
                                            session.busy || session.hasPending
                                            ? null
                                            : () => move(
                                                session.range!.next!.packId,
                                              ),
                                        child: const Text(
                                          '下一包',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      )
                                    else
                                      TextButton(
                                        onPressed: close,
                                        child: const Text(
                                          '返回来源',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget chrome(Widget child) {
    final duration = MediaLayout.motion(context, 140);
    return session.opened && duration > Duration.zero
        ? AnimatedSize(duration: duration, child: child)
        : child;
  }

  Widget tool(String label, IconData icon, VoidCallback action) => Expanded(
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21),
            const SizedBox(height: 3),
            Text(
              MediaLayout.largeText(context) && label.length == 4
                  ? '${label.substring(0, 2)}\n${label.substring(2)}'
                  : label,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(changed);
    session.dispose();
    images.dispose();
    super.dispose();
  }
}

class _PackEnd extends StatelessWidget {
  const _PackEnd({
    required this.next,
    required this.back,
    required this.previous,
    required this.enabled,
  });
  final VoidCallback? next;
  final VoidCallback back, previous;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '已到本包末尾',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (next != null)
                FilledButton(
                  onPressed: enabled ? next : null,
                  child: const Text('阅读下一包'),
                ),
              OutlinedButton(onPressed: back, child: const Text('返回来源')),
            ],
          ),
          TextButton(onPressed: previous, child: const Text('返回最后一张')),
        ],
      ),
    ),
  );
}

typedef _Picture = Widget Function(
  ReaderPage page,
  int index,
  Size size, {
  bool thumbnail,
  bool Function()? visible,
});

class _HorizontalReader extends StatefulWidget {
  const _HorizontalReader({
    super.key,
    required this.session,
    required this.jumpEpoch,
    required this.resetZoom,
    required this.size,
    required this.picture,
    required this.end,
    required this.tap,
    required this.onZoom,
  });
  final PackReadingSession session;
  final int jumpEpoch, resetZoom;
  final Size size;
  final _Picture picture;
  final Widget Function() end;
  final VoidCallback tap;
  final ValueChanged<bool> onZoom;
  @override
  State<_HorizontalReader> createState() => _HorizontalReaderState();
}

class _HorizontalReaderState extends State<_HorizontalReader> {
  late final pages = PageController(initialPage: widget.session.index);
  bool zoom = false;
  @override
  void didUpdateWidget(_HorizontalReader old) {
    super.didUpdateWidget(old);
    if (old.jumpEpoch != widget.jumpEpoch) {
      final epoch = widget.jumpEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == widget.jumpEpoch && pages.hasClients) {
          pages.jumpToPage(widget.session.index);
        }
      });
    }
    if (old.resetZoom != widget.resetZoom) zoom = false;
  }

  bool showing(int index) =>
      pages.hasClients &&
      pages.position.hasPixels &&
      (pages.page ?? pages.initialPage.toDouble()).round() == index;
  @override
  Widget build(BuildContext context) => PageView.builder(
    key: const Key('reader-horizontal'),
    controller: pages,
    reverse: widget.session.preferences.direction == ReaderDirection.rtl,
    physics: zoom ? const NeverScrollableScrollPhysics() : null,
    itemCount: widget.session.total + 1,
    onPageChanged: (index) {
      zoom = false;
      widget.onZoom(false);
      widget.session.show(
        min(index, widget.session.total - 1),
        end: index >= widget.session.total - 1,
      );
    },
    itemBuilder: (context, index) {
      if (index == widget.session.total) return widget.end();
      final page = widget.session.pages[index];
      if (page == null) return const Center(child: CircularProgressIndicator());
      return _ZoomPage(
        key: ValueKey('${page.id}:${widget.size}'),
        reset: widget.resetZoom,
        active: index == widget.session.index,
        tap: widget.tap,
        onZoom: (value) {
          if (index == widget.session.index) {
            setState(() => zoom = value);
            widget.onZoom(value);
          }
        },
        child: widget.session.preferences.fit == ReaderFit.width
            ? _WidthFitPage(
                key: ValueKey('${page.id}-width'),
                session: widget.session,
                index: index,
                page: page,
                size: widget.size,
                picture: widget.picture,
                visible: () => showing(index),
              )
            : widget.picture(
                page,
                index,
                widget.size,
                visible: () => showing(index),
              ),
      );
    },
  );
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }
}

class _ZoomPage extends StatefulWidget {
  const _ZoomPage({
    super.key,
    required this.child,
    required this.tap,
    required this.onZoom,
    required this.active,
    required this.reset,
  });
  final Widget child;
  final VoidCallback tap;
  final ValueChanged<bool> onZoom;
  final bool active;
  final int reset;
  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final transform = TransformationController();
  @override
  void didUpdateWidget(_ZoomPage old) {
    super.didUpdateWidget(old);
    if (old.reset != widget.reset || !widget.active) {
      transform.value = Matrix4.identity();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => GestureDetector(
      onTap: widget.tap,
      onDoubleTap: () {
        final zoom = transform.value.getMaxScaleOnAxis() > 1.01;
        if (zoom) {
          transform.value = Matrix4.identity();
        } else {
          final value = Matrix4.diagonal3Values(2, 2, 1);
          value.setEntry(0, 3, -size.maxWidth / 2);
          value.setEntry(1, 3, -size.maxHeight / 2);
          transform.value = value;
        }
        widget.onZoom(!zoom);
      },
      child: InteractiveViewer(
        transformationController: transform,
        minScale: 1,
        maxScale: 4,
        panEnabled: transform.value.getMaxScaleOnAxis() > 1.01,
        onInteractionUpdate: (_) =>
            widget.onZoom(transform.value.getMaxScaleOnAxis() > 1.01),
        child: SizedBox.expand(child: widget.child),
      ),
    ),
  );
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }
}

class _WidthFitPage extends StatefulWidget {
  const _WidthFitPage({
    super.key,
    required this.session,
    required this.index,
    required this.page,
    required this.size,
    required this.picture,
    required this.visible,
  });
  final PackReadingSession session;
  final int index;
  final ReaderPage page;
  final Size size;
  final _Picture picture;
  final bool Function() visible;
  @override
  State<_WidthFitPage> createState() => _WidthFitPageState();
}

class _WidthFitPageState extends State<_WidthFitPage> {
  final scroll = ScrollController();
  bool positioning = true;
  late bool active = widget.session.index == widget.index;
  double get height => max(
    widget.size.height,
    widget.size.width * max(1, widget.page.height) / max(1, widget.page.width),
  );
  @override
  void initState() {
    super.initState();
    scroll.addListener(report);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      scroll.jumpTo(
        ((widget.session.index == widget.index
                    ? widget.session.offsetRatio
                    : 0) *
                height)
            .clamp(0, scroll.position.maxScrollExtent),
      );
      positioning = false;
      report();
    });
  }

  @override
  void didUpdateWidget(_WidthFitPage old) {
    super.didUpdateWidget(old);
    final now = widget.session.index == widget.index;
    if (now && !active) {
      positioning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        scroll.jumpTo(
          (widget.session.offsetRatio * height).clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
        positioning = false;
        report();
      });
    }
    active = now;
  }

  void report() {
    if (positioning ||
        !scroll.hasClients ||
        widget.session.index != widget.index) {
      return;
    }
    widget.session.show(
      widget.index,
      ratio: (scroll.offset / height).clamp(0, 1),
      end:
          widget.index == widget.session.total - 1 &&
          scroll.position.extentAfter < 2,
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: scroll,
    child: SizedBox(
      width: widget.size.width,
      height: height,
      child: widget.picture(
        widget.page,
        widget.index,
        Size(widget.size.width, height),
        visible: () => !positioning && widget.visible(),
      ),
    ),
  );
  @override
  void dispose() {
    scroll.removeListener(report);
    scroll.dispose();
    super.dispose();
  }
}

class _VerticalReader extends StatefulWidget {
  const _VerticalReader({
    super.key,
    required this.session,
    required this.jumpEpoch,
    required this.size,
    required this.picture,
    required this.end,
    required this.tap,
  });
  final PackReadingSession session;
  final int jumpEpoch;
  final Size size;
  final _Picture picture;
  final Widget Function() end;
  final VoidCallback tap;
  @override
  State<_VerticalReader> createState() => _VerticalReaderState();
}

class _VerticalReaderState extends State<_VerticalReader> {
  final scroll = ScrollController();
  String stamp = '';
  bool positioning = true;
  List<int> indexes = [];
  List<double> tops = [];
  double footer = 180;
  @override
  void initState() {
    super.initState();
    scroll.addListener(report);
  }

  double height(int index) {
    final page = widget.session.pages[index]!;
    return max(
          120,
          widget.size.width * max(1, page.height) / max(1, page.width),
        ) +
        (widget.session.preferences.gap ? 12 : 0);
  }

  void report() {
    if (positioning || !scroll.hasClients || indexes.isEmpty) return;
    final offset = scroll.offset;
    var at = 0;
    while (at + 1 < indexes.length && tops[at + 1] <= offset) {
      at++;
    }
    final index = indexes[at],
        ratio = ((offset - tops[at]) / height(index)).clamp(0.0, 1.0);
    widget.session.show(
      index,
      ratio: ratio,
      end: index == widget.session.total - 1 && scroll.position.extentAfter < 2,
    );
    if (!widget.session.loadingPages) {
      if (index >= indexes.last - 2 &&
          indexes.last < widget.session.total - 1) {
        unawaited(widget.session.ensure(indexes.last + 1));
      } else if (index <= indexes.first + 2 && indexes.first > 0) {
        unawaited(widget.session.ensure(indexes.first - 1));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    if (!s.manifestReady || s.currentPage == null) {
      positioning = true;
      stamp = '';
      return const Center(child: CircularProgressIndicator());
    }
    indexes = s.pages.keys.toList();
    tops = [];
    var total = 0.0;
    for (final i in indexes) {
      tops.add(total);
      total += height(i);
    }
    footer = MediaLayout.largeText(context) ? 260 : 180;
    final next =
        '${s.packEpoch}:${s.windowStart}:${s.windowEnd}:${widget.size}:${s.preferences.gap}:${widget.jumpEpoch}';
    if (next != stamp) {
      stamp = next;
      positioning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !scroll.hasClients ||
            indexes.isEmpty ||
            stamp != next) {
          return;
        }
        final at = indexes.indexOf(s.index);
        if (at >= 0) {
          scroll.jumpTo(
            (tops[at] + s.offsetRatio * height(s.index)).clamp(
              0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
        positioning = false;
        report();
      });
    }
    if (indexes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      key: const Key('reader-vertical'),
      controller: scroll,
      scrollCacheExtent: const ScrollCacheExtent.pixels(180),
      itemCount: indexes.length + 1,
      itemExtentBuilder: (at, dimensions) =>
          at == indexes.length ? footer : height(indexes[at]),
      itemBuilder: (context, at) {
        if (at == indexes.length) {
          return indexes.last == s.total - 1
              ? widget.end()
              : const Center(child: CircularProgressIndicator());
        }
        final index = indexes[at], page = s.pages[index]!;
        return Padding(
          padding: EdgeInsets.only(bottom: s.preferences.gap ? 12 : 0),
          child: GestureDetector(
            onTap: widget.tap,
            child: widget.picture(
              page,
              index,
              Size(
                widget.size.width,
                height(index) - (s.preferences.gap ? 12 : 0),
              ),
              visible: () => !positioning,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    scroll.removeListener(report);
    scroll.dispose();
    super.dispose();
  }
}

class _ReaderOverview extends StatefulWidget {
  const _ReaderOverview({
    required this.repository,
    required this.session,
    required this.images,
    required this.jump,
  });
  final LibraryRepository repository;
  final PackReadingSession session;
  final ReaderImages images;
  final ValueChanged<int> jump;
  @override
  State<_ReaderOverview> createState() => _ReaderOverviewState();
}

class _ReaderOverviewState extends State<_ReaderOverview> {
  late final reader = widget.repository.createPackReader();
  PackManifest? page;
  String error = '';
  bool busy = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(load(widget.session.index ~/ 24 * 24));
  }

  Future<void> load(int offset) async {
    final cursor = widget.session.cursor;
    if (cursor == null) return;
    final request = ++generation;
    setState(() => busy = true);
    try {
      final next = await reader.pages(
        cursor.packId,
        version: cursor.version,
        offset: offset,
        limit: 24,
      );
      if (mounted && request == generation && widget.session.live) {
        setState(() {
          page = next;
          error = '';
        });
      }
    } catch (failure) {
      if (mounted && request == generation) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    key: const Key('reader-overview-sheet'),
    title: '页码总览',
    children: [
      Text(
        '${widget.session.total} 张 · 文件名自然顺序',
        style: const TextStyle(fontSize: 13),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error.isNotEmpty) ...[
        Text(error),
        TextButton(
          onPressed: () => load(page?.offset ?? 0),
          child: const Text('重试'),
        ),
      ],
      if (page != null) ...[
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: .72,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: page!.pages.length,
          itemBuilder: (context, i) {
            final index = page!.offset + i, picture = page!.pages[i];
            final selected = index == widget.session.index;
            final palette = Paper.of(context);
            return Semantics(
              selected: selected,
              label: '第 ${index + 1} 页',
              child: InkWell(
                key: Key('reader-overview-page-$index'),
                onTap: () {
                  widget.session.show(index);
                  widget.jump(index);
                },
                child: Column(
                  children: [
                    Expanded(
                      child: ReaderImage(
                        page: picture,
                        images: widget.images,
                        viewport: const Size(110, 150),
                        thumbnail: true,
                        onUnauthorized: () {
                          if (widget.session.live && reader.isCurrent) {
                            unawaited(
                              widget.session.repository.mediaUnauthorized(
                                picture.thumbnail ?? picture.image!,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: selected ? palette.soft : Colors.transparent,
                        border: Border.all(
                          color: selected ? palette.olive : Colors.transparent,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: page!.offset > 0 && !busy
                  ? () => load(max(0, page!.offset - 24))
                  : null,
              child: const Text('上一页'),
            ),
            TextButton(
              onPressed:
                  page!.offset + page!.pages.length < page!.total && !busy
                  ? () => load(page!.offset + 24)
                  : null,
              child: const Text('下一页'),
            ),
          ],
        ),
      ],
    ],
  );
  @override
  void dispose() {
    generation++;
    reader.dispose();
    super.dispose();
  }
}
