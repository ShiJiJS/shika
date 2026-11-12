import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/media_layout.dart';
import '../../ui/paper.dart';
import '../../ui/paper_icons.dart';
import 'pack_reading_session.dart';
import 'pack_file_action.dart';
import 'quick_pack_cleanup.dart';
import 'reader_images.dart';

class PackReaderPage extends StatefulWidget {
  const PackReaderPage({
    super.key,
    required this.repository,
    required this.entry,
    required this.editTags,
    this.quick = false,
    this.resumeSessionId,
    this.returnContext,
  });
  final LibraryRepository repository;
  final PackReadingEntry entry;
  final bool quick;
  final String? resumeSessionId;
  final PackCleanupContext? returnContext;
  final Future<void> Function(LibraryPack) editTags;
  @override
  State<PackReaderPage> createState() => PackReaderPageState();
}

class PackReaderPageState extends State<PackReaderPage>
    with WidgetsBindingObserver {
  late final session = PackReadingSession(
    widget.repository,
    widget.entry,
    returnContext: widget.returnContext,
  );
  late bool quick = widget.quick;
  final images = ReaderImages();
  bool controls = true, zoomed = false, leaving = false, _framePending = false;
  bool showingEnd = false;
  int jumpEpoch = 0, zoomReset = 0;
  final _chromePointers = <int>{};
  int? _swipePointer;
  Offset? _swipeStart;
  final Set<String> _preparingRemoval = {};
  QuickPackCleanup? _quickCleanup;
  QuickPackCleanup get quickCleanup => _quickCleanup ??= QuickPackCleanup(
    session.cleanupFiles,
    changedFiles: widget.repository.packFilesChanged,
  );
  Timer? _noticeTimer;
  String _notice = '';
  QuickPackRemoval? _noticeUndo, _pendingRemovalNotice;
  int _pendingRemovalEpoch = 0, _observedEpoch = 0;
  bool _stepping = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The library stays portrait; the reader already has a landscape layout.
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    session.addListener(changed);
    if (session.cleanupSupported) quickCleanup.addListener(quickCleanupChanged);
    unawaited(
      session.start(resumeSessionId: widget.resumeSessionId).then((_) {
        if (mounted && quick) session.setQuickPreferences(true);
      }),
    );
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

  String get sourceCaption {
    final query = widget.entry.query;
    if (widget.entry.source == BrowseSource.recent &&
        query.count == 0 &&
        query.search.isEmpty) {
      return '最近阅读';
    }
    final source = switch (widget.entry.source) {
      BrowseSource.library => '媒体库',
      BrowseSource.tags => '标签',
      BrowseSource.recent => '最近',
    };
    return '$source · $scopeLabel';
  }

  void changed() {
    if (!mounted) return;
    if (_observedEpoch != session.packEpoch) {
      _observedEpoch = session.packEpoch;
      clearNotice();
    }
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

  void clearNotice() {
    _noticeTimer?.cancel();
    _notice = '';
    _noticeUndo = null;
    _pendingRemovalNotice = null;
  }

  void toggleControls() => setState(() => controls = !controls);

  // Observe a completed single-finger upward gesture without competing with
  // the image's scroll/scale recognizer or reflowing it while a finger is down.
  void chromePointerDown(PointerDownEvent event) {
    _chromePointers.add(event.pointer);
    if (_chromePointers.length == 1 && quick && controls && !zoomed) {
      _swipePointer = event.pointer;
      _swipeStart = event.position;
    } else {
      _swipePointer = null;
      _swipeStart = null;
    }
  }

  void chromePointerUp(PointerUpEvent event) {
    final start = _swipePointer == event.pointer ? _swipeStart : null;
    _chromePointers.remove(event.pointer);
    _swipePointer = null;
    _swipeStart = null;
    if (start == null || !quick || !controls || zoomed) return;
    final delta = event.position - start;
    if (delta.dy < -32 && -delta.dy > delta.dx.abs() * 1.2) {
      setState(() => controls = false);
    }
  }

  void chromePointerCancel(PointerCancelEvent event) {
    _chromePointers.remove(event.pointer);
    _swipePointer = null;
    _swipeStart = null;
  }

  void showNotice(String message, {QuickPackRemoval? undo}) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    _notice = message;
    _noticeUndo = undo;
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(clearNotice);
    });
    changed();
  }

  void offerRemovalNotice(QuickPackRemoval item) {
    if (item.working) return;
    if (item.canUndo) {
      _pendingRemovalNotice = null;
      showNotice('已移入回收站', undo: item);
    } else if (item.state != QuickRemovalState.queued &&
        item.state != QuickRemovalState.pending) {
      _pendingRemovalNotice = null;
    }
  }

  void quickCleanupChanged() {
    if (!mounted) return;
    session.excludePacks(quickCleanup.hiddenIds);
    final item = _pendingRemovalNotice;
    if (item != null && _pendingRemovalEpoch == session.packEpoch) {
      offerRemovalNotice(item);
    }
    changed();
  }

  void setQuick(bool enabled) {
    session.setQuickPreferences(enabled);
    setState(() {
      quick = enabled;
      controls = true;
      jumpEpoch++;
      zoomReset++;
      zoomed = false;
    });
  }

  Future<void> moveAdjacent(int direction) async {
    if (session.inputBlocked || _stepping) return;
    final epoch = session.packEpoch;
    setState(() => _stepping = true);
    try {
      final target = await session.findNeighbor(direction);
      if (!mounted || epoch != session.packEpoch) return;
      if (target != null) {
        await move(target.packId);
      } else if (direction > 0 && session.error.isEmpty) {
        await close();
      }
    } finally {
      if (mounted) setState(() => _stepping = false);
    }
  }

  Future<void> removeQuick() async {
    final pack = session.range?.pack;
    if (pack == null ||
        quickCleanup.hiddenIds.contains(pack.id) ||
        !_preparingRemoval.add(pack.id)) {
      return;
    }
    try {
      if (!await session.flush() ||
          !mounted ||
          session.range?.pack?.id != pack.id) {
        return;
      }
      final item = await quickCleanup.enqueue(pack);
      if (!mounted || session.range?.pack?.id != pack.id) return;
      final next = await session.findNeighbor(1);
      if (!mounted || session.range?.pack?.id != pack.id) return;
      if (next != null) {
        await move(next.packId);
        if (mounted && session.range?.pack?.id == next.packId) {
          _pendingRemovalNotice = item;
          _pendingRemovalEpoch = session.packEpoch;
          offerRemovalNotice(item);
        }
      } else if (session.error.isEmpty) {
        setState(() => showingEnd = true);
        _pendingRemovalNotice = item;
        _pendingRemovalEpoch = session.packEpoch;
        offerRemovalNotice(item);
      }
    } catch (failure) {
      showNotice(packFileFailureMessage(failure));
    } finally {
      _preparingRemoval.remove(pack.id);
    }
  }

  Future<void> undoQuick(QuickPackRemoval item) async {
    final epoch = session.packEpoch;
    if (await quickCleanup.undo(item) &&
        mounted &&
        session.packEpoch == epoch) {
      await move(item.pack.id);
      showNotice('已撤销移除');
    }
  }

  Future<void> removalRecords() => paperSheet<void>(
    context,
    AnimatedBuilder(
      animation: quickCleanup,
      builder: (context, _) => SheetFrame(
        title: '移除记录',
        children: [
          if (quickCleanup.items.isEmpty) const Text('暂无移除记录'),
          for (final item in quickCleanup.items.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.pack.displayTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.restored
                        ? '已撤销移除'
                        : item.error.isNotEmpty
                        ? item.error
                        : switch (item.state) {
                            QuickRemovalState.queued => '正在提交',
                            QuickRemovalState.pending => '正在处理',
                            QuickRemovalState.succeeded => '已移入回收站，源文件保留',
                            QuickRemovalState.failed => '移除未完成',
                            QuickRemovalState.unknown => '结果待核对',
                          },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (item.canUndo)
                        TextButton(
                          onPressed: item.working
                              ? null
                              : () => undoQuick(item),
                          child: const Text('撤销移除'),
                        ),
                      if (!item.restored &&
                          item.state != QuickRemovalState.succeeded)
                        TextButton(
                          onPressed: item.working
                              ? null
                              : () => quickCleanup.query(item),
                          child: const Text('查询原结果'),
                        ),
                      if (item.undoCommand != null && !item.restored)
                        TextButton(
                          onPressed: item.working
                              ? null
                              : () => quickCleanup.undo(item),
                          child: const Text('查询撤销结果'),
                        ),
                    ],
                  ),
                ],
              ),
              trailing: item.working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
        ],
      ),
    ),
  );

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
      if (session.cleanupFinished ||
          session.cleanupFrozen ||
          session.invalidated ||
          session.range?.pack == null ||
          (_quickCleanup?.hiddenIds.contains(session.cursor?.packId) ??
              false) ||
          await session.flush()) {
        return true;
      }
      if (!mounted) return false;
      return await paperDialog<bool>(
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
    if (await leave() && mounted) Navigator.pop(context, deleteOutcome);
  }

  PackFileOutcome? get deleteOutcome {
    final task = session.lastDeleteTask, command = session.lastDeleteCommand;
    return task == null || command == null
        ? null
        : PackFileOutcome(session.cleanupFiles, command, task);
  }

  Future<void> finishCleanup(PackFileTask? task) async {
    if (!mounted || !session.live || task?.settled != true) return;
    if (session.cleanupFinished) {
      Navigator.pop(context, deleteOutcome);
      return;
    }
    if (task!.result!.succeeded == 0 || session.cleanupFrozen) return;
    setState(() {
      showingEnd = false;
      jumpEpoch++;
      zoomReset++;
      zoomed = false;
      controls = true;
    });
    final remaining = task.remainingUndo();
    if (task.kind != 'pack_trash' || remaining <= Duration.zero) return;
    ScaffoldMessenger.of(context).showSnackBar(
      PaperSnackBar(
        context: context,
        content: const Text('已移入回收站'),
        duration: remaining,
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            await finishCleanup(await session.undoDelete(task));
          },
        ),
      ),
    );
  }

  Future<void> removeCurrent() async {
    if (session.inputBlocked || _stepping || !session.cleanupSupported) return;
    if (quick) {
      await removeQuick();
      return;
    }
    if (!quick) {
      final confirmed = await paperSheet<bool>(
        context,
        SheetFrame(
          title: '移入回收站？',
          children: [
            Text(session.range!.pack!.displayTitle),
            const SizedBox(height: 12),
            const Text('保留源文件、图包标签和阅读进度。移除后返回来源，可在回收站恢复。'),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Paper.of(context).danger,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('移入回收站'),
                ),
              ],
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          !session.live ||
          session.inputBlocked) {
        return;
      }
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await finishCleanup(await session.removeCurrent(quick: quick));
  }

  void jump(int index) {
    if (session.inputBlocked || index < 0 || index > session.total) return;
    if (index == session.total) {
      if (session.total == 0) return;
      // The clicked vertical image can be below the viewport's current page.
      session.show(session.total - 1);
      // Reaching the end is navigation, not proof of a decoded last image.
      setState(() {
        showingEnd = true;
        controls = true;
        zoomReset++;
        zoomed = false;
      });
      return;
    }
    session.show(
      index,
      end:
          index == session.total - 1 &&
          session.preferences.mode == ReaderMode.horizontal,
    );
    setState(() {
      showingEnd = false;
      jumpEpoch++;
      zoomReset++;
      zoomed = false;
    });
  }

  Future<void> move(String packId) async {
    if (await session.move(packId) && mounted) {
      setState(() {
        showingEnd = false;
        jumpEpoch++;
        zoomReset++;
        zoomed = false;
        if (!quick) controls = true;
      });
    }
  }

  Future<void> settings() async {
    await paperSheet<void>(
      context,
      AnimatedBuilder(
        animation: session,
        builder: (context, _) => SheetFrame(
          title: quick ? '快速整理阅读方式' : '阅读设置',
          footer: FilledButton(
            key: const Key('reader-settings-done'),
            onPressed: () => Navigator.pop(context),
            child: const Text('继续阅读'),
          ),
          children: [
            Text(
              quick
                  ? '此次整理使用相同设置，退出后恢复各图包的阅读设置。'
                  : session.range?.pack?.displayTitle ?? '',
              style: TextStyle(fontSize: 13, color: Paper.of(context).muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in ReaderMode.values)
                  PaperChoiceChip(
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
                                showingEnd = false;
                                jumpEpoch++;
                                zoomReset++;
                                zoomed = false;
                              });
                            }
                          },
                  ),
              ],
            ),
            SizedBox(height: MediaLayout.largeText(context) ? 24 : 16),
            if (session.preferences.mode == ReaderMode.horizontal) ...[
              PaperDropdownButtonFormField<ReaderDirection>(
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
              SizedBox(height: MediaLayout.largeText(context) ? 24 : 16),
              PaperDropdownButtonFormField<ReaderFit>(
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
            pack.displayTitle,
            style: Paper.of(context).title.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 12),
          if (pack.readerSubtitle.isNotEmpty) ...[
            Text(pack.readerSubtitle, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
          ],
          Text('${pack.pageCount} 张 · ${pack.readableCount} 张可读取'),
          const SizedBox(height: 16),
          const Text('原目录', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          SelectableText(
            pack.path,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 16),
          const Text('图包标签', style: TextStyle(fontSize: 13)),
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
            footer: page == null
                ? null
                : Row(
                    key: const Key('reader-range-pagination'),
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
            children: [
              Text(
                sourceCaption,
                key: const Key('reader-range-caption'),
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 8),
              Text(
                '${session.displayCount} 个图包 · 只在这次范围内切换',
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
                      entry.pack.displayTitle,
                      style: const TextStyle(fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle:
                        _quickCleanup?.hiddenIds.contains(entry.pack.id) == true
                        ? const Text('已从当前队列移除')
                        : entry.available
                        ? null
                        : const Text('暂不可读取'),
                    onTap:
                        entry.available &&
                            !(_quickCleanup?.hiddenIds.contains(
                                  entry.pack.id,
                                ) ??
                                false) &&
                            !session.busy &&
                            !session.hasPending
                        ? () async {
                            Navigator.pop(context);
                            await move(entry.pack.id);
                          }
                        : null,
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
    if (_stepping) return const LinearProgressIndicator(minHeight: 2);
    if (session.cleanupBusy ||
        session.cleanupError.isNotEmpty ||
        session.hasCleanup) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (session.cleanupBusy) const LinearProgressIndicator(),
            Text(
              session.cleanupBusy ? '正在确认操作…' : session.cleanupError,
              key: const Key('reader-cleanup-status'),
              style: TextStyle(fontSize: 12, color: Paper.of(context).danger),
            ),
            Wrap(
              spacing: 8,
              children: [
                if (session.hasCleanup)
                  TextButton(
                    onPressed: session.cleanupBusy
                        ? null
                        : () async =>
                              finishCleanup(await session.checkCleanup()),
                    child: const Text('查询原结果'),
                  ),
                if (session.cleanupCanResend)
                  TextButton(
                    onPressed: session.cleanupBusy
                        ? null
                        : () async => finishCleanup(
                            await session.checkCleanup(resend: true),
                          ),
                    child: const Text('重新提交原请求'),
                  ),
                if (session.needsReload && !session.hasCleanup)
                  TextButton(
                    onPressed: session.cleanupBusy ? null : session.reload,
                    child: const Text('重新读取位置'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
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
                    onPressed:
                        session.inputBlocked && session.pendingKind == null
                        ? null
                        : session.checkPending,
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
    Widget Function(Widget)? frameDecorator,
  }) {
    final epoch = session.packEpoch;
    return ReaderImage(
      page: page,
      images: images,
      viewport: size,
      thumbnail: thumbnail,
      widthFit: session.preferences.fit == ReaderFit.width && !thumbnail,
      frameDecorator: frameDecorator,
      onFrame: thumbnail
          ? null
          : () {
              if (mounted &&
                  ModalRoute.of(context)?.isCurrent == true &&
                  (visible?.call() ?? true)) {
                session.visibleFrame(index, page.id, epoch);
              }
            },
      onSkip: thumbnail ? null : () => jump(index + 1),
      onUnauthorized: () {
        if (session.live && !thumbnail) {
          unawaited(widget.repository.mediaUnauthorized(page.image!));
        }
      },
    );
  }

  Widget end() => _PackEnd(
    next: session.range?.next == null ? null : () => moveAdjacent(1),
    back: close,
    previous: () => jump(max(0, session.total - 1)),
    enabled: !session.inputBlocked,
  );

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context), pack = session.range?.pack;
    final usable = pack != null && session.live;
    final darkBars =
        !controls || Theme.of(context).brightness == Brightness.dark;
    final window = MediaQuery.sizeOf(context);
    final compact =
        !quick && window.width > window.height && window.height <= 500;
    final chromeButtonStyle = IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final header = chrome(
      controls
          ? ColoredBox(
              color: compact
                  ? p.background.withValues(alpha: .93)
                  : p.background,
              child: ConstrainedBox(
                key: const Key('reader-header'),
                constraints: BoxConstraints(minHeight: compact ? 48 : 52),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 12, compact ? 1 : 5),
                  child: Row(
                    children: [
                      IconButton(
                        style: chromeButtonStyle,
                        tooltip: '返回来源',
                        onPressed: close,
                        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.zero,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pack?.displayTitle ?? '图包阅读',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: p.title.copyWith(fontSize: 20),
                              ),
                              Text(
                                '${quick ? '快速整理 · ' : ''}${pack?.readerSubtitle.isNotEmpty == true ? pack!.readerSubtitle : '${session.total} 张'}',
                                style: TextStyle(fontSize: 12, color: p.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!quick)
                        IconButton(
                          style: chromeButtonStyle,
                          tooltip: '阅读设置',
                          onPressed: usable && !session.inputBlocked
                              ? settings
                              : null,
                          icon: const PaperIcon(PaperGlyph.settings, size: 20),
                        ),
                      if (quick)
                        TextButton(
                          onPressed: session.inputBlocked
                              ? null
                              : () => setQuick(false),
                          child: const Text('完成'),
                        ),
                      PaperMenuButton<String>(
                        icon: const PaperIcon(PaperGlyph.more, size: 20),
                        enabled: usable && !session.inputBlocked && !_stepping,
                        tooltip: '图包更多',
                        onSelected: (value) async {
                          if (value == 'cleanup') {
                            await removeCurrent();
                          }
                          if (value == 'quick') {
                            setQuick(!quick);
                          }
                          if (value == 'details') await details();
                          if (value == 'previous') {
                            await moveAdjacent(-1);
                          }
                          if (value == 'tags' &&
                              session.range?.pack != null &&
                              await session.flush()) {
                            await widget.editTags(session.range!.pack!);
                            if (session.live) await session.reload();
                          }
                          if (value == 'queue') await queue();
                          if (value == 'overview') await overview();
                          if (value == 'settings') await settings();
                          if (value == 'records') await removalRecords();
                          if (value == 'undo' &&
                              quickCleanup.undoable != null) {
                            await undoQuick(quickCleanup.undoable!);
                          }
                          if (value == 'immerse') {
                            setState(() => controls = false);
                          }
                        },
                        itemBuilder: (_) => [
                          if (quick)
                            const PopupMenuItem(
                              value: 'settings',
                              child: Text('阅读方式'),
                            ),
                          if (!widget
                                  .repository
                                  .capabilities
                                  .packDirectoryDelete &&
                              _quickCleanup?.items.isNotEmpty == true)
                            PopupMenuItem(
                              value: 'records',
                              child: Text(
                                '移除记录${quickCleanup.unresolved > 0 ? '（${quickCleanup.unresolved}）' : ''}',
                              ),
                            ),
                          if (_quickCleanup?.undoable != null)
                            const PopupMenuItem(
                              value: 'undo',
                              child: Text('撤销移除'),
                            ),
                          if (compact && usable) ...[
                            const PopupMenuItem(
                              value: 'overview',
                              child: Text('页码总览'),
                            ),
                            if (!quick)
                              const PopupMenuItem(
                                value: 'immerse',
                                child: Text('沉浸阅读'),
                              ),
                          ],
                          if (session.cleanupSupported)
                            PopupMenuItem(
                              value: 'quick',
                              child: Text(quick ? '退出快速整理' : '快速整理当前范围'),
                            ),
                          if (session.cleanupSupported && !quick)
                            const PopupMenuItem(
                              value: 'cleanup',
                              child: Text('移入回收站'),
                            ),
                          if (usable)
                            const PopupMenuItem(
                              value: 'details',
                              child: Text('图包详情'),
                            ),
                          if (usable && (quick || compact))
                            const PopupMenuItem(
                              value: 'tags',
                              child: Text('图包标签'),
                            ),
                          if (compact &&
                              !quick &&
                              session.range?.previous != null)
                            const PopupMenuItem(
                              value: 'previous',
                              child: Text('上一个'),
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
              ),
            )
          : const SizedBox.shrink(),
    );
    final notices = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controls) ColoredBox(color: p.background, child: status(context)),
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
      ],
    );
    final cleanupNotice = Material(
      key: const Key('reader-cleanup-notice'),
      color: p.background,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _notice,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.olive),
              ),
            ),
            if (_noticeUndo?.canUndo == true)
              TextButton(
                key: const Key('reader-notice-undo'),
                onPressed: () {
                  final item = _noticeUndo!;
                  setState(clearNotice);
                  unawaited(undoQuick(item));
                },
                child: const Text('撤销'),
              )
            else
              const SizedBox(height: 40),
          ],
        ),
      ),
    );
    final canvas = Expanded(
      key: const Key('reader-stage-layout'),
      child: ColoredBox(
        key: const Key('reader-canvas'),
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
                    child: IgnorePointer(
                      ignoring: session.cleanupBusy || session.cleanupFrozen,
                      child: Listener(
                        onPointerDown: chromePointerDown,
                        onPointerUp: chromePointerUp,
                        onPointerCancel: chromePointerCancel,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = constraints.biggest;
                            if (showingEnd) return end();
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
                                    tap: toggleControls,
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
                                    resetZoom: zoomReset,
                                    onZoom: (value) {
                                      if (mounted && zoomed != value) {
                                        setState(() => zoomed = value);
                                      }
                                    },
                                    size: size,
                                    picture: picture,
                                    end: end,
                                    tap: toggleControls,
                                  );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (quick && session.cleanupSupported)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: SizedBox.square(
                        dimension: 80,
                        child: FloatingActionButton(
                          key: const Key('reader-trash-pack'),
                          heroTag: null,
                          tooltip: '移入回收站',
                          backgroundColor: p.background,
                          foregroundColor: p.danger,
                          elevation: 3,
                          shape: CircleBorder(side: BorderSide(color: p.line)),
                          onPressed:
                              session.inputBlocked ||
                                  _stepping ||
                                  !session.opened ||
                                  (_quickCleanup?.hiddenIds.contains(pack.id) ??
                                      false)
                              ? null
                              : removeCurrent,
                          child: const Icon(Icons.delete_outline, size: 36),
                        ),
                      ),
                    ),
                  if (!controls && !quick)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: GestureDetector(
                        onTap: () => setState(() => controls = true),
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
    );
    final bottom = chrome(
      controls && usable
          ? ColoredBox(
              color: compact
                  ? p.background.withValues(alpha: .93)
                  : p.background,
              child: Padding(
                key: const Key('reader-controls'),
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 16,
                  3,
                  compact ? 12 : 16,
                  compact ? 5 : 9,
                ),
                child: Column(
                  children: [
                    if (!quick)
                      Row(
                        children: [
                          IconButton(
                            style: chromeButtonStyle,
                            tooltip: '上一张',
                            onPressed:
                                !session.inputBlocked && session.index > 0
                                ? () => jump(session.index - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left, size: 20),
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7.5,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                ),
                                child: Slider(
                                  // A fresh Slider state avoids reparenting its internal
                                  // global-key semantics while a modal blocks this route
                                  // (Flutter 3.47, flutter/flutter#193706).
                                  key: ValueKey(
                                    !session.inputBlocked && session.total > 1,
                                  ),
                                  value: session.index.toDouble(),
                                  min: 0,
                                  max: max(1, session.total - 1).toDouble(),
                                  onChanged:
                                      !session.inputBlocked && session.total > 1
                                      ? (value) => jump(value.round())
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            '${session.index + 1} / ${session.total}',
                            style: p.title.copyWith(fontSize: 14),
                          ),
                          IconButton(
                            style: chromeButtonStyle,
                            tooltip: '下一张',
                            onPressed: !session.inputBlocked && !showingEnd
                                ? () => jump(session.index + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right, size: 20),
                          ),
                        ],
                      ),
                    if (!quick && !compact)
                      Row(
                        key: const Key('reader-tools'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tool('总览', PaperGlyph.grid, overview),
                          tool(
                            session.preferences.mode == ReaderMode.horizontal
                                ? '横向翻页'
                                : '纵向拼接',
                            session.preferences.mode == ReaderMode.horizontal
                                ? PaperGlyph.horizontal
                                : PaperGlyph.vertical,
                            settings,
                          ),
                          tool('图包标签', PaperGlyph.tag, () async {
                            if (await session.flush()) {
                              await widget.editTags(session.range!.pack!);
                              if (session.live) {
                                await session.reload();
                              }
                            }
                          }),
                          if (!quick)
                            tool(
                              '沉浸',
                              PaperGlyph.expand,
                              () => setState(() => controls = false),
                            ),
                        ],
                      ),
                    if (!compact || quick) ...[
                      if (!quick) Divider(height: 8, color: p.line),
                      rangeNavigation(),
                    ],
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
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
            child: LayoutBuilder(
              builder: (context, available) => Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      if (!compact) header,
                      if (!compact) notices,
                      canvas,
                      if (!compact) bottom,
                    ],
                  ),
                  if (compact)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [header, notices],
                      ),
                    ),
                  if (compact && controls && usable)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: quick ? 430 : 360,
                            maxHeight: available.maxHeight * .6,
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(9),
                            ),
                            child: SingleChildScrollView(child: bottom),
                          ),
                        ),
                      ),
                    ),
                  if (_notice.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 56,
                      right: 56,
                      child: cleanupNotice,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget rangeNavigation() {
    final scope = TextButton(
      key: const Key('reader-scope'),
      onPressed: session.inputBlocked || _stepping ? null : queue,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.zero,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              sourceCaption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Paper.of(context).muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${session.displayPosition} / ${session.displayCount}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Paper.of(context).muted,
            ),
          ),
        ],
      ),
    );
    final previous = TextButton(
      onPressed:
          session.inputBlocked || _stepping || session.range?.previous == null
          ? null
          : () => moveAdjacent(-1),
      child: const Text('上一个', style: TextStyle(fontSize: 13)),
    );
    final next = TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(84, 44)),
      onPressed: session.range?.next == null
          ? close
          : session.inputBlocked || _stepping
          ? null
          : () => moveAdjacent(1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.range?.next == null ? '返回来源' : '下一个',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          ),
          if (session.range?.next != null) ...[
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ],
      ),
    );
    if (MediaLayout.largeText(context)) {
      return Column(
        children: [
          scope,
          Row(
            mainAxisAlignment: quick
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.end,
            children: [if (quick) previous, next],
          ),
        ],
      );
    }
    return Row(
      children: [
        if (quick) previous,
        Expanded(child: scope),
        next,
      ],
    );
  }

  Widget chrome(Widget child) {
    final duration = MediaLayout.motion(context, 140);
    return session.opened && duration > Duration.zero
        ? AnimatedSize(duration: duration, child: child)
        : child;
  }

  Widget tool(String label, PaperGlyph icon, VoidCallback action) => Expanded(
    child: InkWell(
      onTap: session.inputBlocked ? null : action,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaperIcon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              MediaLayout.largeText(context) && label.length == 4
                  ? '${label.substring(0, 2)}\n${label.substring(2)}'
                  : label,
              style: TextStyle(fontSize: 12, color: Paper.of(context).olive),
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
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    session.removeListener(changed);
    _noticeTimer?.cancel();
    _quickCleanup?.removeListener(quickCleanupChanged);
    _quickCleanup?.dispose();
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
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '已阅读到末尾',
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
                  child: const Text('下一个'),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: back,
                child: const Text('返回来源'),
              ),
            ],
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: previous,
            child: const Text('返回最后一张'),
          ),
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
  Widget Function(Widget)? frameDecorator,
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
  Drag? pageDrag;

  void startDrag(ScaleStartDetails details) {
    if (zoom || !pages.hasClients) return;
    pageDrag?.cancel();
    pageDrag = pages.position.drag(
      DragStartDetails(globalPosition: details.focalPoint),
      () => pageDrag = null,
    );
    // The image must keep receiving a second pointer while its first pointer
    // drives this drag; ScrollPosition normally ignores children during drags.
    pages.position.context.setIgnorePointer(false);
  }

  void updateDrag(ScaleUpdateDetails details) {
    pageDrag?.update(
      DragUpdateDetails(
        delta: Offset(details.focalPointDelta.dx, 0),
        primaryDelta: details.focalPointDelta.dx,
        globalPosition: details.focalPoint,
      ),
    );
  }

  void endDrag(ScaleEndDetails details) {
    final drag = pageDrag;
    pageDrag = null;
    drag?.end(
      DragEndDetails(
        velocity: details.velocity,
        primaryVelocity: details.velocity.pixelsPerSecond.dx,
      ),
    );
  }

  void cancelDrag() {
    final drag = pageDrag;
    pageDrag = null;
    drag?.cancel();
  }

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
    // Image scale recognition owns the arena. Its unzoomed one-finger input
    // drives this position directly; a competing drag recognizer here can win
    // before pinch detection on devices with a smaller touch slop.
    physics: const NeverScrollableScrollPhysics(),
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
        startDrag: startDrag,
        updateDrag: updateDrag,
        endDrag: endDrag,
        cancelDrag: cancelDrag,
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
    cancelDrag();
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
    required this.startDrag,
    required this.updateDrag,
    required this.endDrag,
    required this.cancelDrag,
  });
  final GestureScaleStartCallback startDrag;
  final GestureScaleUpdateCallback updateDrag;
  final GestureScaleEndCallback endDrag;
  final VoidCallback cancelDrag;
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
  bool pageGesture = false;
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
        // InteractiveViewer's scale recognizer also wins single-finger drags
        // when panEnabled is false. Forward those to the PageView's real scroll
        // activity so page physics, RTL and follow-the-finger movement agree.
        onInteractionStart: (details) {
          pageGesture =
              details.pointerCount == 1 &&
              transform.value.getMaxScaleOnAxis() <= 1.01;
          if (pageGesture) widget.startDrag(details);
        },
        onInteractionUpdate: (details) {
          final enlarged = transform.value.getMaxScaleOnAxis() > 1.01;
          if (pageGesture && (details.pointerCount > 1 || enlarged)) {
            pageGesture = false;
            widget.cancelDrag();
          }
          if (pageGesture) widget.updateDrag(details);
          widget.onZoom(enlarged);
        },
        onInteractionEnd: (details) {
          if (pageGesture) widget.endDrag(details);
          pageGesture = false;
        },
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
    required this.resetZoom,
    required this.onZoom,
    required this.size,
    required this.picture,
    required this.end,
    required this.tap,
  });
  final PackReadingSession session;
  final int jumpEpoch, resetZoom;
  final ValueChanged<bool> onZoom;
  final Size size;
  final _Picture picture;
  final Widget Function() end;
  final VoidCallback tap;
  @override
  State<_VerticalReader> createState() => _VerticalReaderState();
}

