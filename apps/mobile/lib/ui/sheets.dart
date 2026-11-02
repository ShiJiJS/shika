import 'dart:async';

import 'package:flutter/material.dart';

import '../library/models.dart';
import '../library/repository.dart';
import 'paper.dart';
import 'media_tag_editor.dart';

class FolderPicker extends StatefulWidget {
  const FolderPicker({
    super.key,
    required this.repository,
    required this.initial,
  });
  final LibraryRepository repository;
  final String initial;
  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  late String cursor = widget.initial;
  List<FolderEntry> children = [];
  bool loading = true;
  String error = '';
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(load(initial: true));
  }

  Future<void> load({bool initial = false}) async {
    final current = ++generation;
    if (!initial) {
      setState(() {
        loading = true;
        children = [];
        error = '';
      });
    }
    try {
      final result = await widget.repository.loadFolders(cursor);
      if (mounted && current == generation) setState(() => children = result);
    } on RequestCancelled {
      // A newer directory selection owns the visible result.
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  void navigate(String path) {
    cursor = path;
    unawaited(load());
  }

  @override
  void dispose() {
    generation++;
    widget.repository.cancelFolderRead();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.repository.snapshot.roots
        .where((r) => under(cursor, r.path))
        .firstOrNull;
    final paths = <String>[];
    if (root != null) {
      paths.add(root.path);
      var p = root.path;
      for (final part
          in cursor
              .substring(root.path.length)
              .split('/')
              .where((p) => p.isNotEmpty)) {
        p = '$p/$part';
        paths.add(p);
      }
    }
    return SheetFrame(
      title: '选择文件夹',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton(
                onPressed: () => navigate(''),
                child: const Text('媒体目录'),
              ),
              ...paths.expand(
                (p) => [
                  const Icon(Icons.chevron_right, size: 16),
                  TextButton(
                    onPressed: () => navigate(p),
                    child: Text(p == root?.path ? root!.name : basename(p)),
                  ),
                ],
              ),
            ],
          ),
        ),
        note(cursor.isEmpty ? '全部媒体目录' : cursor),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (error.isNotEmpty) ...[
          note(error),
          TextButton(onPressed: () => load(), child: const Text('重试')),
        ],
        ...children.map(
          (f) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(f.name),
            subtitle: Text(
              f.available
                  ? f.videoCount == null
                        ? '包含下级目录'
                        : '${f.videoCount} 个视频'
                  : '目录暂不可用',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: f.available,
            onTap: () => navigate(f.path),
          ),
        ),
        if (!loading && error.isEmpty && children.isEmpty)
          note('已经到最下一级，可使用当前目录。'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed:
              loading || error.isNotEmpty || (root != null && !root.available)
              ? null
              : () => Navigator.pop(context, cursor),
          child: Text(cursor.isEmpty ? '使用全部目录' : '使用此目录'),
        ),
        note('范围包含所选文件夹的下级目录。'),
      ],
    );
  }
}

class ScopeSheet extends StatefulWidget {
  const ScopeSheet({
    super.key,
    required this.repository,
    this.review = false,
    this.initial,
  });
  final LibraryRepository repository;
  final bool review;
  final VideoQuery? initial;
  @override
  State<ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<ScopeSheet> {
  late VideoQuery draft = widget.initial ?? widget.repository.snapshot.query;
  Widget select(
    String label,
    String value,
    Map<String, String> options,
    void Function(String) changed,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: PaperDropdownButtonFormField<String>(
      initialValue: value,
      key: ValueKey('$label-$value'),
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) => setState(() => changed(v ?? '')),
    ),
  );
  @override
  Widget build(BuildContext context) => SheetFrame(
    title: widget.review ? '筛选整理范围' : '筛选视频',
    children: [
      note('只查看同时满足条件的视频。'),
      Container(
        color: Paper.of(context).soft,
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                draft.folder.isEmpty ? '全部媒体目录' : draft.folder,
                style: TextStyle(fontSize: 12, color: Paper.of(context).olive),
              ),
            ),
            TextButton(
              onPressed: () async {
                final folder = await paperSheet<String>(
                  context,
                  FolderPicker(
                    repository: widget.repository,
                    initial: draft.folder,
                  ),
                );
                if (folder != null && mounted) {
                  setState(() => draft = draft.copy(folder: folder));
                }
              },
              child: const Text('更换目录'),
            ),
          ],
        ),
      ),
      note('标签 · 同时满足'),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: widget.repository.snapshot.tags
            .map(
              (tag) => PaperFilterChip(
                label: Text(widget.repository.tagName(tag)),
                selected: draft.tags.contains(tag),
                backgroundColor: Paper.of(context).soft,
                side: BorderSide.none,
                onSelected: (yes) => setState(() {
                  final tags = {...draft.tags};
                  yes ? tags.add(tag) : tags.remove(tag);
                  draft = draft.copy(tags: tags);
                }),
              ),
            )
            .toList(),
      ),
      select('画面方向', draft.orientation, const {
        '': '全部方向',
        'portrait': '竖版',
        'landscape': '横版',
      }, (v) => draft = draft.copy(orientation: v)),
      select('时长', draft.duration, const {
        '': '全部时长',
        'short': '10 秒以内',
        'long': '10 秒以上',
      }, (v) => draft = draft.copy(duration: v)),
      select('文件类型', draft.type, const {
        '': '全部类型',
        'MP4': 'MP4',
        'MOV': 'MOV',
        'MKV': 'MKV',
        'WEBM': 'WebM',
        'AVI': 'AVI',
        'M4V': 'M4V',
        'TS': 'TS',
        'MTS': 'MTS',
        'M2TS': 'M2TS',
        'MPG': 'MPG',
        'MPEG': 'MPEG',
        '3GP': '3GP',
      }, (v) => draft = draft.copy(type: v)),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => setState(() => draft = VideoQuery()),
            child: const Text('清除条件'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('应用筛选'),
          ),
        ],
      ),
    ],
  );
}

class TagEditor extends StatelessWidget {
  const TagEditor({
    super.key,
    required this.repository,
    required this.ids,
    this.initial,
    this.appendOnly = false,
  });
  final LibraryRepository repository;
  final Set<String> ids;
  final Set<String>? initial;
  final bool appendOnly;
  @override
  Widget build(BuildContext context) {
    final matches = repository.snapshot.videos.where((v) => ids.contains(v.id));
    final single = ids.length == 1 && !appendOnly;
    final tags =
        initial ?? (matches.length == 1 ? matches.single.tags : <String>{});
    return MediaTagEditor(
      repository: repository,
      kind: MediaKind.video,
      ids: ids,
      initial: tags,
      initialNames: {for (final id in tags) id: repository.tagName(id)},
      initialKnown: !single || initial != null || matches.length == 1,
      appendOnly: appendOnly,
      allowRemoval: ids.length > 1 && !appendOnly,
      onSaved: (_) => Navigator.pop(context, true),
    );
  }
}
