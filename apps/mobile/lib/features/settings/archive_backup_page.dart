import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/backup_file_picker.dart';
import '../../library/management_archives.dart';
import '../../library/models.dart';
import '../../library/repository.dart';
import '../../library/request_scope.dart';
import '../../ui/paper.dart';
import '../../ui/paper_form.dart';
import '../../ui/paper_management.dart';

class ArchiveBackupPage extends StatefulWidget {
  const ArchiveBackupPage({
    super.key,
    required this.repository,
    required this.archives,
    required this.onOpenTasks,
    this.files = const NativeBackupArchiveFiles(),
  });
  final LibraryRepository repository;
  final ManagementArchiveRepository archives;
  final BackupArchiveFiles files;
  final VoidCallback onOpenTasks;
  @override
  State<ArchiveBackupPage> createState() => _ArchiveBackupPageState();
}

class _ArchiveBackupPageState extends State<ArchiveBackupPage> {
  late final connection = widget.repository.connectionIdentity;
  final scope = RequestScope();
  late final int maximum;
  bool busy = false;
  String error = '', message = '', snapshotError = '';
  ArchiveRestorePoint? restorePoint;
  bool get current =>
      identical(connection, widget.repository.connectionIdentity);
  @override
  void initState() {
    super.initState();
    maximum = widget.archives.archiveMaximumBytes;
    widget.repository.addListener(ownerChanged);
    unawaited(loadRestorePoint());
  }

  Future<void> loadRestorePoint() async {
    try {
      final value = await widget.archives.latestArchiveRestorePoint();
      if (mounted && current) setState(() => restorePoint = value);
    } catch (_) {
      if (mounted && current) {
        setState(() => snapshotError = '暂时无法读取恢复前快照，可在后台操作结果中查询');
      }
    }
  }

  void ownerChanged() {
    if (!mounted) return;
    if (!current) {
      scope.cancel();
      error = '管理数据或连接已变化，请返回后重新打开';
    }
    setState(() {});
  }

  @override
  void dispose() {
    scope.cancel();
    widget.repository.removeListener(ownerChanged);
    super.dispose();
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = message = '';
    });
    try {
      await action();
    } on RequestCancelled {
      /* Original receipt remains with its captured owner. */
    } catch (failure) {
      if (mounted && current) {
        setState(
          () => error = failure is LibraryFailure
              ? failure.message
              : '操作未完成，原备份任务已保留，请查询原结果',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> preview(ArchivePreview value) async {
    if (!mounted || !current) return;
    final page = ArchiveRestorePage(
      repository: widget.repository,
      archives: widget.archives,
      preview: value,
      asSheet: value.rootsTotal <= 2,
    );
    if (value.rootsTotal <= 2) {
      await paperSheet<void>(context, page, dismissible: false);
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    final pending = widget.repository.backupRestorePending;
    final disabled = busy || !current || pending;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 22),
      children: [
        const Text('保存你的整理成果', style: TextStyle(fontSize: 14, height: 1.6)),
        const SizedBox(height: 12),
        Text(
          '包含两套标签与关联、目录映射、回收站、预览轮次、图包进度和阅读偏好。不包含媒体文件、个人口令与本机外观偏好。',
          style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: widget.repository.backupStatus,
          builder: (_, status, _) => AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            child: status == null
                ? const SizedBox.shrink()
                : Text(
                    status,
                    key: const Key('backup-status'),
                    style: const TextStyle(fontSize: 12),
                  ),
          ),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error,
              key: const Key('archive-error'),
              style: TextStyle(color: Paper.of(context).danger),
            ),
          ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message, key: const Key('archive-message')),
          ),
        const SizedBox(height: 20),
        PaperActionRow(
          key: const Key('archive-export'),
          title: '导出备份',
          trailing: const Icon(Icons.keyboard_arrow_down, size: 20),
          onTap: disabled
              ? null
              : () => act(() async {
                  final exported = await widget.archives.exportArchive();
                  if (!mounted || !current) return;
                  final saved = await widget.files.save(
                    exported.document,
                    scope: scope,
                  );
                  if (!mounted || !current) return;
                  if (saved) {
                    await widget.archives.archiveSaved(exported.taskId);
                    if (mounted && current) {
                      setState(() => message = '已导出管理数据备份');
                    }
                  } else {
                    setState(() => message = '保存已取消，原导出任务已保留');
                  }
                }),
        ),
        PaperActionRow(
          key: const Key('archive-pick'),
          title: '选择备份文件',
          onTap: disabled
              ? null
              : () => act(() async {
                  final store = await widget.archives.archiveFileStore();
                  final document = await widget.files.pick(
                    store,
                    maximumBytes: maximum,
                    scope: scope,
                  );
                  if (!mounted || !current) {
                    await document?.delete();
                    return;
                  }
                  if (document != null) {
                    await preview(
                      await widget.archives.inspectArchive(document),
                    );
                  }
                }),
        ),
        if (widget.archives.archivePreviewPending && !pending)
          TextButton(
            key: const Key('archive-resume-preview'),
            onPressed: disabled
                ? null
                : () => act(
                    () async =>
                        preview(await widget.archives.resumeArchivePreview()),
                  ),
            child: const Text('继续核对已选备份'),
          ),
        const SizedBox(height: 24),
        Text(
          '先校验，再核对目录映射。恢复前保留当前管理数据快照。已永久删除的源文件不会从备份恢复。',
          style: TextStyle(fontSize: 13, height: 1.8, color: p.catalogMeta),
        ),
        const SizedBox(height: 8),
        Text(
          '文件上限 ${maximum >= 1024 * 1024 ? '${maximum ~/ (1024 * 1024)} MiB' : '${maximum ~/ 1024} KiB'}',
          style: TextStyle(fontSize: 12, height: 1.7, color: p.catalogMeta),
        ),
        if (pending) ...[
          note('恢复结果待确认，请查询原任务。关闭页面不会取消服务端恢复。'),
          FilledButton(
            key: const Key('archive-query-restore'),
            onPressed: busy || !current
                ? null
                : () => act(widget.repository.reconcileBackupRestore),
            child: const Text('查询恢复结果'),
          ),
        ],
        if (restorePoint case final point?) ...[
          const SizedBox(height: 16),
          PaperActionRow(
            key: const Key('archive-restore-point'),
            title: '恢复前的快照',
            details: [
              Text(
                '查看并恢复上一次替换前的管理数据',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: p.catalogMeta,
                ),
              ),
            ],
            trailing: const Icon(Icons.chevron_right),
            onTap: disabled
                ? null
                : () => act(() async {
                    await preview(
                      await widget.archives.inspectArchiveRestorePoint(point),
                    );
                  }),
          ),
        ],
        if (snapshotError.isNotEmpty) note(snapshotError),
        TextButton(
          onPressed: current ? widget.onOpenTasks : null,
          child: const Text('查看后台操作结果'),
        ),
      ],
    );
  }
}