typedef _StripAnchor = ({String id, double ratio, double trailing});

class _VerticalReaderState extends State<_VerticalReader> {
  final scroll = ScrollController();
  String stamp = '';
  bool positioning = true, pinching = false, userScroll = false;
  bool cancelledGesture = false;
  List<int> indexes = [];
  List<String> ids = [];
  List<double> tops = [], extents = [];
  double footer = 180, scale = 1, shift = 0;
  double gestureScale = 1, gestureBase = 1, focalX = 0;
  Offset doubleTapPoint = Offset.zero;
  _StripAnchor? pendingAnchor, pinchAnchor;
  double pendingY = 0;
  int layoutRevision = 0;
  Drag? drag;
  ScrollHoldController? hold;

  @override
  void initState() {
    super.initState();
    scroll.addListener(report);
  }

  double get gap => widget.session.preferences.gap ? 12 : 0;
  double height(int index) {
    final page = widget.session.pages[index]!;
    return max(
              120,
              widget.size.width * max(1, page.height) / max(1, page.width),
            ) *
            scale +
        gap;
  }

  _StripAnchor sessionAnchor() => (
    id: widget.session.currentPage!.id,
    ratio: widget.session.offsetRatio,
    trailing: 0,
  );

  // The old laid-out extents are used even if the next window or viewport
  // already changed. IDs keep the anchor valid when the window's head evicts.
  _StripAnchor? anchorAt(double y) {
    if (!scroll.hasClients || ids.isEmpty) return null;
    final offset = max(0.0, scroll.offset + y);
    var at = 0;
    while (at + 1 < ids.length && tops[at + 1] <= offset) {
      at++;
    }
    final within = max(0.0, offset - tops[at]);
    return (
      id: ids[at],
      ratio: (within / extents[at]).clamp(0, 1),
      trailing: max(0.0, within - extents[at]),
    );
  }

