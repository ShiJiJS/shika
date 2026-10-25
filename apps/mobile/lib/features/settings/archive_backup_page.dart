import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/backup_file_picker.dart';
import '../../library/management_archives.dart';
import '../../library/models.dart';
import '../../library/repository.dart';
import '../../library/request_scope.dart';
import '../../ui/paper.dart';

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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArchiveRestorePage(
          repository: widget.repository,
          archives: widget.archives,
          preview: value,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.repository.backupRestorePending;
    final disabled = busy || !current || pending;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('保存你的整理成果', style: Paper.of(context).title.copyWith(fontSize: 21)),
        note('包含两套标签与关联、目录映射、回收站、预览轮次、图包进度和阅读偏好。不包含媒体文件、个人口令与本机外观偏好。'),
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
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('archive-export'),
          onPressed: disabled
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
          child: const Text('导出备份'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('archive-pick'),
          onPressed: disabled
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
          child: const Text('选择备份文件'),
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
        note(
          '文件上限 ${maximum >= 1024 * 1024 ? '${maximum ~/ (1024 * 1024)} MiB' : '${maximum ~/ 1024} KiB'}。先校验，再核对目录映射；恢复前保留当前管理数据快照。已永久删除的源文件不会从备份恢复。',
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
          const Divider(height: 32),
          ListTile(
            key: const Key('archive-restore-point'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: const Text('恢复前的快照'),
            subtitle: const Text('查看并恢复上一次替换前的管理数据'),
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
          child: const Text('查看后台操作结果与恢复前快照'),
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
  });
  final LibraryRepository repository;
  final ManagementArchiveRepository archives;
  final ArchivePreview preview;
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
    }
  }

  @override
  void dispose() {
    read++;
    widget.repository.removeListener(changed);
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
    return Scaffold(
      appBar: AppBar(title: Text('恢复备份', style: Paper.of(context).title)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            note(
              widget.preview.protocol == 1
                  ? '这是旧协议的原预览，仅供查看。请返回重新选择原文件，完成新版校验后再恢复。'
                  : '校验通过。恢复会替换现有管理数据，请核对目录映射；留空表示暂不启用该目录。',
            ),
            Text(
              '视频 ${counts['videos'] ?? 0} · 视频标签 ${counts['tags'] ?? 0}\n图包 ${counts['packs'] ?? 0} · 图片 ${counts['pack_pages'] ?? 0} · 图包标签 ${counts['pack_tag_definitions'] ?? 0}\n回收记录 ${(counts['trash_items'] ?? 0) + (counts['pack_trash_items'] ?? 0)} · 阅读记录 ${counts['pack_progress'] ?? 0}',
              key: const Key('archive-counts'),
              style: const TextStyle(height: 1.7),
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
                child: TextField(
                  key: Key('archive-mapping-${root.id}'),
                  controller: fields[root.id],
                  enabled: editable,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    labelText:
                        '${root.name} · ${root.kind == MediaKind.video ? '视频' : '图包'}',
                    helperText:
                        '原目录：${root.path}${root.enabled ? '' : '\n原备份中已停用'}',
                    helperMaxLines: 5,
                    hintText: '留空表示暂不启用',
                  ),
                ),
              ),
            if (widget.preview.rootsTotal > 24)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: editable && !loading && offset > 0
                          ? () => load(offset - 24)
                          : null,
                      child: const Text('上一页'),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '${offset ~/ 24 + 1} / ${(widget.preview.rootsTotal + 23) ~/ 24}',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          editable &&
                              !loading &&
                              offset + 24 < widget.preview.rootsTotal
                          ? () => load(offset + 24)
                          : null,
                      child: const Text('下一页'),
                    ),
                  ],
                ),
              ),
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
            if (!complete && !loading) note('请查看剩余目录并核对映射，再确认恢复。'),
            CheckboxListTile(
              key: const Key('archive-confirm'),
              contentPadding: EdgeInsets.zero,
              value: checked,
              onChanged: editable && complete && !loading
                  ? (value) => setState(() => checked = value!)
                  : null,
              title: const Text(
                '我知道恢复会替换现有管理数据',
                style: TextStyle(fontSize: 13),
              ),
            ),
            note('恢复不会回滚磁盘文件删除，也不修改连接口令、本机暗黑模式和相邻视频准备。'),
            FilledButton(
              key: const Key('archive-restore-submit'),
              onPressed: editable && checked && complete && !loading
                  ? restore
                  : null,
              child: Text(restoring ? '正在恢复…' : '确认恢复'),
            ),
            if (pending) note('原恢复已提交。可关闭此页，在备份或操作任务查询结果；不会再次提交恢复。'),
            TextButton(
              key: const Key('archive-restore-close'),
              onPressed: () => Navigator.pop(context),
              child: Text(restoring || pending ? '关闭' : '取消'),
            ),
          ],
        ),
      ),
    );
  }
}