class ArchiveRestorePage extends StatefulWidget {
  const ArchiveRestorePage({
    super.key,
    required this.repository,
    required this.archives,
    required this.preview,
    this.asSheet = false,
  });
  final LibraryRepository repository;
  final ManagementArchiveRepository archives;
  final ArchivePreview preview;
  final bool asSheet;
  @override
  State<ArchiveRestorePage> createState() => _ArchiveRestorePageState();
}

class _ArchiveRestorePageState extends State<ArchiveRestorePage> {
  late final connection = widget.repository.connectionIdentity;
  final fields = <String, TextEditingController>{};
  List<ArchiveRoot> roots = [];
  int offset = 0, read = 0;
  bool loading = true, checked = false, restoring = false;
  String error = '';
  final scroll = ScrollController();
  final errorAnchor = GlobalKey();
  void revealError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scroll.hasClients) scroll.jumpTo(0);
      revealFormError(errorAnchor);
    });
  }

  Future<void> turn(int at) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await load(at);
    if (mounted && current && error.isEmpty && scroll.hasClients) {
      scroll.jumpTo(0);
    }
  }

  bool get current =>
      identical(connection, widget.repository.connectionIdentity);
  bool get complete => fields.length == widget.preview.rootsTotal;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(changed);
    unawaited(load(0));
  }

  void changed() {
    if (mounted && !current && !restoring) {
      setState(() => error = '管理数据或连接已变化，请关闭预览重新读取');
      revealError();
    }
  }

  @override
  void dispose() {
    read++;
    widget.repository.removeListener(changed);
    scroll.dispose();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> load(int at) async {
    if (!current) return;
    final serial = ++read;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final page = await widget.archives.archiveRoots(
        widget.preview,
        offset: at,
      );
      if (!mounted || !current || read != serial) return;
      for (final root in page.items) {
        fields.putIfAbsent(
          root.id,
          () => TextEditingController(text: root.suggestedPath ?? ''),
        );
      }
      setState(() {
        roots = page.items;
        offset = at;
      });
    } on RequestCancelled {
      /* Obsolete preview. */
    } catch (failure) {
      if (mounted && current && read == serial) {
        setState(
          () => error = failure is LibraryFailure
              ? failure.message
              : '目录读取未完成，已有映射已保留',
        );
        revealError();
      }
    } finally {
      if (mounted && read == serial) setState(() => loading = false);
    }
  }

  Future<void> restore() async {
    if (restoring || !current || !checked || !complete) return;
    FocusScope.of(context).unfocus();
    setState(() {
      restoring = true;
      error = '';
    });
    try {
      await widget.archives.restoreArchive(widget.preview, {
        for (final entry in fields.entries)
          entry.key: entry.value.text.trim().isEmpty ? null : entry.value.text,
      });
      if (mounted) Navigator.pop(context);
    } on RequestCancelled {
      /* Old journal is retained when another restore changes authority. */
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is LibraryFailure
              ? failure.message
              : '恢复结果尚未确认，请到操作任务查询原结果',
        );
        revealError();
      }
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = widget.preview.counts;
    final pending = widget.repository.backupRestorePending;
    final editable =
        current && !restoring && !pending && widget.preview.protocol == 2;
    final footer = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton(
          key: const Key('archive-restore-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(restoring || pending ? '关闭' : '取消'),
        ),
        FilledButton(
          key: const Key('archive-restore-submit'),
          onPressed: editable && checked && complete && !loading
              ? restore
              : null,
          child: Text(restoring ? '正在恢复…' : '确认恢复'),
        ),
      ],
    );
    final content = <Widget>[
      KeyedSubtree(
        key: errorAnchor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error,
                  key: const Key('archive-restore-error'),
                  style: TextStyle(color: Paper.of(context).danger),
                ),
              ),
              if (!pending)
                TextButton(
                  onPressed: loading || !current ? null : () => load(offset),
                  child: const Text('重新读取本页'),
                ),
            ],
          ],
        ),
      ),

      note(
        widget.preview.protocol == 1
            ? '这是旧协议的原预览，仅供查看。请返回重新选择原文件，完成新版校验后再恢复。'
            : '校验通过。恢复会替换现有管理数据，请核对目录映射；留空表示暂不启用该目录。',
      ),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Paper.of(context).soft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '视频 ${counts['videos'] ?? 0} · 视频标签 ${counts['tags'] ?? 0}\n图包 ${counts['packs'] ?? 0} · 图片 ${counts['pack_pages'] ?? 0} · 图包标签 ${counts['pack_tag_definitions'] ?? 0}\n回收记录 ${(counts['trash_items'] ?? 0) + (counts['pack_trash_items'] ?? 0)} · 阅读记录 ${counts['pack_progress'] ?? 0}',
          key: const Key('archive-counts'),
          style: const TextStyle(fontSize: 13, height: 1.7),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        '媒体目录 · 已载入 ${fields.length}/${widget.preview.rootsTotal}',
        key: const Key('archive-root-count'),
      ),
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
      for (final root in roots)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaperField(
                label:
                    '${root.name} · ${root.kind == MediaKind.video ? '视频' : '图包'}',
                child: TextField(
                  key: Key('archive-mapping-${root.id}'),
                  controller: fields[root.id],
                  enabled: editable,
                  maxLines: null,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(hintText: '留空表示暂不启用'),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '原目录：${root.path}${root.enabled ? '' : '\n原备份中已停用'}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: Paper.of(context).catalogMeta,
                ),
              ),
            ],
          ),
        ),
      if (widget.preview.rootsTotal > 24)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: editable && !loading && offset > 0
                    ? () => turn(offset - 24)
                    : null,
                child: const Text('上一页'),
              ),
              Text(
                '${offset ~/ 24 + 1} / ${(widget.preview.rootsTotal + 23) ~/ 24}',
              ),
              TextButton(
                onPressed:
                    editable &&
                        !loading &&
                        offset + 24 < widget.preview.rootsTotal
                    ? () => turn(offset + 24)
                    : null,
                child: const Text('下一页'),
              ),
            ],
          ),
        ),
      if (!complete && !loading) note('请查看剩余目录并核对映射，再确认恢复。'),
      CheckboxListTile(
        key: const Key('archive-confirm'),
        contentPadding: EdgeInsets.zero,
        value: checked,
        onChanged: editable && complete && !loading
            ? (value) => setState(() => checked = value!)
            : null,
        title: const Text('我知道恢复会替换现有管理数据', style: TextStyle(fontSize: 13)),
      ),
      note('恢复不会回滚磁盘文件删除，也不修改连接口令、本机暗黑模式和相邻视频准备。'),
      if (pending) note('原恢复已提交。可关闭此页，在备份或操作任务查询结果；不会再次提交恢复。'),
    ];
    if (widget.asSheet) {
      return SheetFrame(title: '恢复备份', footer: footer, children: content);
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PaperManagementHeader(
              title: '恢复备份',
              closeLabel: '关闭备份预览',
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: PaperManagementForm(
                controller: scroll,
                footer: footer,
                children: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