  void cancelDrag() {
    final previous = drag;
    drag = null;
    previous?.cancel();
  }

  void releaseHold() {
    hold?.cancel();
    hold = null;
  }

  void beginDrag(Offset global) {
    if (!scroll.hasClients) return;
    releaseHold();
    cancelDrag();
    drag = scroll.position.drag(
      DragStartDetails(globalPosition: global),
      () => drag = null,
    );
    scroll.position.context.setIgnorePointer(false);
    userScroll = true;
  }

  void beginPinch(Offset local, double baseline) {
    pinching = true;
    userScroll = false;
    cancelDrag();
    releaseHold();
    if (scroll.hasClients) hold = scroll.position.hold(() => hold = null);
    gestureScale = scale;
    gestureBase = baseline;
    focalX = (local.dx - shift) / scale;
    pinchAnchor = anchorAt(local.dy);
  }

  void changeGeometry(
    double next,
    double nextShift,
    _StripAnchor? anchor,
    double y,
  ) {
    if (anchor == null) return;
    setState(() {
      pendingAnchor = anchor;
      pendingY = y;
      positioning = true;
      layoutRevision++;
      scale = next.clamp(1, 4);
      shift = nextShift.clamp(widget.size.width * (1 - scale), 0);
    });
    widget.onZoom(scale > 1.01);
  }

