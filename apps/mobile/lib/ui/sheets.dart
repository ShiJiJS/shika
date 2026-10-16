import 'package:flutter/material.dart';

import '../library/models.dart';
import '../library/repository.dart';
import 'paper.dart';

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
    final children = widget.repository.folders(cursor);
    return SheetFrame(
      title: '选择文件夹',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => cursor = ''),
                child: const Text('媒体目录'),
              ),
              ...paths.expand(
                (p) => [
                  const Icon(Icons.chevron_right, size: 16),
                  TextButton(
                    onPressed: () => setState(() => cursor = p),
                    child: Text(p == root?.path ? root!.name : basename(p)),
                  ),
                ],
              ),
            ],
          ),
        ),
        note(cursor.isEmpty ? '全部媒体目录' : cursor),
        ...children.map(
          (f) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(f.name),
            subtitle: Text(
              f.available
                  ? '${widget.repository.query(scope: VideoQuery(folder: f.path)).length} 个视频'
                  : '目录暂不可用',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: f.available,
            onTap: () => setState(() => cursor = f.path),
          ),
        ),
        if (children.isEmpty) note('已经到最下一级，可使用当前目录。'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: root != null && !root.available
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
  const ScopeSheet({super.key, required this.repository, this.review = false});
  final LibraryRepository repository;
  final bool review;
  @override
  State<ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<ScopeSheet> {
  late VideoQuery draft = widget.repository.snapshot.query;
  Widget select(
    String label,
    String value,
    Map<String, String> options,
    void Function(String) changed,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: DropdownButtonFormField<String>(
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
        color: Paper.soft,
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                draft.folder.isEmpty ? '全部媒体目录' : draft.folder,
                style: const TextStyle(fontSize: 12, color: Paper.olive),
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
              (tag) => FilterChip(
                label: Text(tag),
                selected: draft.tags.contains(tag),
                backgroundColor: Paper.soft,
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

class TagEditor extends StatefulWidget {
  const TagEditor({super.key, required this.repository, required this.ids});
  final LibraryRepository repository;
  final Set<String> ids;
  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  late Set<String> selected = widget.ids.length == 1
      ? {
          ...widget.repository.snapshot.videos
              .firstWhere((v) => v.id == widget.ids.first)
              .tags,
        }
      : {};
  String search = '', error = '';
  bool remove = false, busy = false;
  @override
  Widget build(BuildContext context) => SheetFrame(
    title: '打标签',
    children: [
      note(
        widget.ids.length == 1
            ? '编辑当前视频的标签'
            : '将修改 ${widget.ids.length} 个视频，其他标签保持不变',
      ),
      if (widget.ids.length > 1)
        Row(
          children: [
            ChoiceChip(
              label: const Text('添加标签'),
              selected: !remove,
              onSelected: (_) => setState(() => remove = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('移除标签'),
              selected: remove,
              onSelected: (_) => setState(() => remove = true),
            ),
          ],
        ),
      TextField(
        decoration: const InputDecoration(
          hintText: '搜索标签',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: widget.repository.snapshot.tags
            .where((t) => t.contains(search))
            .map(
              (tag) => FilterChip(
                label: Text(tag),
                selected: selected.contains(tag),
                backgroundColor: Paper.soft,
                side: BorderSide.none,
                onSelected: busy
                    ? null
                    : (yes) => setState(
                        () => yes ? selected.add(tag) : selected.remove(tag),
                      ),
              ),
            )
            .toList(),
      ),
      if (error.isNotEmpty) note(error),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() {
                  busy = true;
                  error = '';
                });
                try {
                  await widget.repository.setVideoTags(
                    widget.ids,
                    selected,
                    remove: remove,
                    replace: widget.ids.length == 1,
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(busy ? '保存中…' : '完成'),
      ),
    ],
  );
}
