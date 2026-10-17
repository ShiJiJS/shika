import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../library/models.dart';
import '../library/repository.dart';
import 'paper.dart';
import 'player.dart';
import 'sheets.dart';
import 'preferences.dart';
import 'media_poster.dart';
import 'playback_session.dart';

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
    required this.preferences,
    this.initializeRepository = false,
  });
  final LibraryRepository repository;
  final String? initialError;
  final BackupFiles? backupFiles;
  final UiPreferences preferences;
  final bool initializeRepository;
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  final _playback = PlaybackSession();
  LibraryRepository get repo => widget.repository;
  LibrarySnapshot get data => repo.snapshot;
  late String page = data.connected ? 'browse' : 'connection';
  late String error = widget.initialError ?? '';
  bool _busy = false, review = false, selecting = false, obscured = false;
  bool get busy => _busy || repo.backupRestorePending;
  String search = '', tagSearch = '';
  Set<String> selected = {};
  int playerEpoch = 0;
  List<LibraryVideo> libraryItems = [];
  int libraryTotal = 0, libraryGeneration = 0;
  bool libraryLoading = false;
  final libraryScroll = ScrollController();
  String libraryError = '', libraryKey = '', previousScope = '';
  List<LibraryVideo> trashItems = [];
  int trashTotal = 0, trashGeneration = 0;
  bool trashLoading = false;
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
    'connection': '连接',
  }[page]!;
  bool get mediaPage => page == 'browse' || page == 'library';
  bool get primaryPage =>
      ['browse', 'library', 'tags', 'settings'].contains(page);
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
    repo.addListener(changed);
    repo.libraryPreparation.addListener(preparationChanged);
    libraryScroll.addListener(loadNearBottom);
    address.text = data.address;
    port.text = '${data.port}';
    previousScope = jsonEncode(data.query.toJson());
    if (repo is DemoControls) passphrase.text = 'demo';
    if (widget.initializeRepository) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final connected = await perform(repo.initialize);
        if (!mounted) return;
        address.text = data.address;
        port.text = '${data.port}';
        if (connected && data.connected) {
          go(repo.backupRestorePending ? 'backup' : 'browse');
        }
      });
    }
  }

  void changed() {
    if (!mounted) return;
    final nextScope = jsonEncode(data.query.toJson());
    setState(() {
      if (nextScope != previousScope) {
        selected = {};
        previousScope = nextScope;
      }
      if (!data.connected && page != 'connection') page = 'connection';
      if (!data.connected && repo.connectionError != null) {
        error = repo.connectionError!;
      }
    });
    if (page == 'library') unawaited(loadLibrary());
    if (page == 'trash') unawaited(loadTrash());
    if (page == 'roots') unawaited(loadMissing());
  }

  void preparationChanged() {
    if (mounted) setState(() {});
  }

  void loadNearBottom() {
    if (page == 'library' &&
        libraryScroll.hasClients &&
        libraryScroll.position.extentAfter < 480 &&
        !libraryLoading &&
        libraryError.isEmpty &&
        libraryItems.isNotEmpty &&
        libraryItems.length < libraryTotal) {
      unawaited(loadLibrary(more: true));
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
    if (page != 'trash' || (more && trashLoading)) return;
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

  Future<void> loadLibrary({bool more = false}) async {
    if (page != 'library' || (more && libraryLoading)) return;
    final generation = ++libraryGeneration;
    final scope = data.query;
    final text = search;
    final key = jsonEncode([scope.toJson(), text]);
    final offset = more ? libraryItems.length : 0;
    setState(() {
      libraryLoading = true;
      libraryError = '';
      if (key != libraryKey) {
        libraryItems = [];
        libraryTotal = 0;
        selected = {};
      }
      libraryKey = key;
    });
    try {
      final result = await repo.loadVideos(
        scope: scope,
        search: text,
        offset: offset,
        limit: 24,
      );
      if (!mounted || generation != libraryGeneration || page != 'library') {
        return;
      }
      setState(() {
        libraryItems = more ? [...libraryItems, ...result.items] : result.items;
        libraryTotal = result.total;
        if (more &&
            result.items.isEmpty &&
            libraryItems.length < result.total) {
          libraryError = '视频列表已变化，请刷新后继续';
        }
      });
    } on RequestCancelled {
      // A newer query or another page owns the visible state.
    } catch (failure) {
      if (mounted && generation == libraryGeneration) {
        setState(() => libraryError = failure.toString());
      }
    } finally {
      if (mounted && generation == libraryGeneration) {
        setState(() => libraryLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) loadNearBottom();
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_playback.close());
    libraryGeneration++;
    trashGeneration++;
    missingGeneration++;
    repo.cancelVideoRead();
    repo.cancelTrashRead();
    repo.cancelMissingRead();
    repo.removeListener(changed);
    repo.libraryPreparation.removeListener(preparationChanged);
    libraryScroll.dispose();
    address.dispose();
    port.dispose();
    passphrase.dispose();
    super.dispose();
  }

  void go(String next) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() {
      page = next;
      selected = {};
      selecting = false;
    });
    if (next == 'library') {
      unawaited(loadLibrary());
    } else {
      libraryGeneration++;
      repo.cancelVideoRead();
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
      unawaited(loadMissing());
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
      ScopeSheet(repository: repo, review: quick),
    );
    if (q != null) {
      await perform(() async {
        await repo.setScope(q);
        playerEpoch++;
      });
    }
  }

  Future<void> folder() async {
    final value = await sheet<String>(
      FolderPicker(repository: repo, initial: data.query.folder),
    );
    if (value != null) {
      await perform(() async {
        await repo.setScope(data.query.copy(folder: value));
        playerEpoch++;
      });
    }
  }

  Future<void> order() async {
    final mode = await sheet<PlayOrder>(
      SheetFrame(
        title: '播放模式',
        children: [
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
                value == PlayOrder.random ? '本轮向前不重复，允许回看' : '按目录和文件名排列',
              ),
              trailing: data.order == value ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (mode != null) {
      await perform(() async {
        await repo.setScope(data.query, order: mode);
        playerEpoch++;
      });
    }
  }

  Future<bool> step(int delta) async {
    if (data.round.isEmpty || busy || obscured) return false;
    // The adjacent window may have no next playable entry even when a missing
    // tail is still included in the server's candidate count until a scan.
    if (delta > 0 && data.position == data.round.length - 1) {
      if (!await perform(() => repo.step(delta)) || !mounted) return false;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            margin: snackMargin,
            content: const Text('本轮已看完'),
            action: SnackBarAction(
              label: '开始新一轮',
              onPressed: () => perform(() async {
                await repo.newRound();
                playerEpoch++;
              }),
            ),
          ),
        );
      return false;
    }
    return perform(() => repo.step(delta));
  }

  Future<void> tag(Set<String> ids) async {
    final saved = await sheet<bool>(TagEditor(repository: repo, ids: {...ids}));
    if (saved == true) {
      setState(() {
        selected = {};
        selecting = false;
      });
      notice('标签已保存');
    }
  }

  Future<void> remove(Set<String> ids) async {
    final requestId = 'delete-${DateTime.now().microsecondsSinceEpoch}';
    final previous = data.lastDelete?.id;
    final completed = await perform(
      () => repo.deleteVideos({...ids}, requestId: requestId),
    );
    if (!mounted) return;
    final operation = data.lastDelete;
    if (operation != null && operation.id != previous) {
      setState(() {
        selected.removeAll(operation.ids);
        if (completed) selecting = false;
      });
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            margin: snackMargin,
            content: Text(
              completed ? '已移入回收站' : '已移入 ${operation.ids.length} 个，其余未完成',
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () => perform(() async {
                if (data.lastDelete?.id != operation.id) {
                  throw const LibraryFailure('这次删除已失效，请在回收站查看');
                }
                await repo.undoDelete(operationId: operation.id);
              }),
            ),
          ),
        );
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
    final current = repo.current;
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
          await perform(() => repo.undoDelete(operationId: operation.id));
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
          playerEpoch++;
        });
      case 'delete':
        if (current != null) await remove({current.id});
      default:
        go(action);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
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
    child: Scaffold(
      bottomNavigationBar: primaryPage
          ? SafeArea(top: false, child: bottomNav())
          : null,
      body: SafeArea(
        bottom: !primaryPage,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: Row(
                  children: [
                    if (!primaryPage)
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
                              : '${data.round.isEmpty ? '00' : (repo.playbackPosition + 1).toString().padLeft(2, '0')} / ${repo.playbackTotal.toString().padLeft(2, '0')}',
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
                                if (repo.current != null)
                                  const PopupMenuItem(
                                    value: 'tag',
                                    child: Text('打标签'),
                                  ),
                                if (repo.current != null)
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
                                if (repo.current != null)
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
            SizedBox(
              height: 2,
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
            if (data.connected && repo.fileOperationPending)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('文件操作结果待确认', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => perform(repo.reconcileFileOperation),
                      child: const Text('查询结果'),
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
                builder: (context, message, _) =>
                    message == null || message == error
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
            Expanded(
              child: switch (page) {
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
                'connection' => connection(),
                _ => const SizedBox(),
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget bottomNav() => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Paper.of(context).line)),
    ),
    child: Center(
      heightFactor: 1,
      child: SizedBox(
        width: 300,
        height: 52,
        child: Row(
          children: [
            for (final tab in [
              ('browse', '浏览', Icons.smart_display_outlined),
              ('library', '视频库', Icons.grid_view),
              ('tags', '标签', Icons.sell_outlined),
              ('settings', '设置', Icons.settings_outlined),
            ])
              Expanded(
                child: InkWell(
                  key: Key('nav-${tab.$1}'),
                  onTap: _busy ? null : () => go(tab.$1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        tab.$3,
                        size: 19,
                        color: page == tab.$1
                            ? Paper.of(context).olive
                            : Paper.of(context).muted,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tab.$2,
                        style: TextStyle(
                          fontSize: 10,
                          color: page == tab.$1
                              ? Paper.of(context).olive
                              : Paper.of(context).muted,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(top: 3),
                        width: 18,
                        height: 2,
                        color: page == tab.$1
                            ? Paper.of(context).olive
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
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
          if (state.failed > 0 || state.deferred > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${state.failed} 个读取失败 · ${state.deferred} 个等待文件稳定',
                style: TextStyle(fontSize: 11, color: p.muted),
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

  Widget browsing() {
    if (!repo.libraryPreparation.value.ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: preparationCard(locked: true),
        ),
      );
    }
    final current = repo.current;
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
                        repo.current?.id != video.id) {
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
                    : () async {
                        if (await perform(
                          () => repo.openVideo(results.first.id),
                        )) {
                          go('browse');
                        }
                      },
                child: const Text('播放'),
              ),
            ],
          ),
        ),
        if (data.query.count > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (data.query.folder.isNotEmpty) data.query.folder,
                      ...data.query.tags.map((t) => '# ${repo.tagName(t)}'),
                      if (data.query.orientation.isNotEmpty)
                        data.query.orientation == 'portrait' ? '竖版' : '横版',
                      if (data.query.duration.isNotEmpty)
                        data.query.duration == 'short' ? '10 秒以内' : '10 秒以上',
                      data.query.type,
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
                      : () => perform(() => repo.setScope(VideoQuery())),
                  child: const Text('清除'),
                ),
              ],
            ),
          ),
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
                          : data.query.count > 0 || search.isNotEmpty
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
                                      } else if (await perform(
                                        () => repo.openVideo(v.id),
                                      )) {
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
                                      onPressed: () => loadLibrary(more: true),
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
                                          : results.length >= total
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
  }) => Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Paper.of(context).olive),
              ),
        trailing: const Icon(Icons.chevron_right, size: 19),
        onTap: _busy || (!allowDuringRestore && repo.backupRestorePending)
            ? null
            : action,
      ),
      const Divider(height: 1),
    ],
  );
  Widget settings() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    children: [
      note('连接与文件'),
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
        '${data.roots.length} 个目录 · ${repo.missingCount} 个缺失视频',
        () => go('roots'),
      ),
      const SizedBox(height: 14),
      note('数据维护'),
      settingRow(
        Icons.delete_outline,
        '回收站',
        '${repo.trashCount} 个视频 · 不会自动清空',
        () => go('trash'),
      ),
      settingRow(
        Icons.save_outlined,
        '备份与恢复',
        '导出标签和管理记录',
        () => go('backup'),
        allowDuringRestore: true,
      ),
      const SizedBox(height: 14),
      note('偏好'),
      SwitchListTile(
        key: const Key('dark-mode-setting'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.dark_mode_outlined),
        title: const Text('暗黑模式'),
        value: widget.preferences.dark,
        onChanged: busy
            ? null
            : (value) => perform(() => widget.preferences.setDark(value)),
      ),
      const Divider(height: 1),
      SwitchListTile(
        key: const Key('preload-setting'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.slow_motion_video),
        title: const Text('准备相邻视频'),
        subtitle: const Text('最多准备前后各一条，关闭可减少网络和解码占用'),
        value: widget.preferences.preloadAdjacent,
        onChanged: busy
            ? null
            : (value) =>
                  perform(() => widget.preferences.setPreloadAdjacent(value)),
      ),
      const Divider(height: 1),
      settingRow(
        Icons.shuffle,
        '播放顺序',
        data.order == PlayOrder.random ? '随机播放' : '顺序播放',
        order,
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
      Text('连接你的视频库', style: Paper.of(context).title),
      const SizedBox(height: 26),
      TextField(
        controller: address,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: '服务地址'),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: port,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '端口'),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: passphrase,
        enabled: !_busy,
        obscureText: true,
        decoration: const InputDecoration(labelText: '个人口令'),
      ),
      const SizedBox(height: 26),
      FilledButton(
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
                  go(repo.backupRestorePending ? 'backup' : 'browse');
                }
              },
        child: Text(_busy ? '正在连接…' : '连接'),
      ),
    ],
  );
  Widget roots() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    children: [
      if (repo is! DemoControls) ...[
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
        ListTile(
          key: Key('root-${r.id}'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: Text(r.name),
          subtitle: Text(
            '${r.path}\n${rootScanLabel(r)}',
            style: TextStyle(
              fontSize: 12,
              color: r.available
                  ? Paper.of(context).olive
                  : Paper.of(context).danger,
            ),
          ),
          trailing: iconAction(
            '编辑目录 ${r.name}',
            Icons.edit_outlined,
            busy ? null : () => rootForm(r),
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
          repo.libraryPreparation.value.scanning ? '扫描进行中' : '刷新媒体目录',
        ),
      ),
      if (missingTotal > 0 || missingItems.isNotEmpty) ...[
        const SizedBox(height: 30),
        Text('缺失视频', style: Paper.of(context).title.copyWith(fontSize: 20)),
        note('保留标签记录，重新找到同一文件后继续关联。'),
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
      const SizedBox(height: 20),
    ],
  );
  Future<void> rootForm([MediaRoot? root]) async {
    final name = TextEditingController(text: root?.name ?? ''),
        path = TextEditingController(text: root?.path ?? '');
    String formError = '';
    bool saving = false;
    await sheet<void>(
      StatefulBuilder(
        builder: (context, local) => SheetFrame(
          title: root == null ? '添加媒体目录' : '编辑媒体目录',
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: path,
              decoration: const InputDecoration(labelText: '挂载目录'),
            ),
            note('扫描包含子目录，不修改源文件位置。'),
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
                        await repo.saveRoot(
                          MediaRoot(
                            root?.id ?? '',
                            name.text.trim(),
                            path.text.trim().replaceAll(RegExp(r'/+$'), ''),
                          ),
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
    name.dispose();
    path.dispose();
  }

  Widget trash() {
    final items = trashItems;
    if (trashError.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(trashError),
            TextButton(onPressed: () => loadTrash(), child: const Text('重试')),
          ],
        ),
      );
    }
    if (items.isEmpty && trashLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) return const EmptyView('回收站是空的');
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              note('不会自动清空；恢复时保留原有标签。'),
              for (final v in items)
                CheckboxListTile(
                  key: Key('trash-${v.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: selected.contains(v.id),
                  title: Text(v.name),
                  subtitle: Text(
                    v.originalPath ?? v.path,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onChanged: busy
                      ? null
                      : (yes) => setState(
                          () =>
                              yes! ? selected.add(v.id) : selected.remove(v.id),
                        ),
                ),
              if (items.length < trashTotal)
                TextButton(
                  onPressed: trashLoading ? null : () => loadTrash(more: true),
                  child: Text(trashLoading ? '正在加载…' : '加载更多'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text('已选 ${selected.length}')),
              OutlinedButton(
                onPressed: busy || selected.isEmpty
                    ? null
                    : () async {
                        List<String> failures = [];
                        if (await perform(() async {
                          failures = await repo.restoreVideos({...selected});
                        })) {
                          setState(() {
                            selected = {};
                            error = failures.join('\n');
                          });
                          if (failures.isEmpty) notice('已恢复，标签保留');
                        }
                      },
                child: const Text('恢复'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: busy || selected.isEmpty
                    ? null
                    : () async {
                        final ids = {...selected};
                        if (await confirm(
                          '永久删除这些视频？',
                          '将永久删除所选 ${ids.length} 个视频，无法撤销。',
                          '永久删除',
                        )) {
                          if (await perform(
                            () => repo.permanentlyDelete(ids),
                          )) {
                            setState(() => selected = {});
                            notice('已永久删除');
                          }
                        }
                      },
                style: TextButton.styleFrom(
                  foregroundColor: Paper.of(context).danger,
                ),
                child: const Text('永久删除'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget backup() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('保存你的整理成果', style: Paper.of(context).title.copyWith(fontSize: 21)),
      note('备份标签、视频关联、媒体目录映射、回收站索引和播放轮次，不包含原视频及访问口令。'),
      ValueListenableBuilder<String?>(
        valueListenable: repo.backupStatus,
        builder: (context, message, _) => message == null
            ? const SizedBox()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  message,
                  key: const Key('backup-status'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                bool saved = false;
                if (await perform(
                      () async => saved = await files.save(
                        await repo.exportBackupFile(),
                      ),
                    ) &&
                    saved) {
                  notice('已导出管理数据备份');
                }
              },
        child: const Text('导出备份'),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: busy
            ? null
            : () async {
                String? text;
                if (await perform(() async {
                      text = await files.open();
                      if (text != null) await repo.inspectBackupFile(text!);
                    }) &&
                    text != null) {
                  await restoreForm(text!);
                }
              },
        child: const Text('选择备份文件'),
      ),
      const SizedBox(height: 18),
      note('完整恢复会替换现有管理数据。已永久删除的视频不会从备份中恢复，也不会回滚磁盘上的文件移动。恢复前会保留当前数据快照。'),
    ],
  );
  Future<void> restoreForm(String text) async {
    final preview = await repo.inspectBackupFile(text);
    if (!mounted) return;
    final mappings = {
      for (final r in preview.snapshot.roots)
        r.id: preview.suggestedMappings.containsKey(r.id)
            ? preview.suggestedMappings[r.id] ?? ''
            : r.path,
    };
    bool checked = false, restoring = false;
    String formError = '';
    await sheet<void>(
      StatefulBuilder(
        builder: (context, local) => PopScope(
          canPop: !restoring,
          child: SheetFrame(
            title: '恢复备份',
            closeEnabled: !restoring,
            children: [
              note('校验通过。请核对媒体目录映射，恢复前将保留当前数据快照。'),
              if (preview.counts.isNotEmpty)
                note(
                  '视频 ${preview.counts['videos'] ?? 0} · 标签 ${preview.counts['tags'] ?? 0} · 回收站 ${preview.counts['trash_items'] ?? 0}',
                ),
              for (final r in preview.snapshot.roots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    key: Key('mapping-${r.id}'),
                    initialValue: mappings[r.id],
                    enabled: !restoring && !repo.backupRestorePending,
                    decoration: InputDecoration(
                      labelText: r.name,
                      helperText: '原目录：${r.path}',
                      hintText: preview.importId == null ? null : '留空表示暂不映射',
                    ),
                    onChanged: (value) => mappings[r.id] = value,
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
                  style: TextStyle(fontSize: 13),
                ),
              ),
              if (formError.isNotEmpty) note(formError),
              FilledButton(
                key: const Key('restore-submit'),
                onPressed: restoring
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
                        }
                        if (context.mounted) local(() => restoring = false);
                      },
                child: Text(
                  restoring
                      ? '正在恢复…'
                      : repo.backupRestorePending
                      ? '查询恢复结果'
                      : '恢复管理数据',
                ),
              ),
              TextButton(
                key: const Key('restore-cancel'),
                onPressed: restoring ? null : () => Navigator.pop(context),
                child: Text(repo.backupRestorePending ? '关闭' : '取消'),
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
        error = '';
        playerEpoch++;
        page = chosen == DemoScenario.offline ? 'connection' : 'browse';
      });
      notice('演示数据已复位');
    }
  }
}