  void start(ScaleStartDetails details) {
    cancelledGesture = false;
    if (positioning) return;
    if (details.pointerCount > 1) {
      beginPinch(details.localFocalPoint, 1);
    } else {
      pinching = false;
      beginDrag(details.focalPoint);
    }
  }

  void update(ScaleUpdateDetails details) {
    if (cancelledGesture || (positioning && !pinching)) return;
    if (details.pointerCount > 1) {
      if (!pinching) beginPinch(details.localFocalPoint, details.scale);
      final next = (gestureScale * details.scale / gestureBase).clamp(1.0, 4.0);
      changeGeometry(
        next,
        details.localFocalPoint.dx - focalX * next,
        pinchAnchor,
        details.localFocalPoint.dy,
      );
    } else {
      if (pinching) {
        pinching = false;
        beginDrag(details.focalPoint);
      }
      if (drag == null) beginDrag(details.focalPoint);
      if (scale > 1) {
        final next = (shift + details.focalPointDelta.dx).clamp(
          widget.size.width * (1 - scale),
          0.0,
        );
        if (next != shift) setState(() => shift = next);
      }
      drag?.update(
        DragUpdateDetails(
          delta: Offset(0, details.focalPointDelta.dy),
          primaryDelta: details.focalPointDelta.dy,
          globalPosition: details.focalPoint,
        ),
      );
    }
  }

  void endGesture(ScaleEndDetails details) {
    final previous = drag;
    drag = null;
    previous?.end(
      DragEndDetails(
        velocity: Velocity(
          pixelsPerSecond: Offset(0, details.velocity.pixelsPerSecond.dy),
        ),
        primaryVelocity: details.velocity.pixelsPerSecond.dy,
      ),
    );
    pinching = false;
    releaseHold();
  }

  void doubleTap() {
    pinching = false;
    userScroll = false;
    cancelDrag();
    releaseHold();
    final next = scale > 1.01 ? 1.0 : 2.0;
    final imageX = (doubleTapPoint.dx - shift) / scale;
    changeGeometry(
      next,
      doubleTapPoint.dx - imageX * next,
      anchorAt(doubleTapPoint.dy),
      doubleTapPoint.dy,
    );
  }

  @override
  void didUpdateWidget(_VerticalReader old) {
    super.didUpdateWidget(old);
    final jump = old.jumpEpoch != widget.jumpEpoch;
    if (jump ||
        old.resetZoom != widget.resetZoom ||
        old.size.width != widget.size.width) {
      pendingAnchor = jump ? null : anchorAt(0);
      if (jump) stamp = '';
      pendingY = 0;
      positioning = true;
      pinching = userScroll = false;
      cancelledGesture = true;
      cancelDrag();
      releaseHold();
      scale = 1;
      shift = 0;
      layoutRevision++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scale <= 1.01) widget.onZoom(false);
      });
    }
  }

  void report() {
    if (positioning ||
        pinching ||
        !userScroll ||
        !scroll.hasClients ||
        indexes.isEmpty) {
      return;
    }
    final offset = scroll.offset;
    var at = 0;
    while (at + 1 < indexes.length && tops[at + 1] <= offset) {
      at++;
    }
    final index = indexes[at],
        ratio = ((offset - tops[at]) / extents[at]).clamp(0.0, 1.0);
    widget.session.show(
      index,
      ratio: ratio,
      end: index == widget.session.total - 1 && scroll.position.extentAfter < 2,
    );
    extendWindow(index);
  }

  void extendWindow(int index) {
    if (indexes.isEmpty || widget.session.loadingPages) return;
    if (index >= indexes.last - 2 && indexes.last < widget.session.total - 1) {
      unawaited(widget.session.ensure(indexes.last + 1));
    } else if (index <= indexes.first + 2 && indexes.first > 0) {
      unawaited(widget.session.ensure(indexes.first - 1));
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
    final next =
        '${s.packEpoch}:${s.windowStart}:${s.windowEnd}:${widget.size}:${s.preferences.gap}:${widget.jumpEpoch}:$layoutRevision';
    final reflow = next != stamp;
    final anchor = reflow
        ? pendingAnchor ??
              (stamp.isEmpty ? null : anchorAt(0)) ??
              sessionAnchor()
        : null;
    final focalY = pendingAnchor == null ? 0.0 : pendingY;
    indexes = s.pages.keys.toList();
    ids = [for (final i in indexes) s.pages[i]!.id];
    tops = [];
    extents = [];
    var total = 0.0;
    for (final i in indexes) {
      tops.add(total);
      final extent = height(i);
      extents.add(extent);
      total += extent;
    }
    footer = MediaLayout.largeText(context) ? 260 : 180;
    if (reflow) {
      stamp = next;
      positioning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !scroll.hasClients ||
            indexes.isEmpty ||
            stamp != next) {
          return;
        }
        final selected = ids.indexOf(anchor!.id);
        final at = selected >= 0 ? selected : indexes.indexOf(s.index);
        if (at >= 0) {
          final ratio = selected >= 0 ? anchor.ratio : s.offsetRatio;
          scroll.jumpTo(
            (tops[at] + ratio * extents[at] + anchor.trailing - focalY).clamp(
              0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
        pendingAnchor = null;
        pendingY = 0;
        setState(() => positioning = false);
        // Loading a neighboring window is read-only. It must still work when
        // resuming at an edge, without marking a reflow as new reading progress.
        if (!pinching) extendWindow(s.index);
      });
    }
    if (indexes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      key: const Key('reader-vertical-gestures'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.tap,
      onScaleStart: start,
      onScaleUpdate: update,
      onScaleEnd: endGesture,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          userScroll = false;
          return false;
        },
        child: ListView.builder(
          key: const Key('reader-vertical'),
          controller: scroll,
          // One scale recognizer owns both fingers. Ordinary vertical input is
          // forwarded to the real ScrollPosition, including ballistic motion.
          physics: const NeverScrollableScrollPhysics(),
          scrollCacheExtent: const ScrollCacheExtent.pixels(180),
          itemCount: indexes.length + 1,
          itemExtentBuilder: (at, dimensions) =>
              at == indexes.length ? footer : extents[at],
          itemBuilder: (context, at) {
            if (at == indexes.length) {
              return indexes.last == s.total - 1
                  ? widget.end()
                  : const Center(child: CircularProgressIndicator());
            }
            final index = indexes[at], page = s.pages[index]!;
            final size = Size(widget.size.width * scale, extents[at] - gap);
            return Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: size.width,
                maxWidth: size.width,
                child: Transform.translate(
                  key: ValueKey('reader-strip-${page.id}'),
                  offset: Offset(shift, 0),
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: widget.picture(
                      page,
                      index,
                      size,
                      visible: () => !positioning && !pinching,
                      frameDecorator: (child) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTapDown: (details) {
                          final box =
                              this.context.findRenderObject()! as RenderBox;
                          doubleTapPoint = box.globalToLocal(
                            details.globalPosition,
                          );
                        },
                        onDoubleTap: doubleTap,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    cancelDrag();
    releaseHold();
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
                        active: !busy,
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
