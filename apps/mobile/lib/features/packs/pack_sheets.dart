import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';
import '../../ui/media_tag_editor.dart';
import '../../ui/media_layout.dart';

class PackFolderPicker extends StatefulWidget {
  const PackFolderPicker({
    super.key,
    required this.repository,
    required this.initial,
  });
  final LibraryRepository repository;
  final String initial;
  @override
  State<PackFolderPicker> createState() => _PackFolderPickerState();
}

class _PackFolderPickerState extends State<PackFolderPicker> {
  late String cursor = widget.initial;
  List<FolderEntry> items = [];
  int total = 0, generation = 0;
  bool loading = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    final current = ++generation;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final page = await widget.repository.loadPackDirectories(
        cursor,
        offset: more ? items.length : 0,
      );
      if (!mounted || current != generation) return;
      setState(() {
        items = more ? [...items, ...page.items] : page.items;
        total = page.total;
      });
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  void navigate(String value) {
    cursor = value;
    items = [];
    unawaited(load());
  }

  @override
  void dispose() {
    generation++;
    widget.repository.cancelPackDirectoryRead();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: '图包目录',
    children: [
      note(cursor.isEmpty ? '选择图包根目录，范围包含下级目录。' : cursor),
      TextButton(onPressed: () => navigate(''), child: const Text('媒体目录')),
      if (cursor.isNotEmpty)
        TextButton(
          onPressed: () => navigate(
            cursor.substring(0, cursor.lastIndexOf('/')).isEmpty
                ? ''
                : cursor.substring(0, cursor.lastIndexOf('/')),
          ),
          child: const Text('上一级'),
        ),
      for (final item in items)
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(item.name),
          subtitle: item.available ? null : const Text('目录暂不可用'),
          enabled: !loading && item.available,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => navigate(item.path),
        ),
      if (loading) const PaperLinearProgressIndicator(),
      if (error.isNotEmpty) ...[
        note(error),
        TextButton(onPressed: () => load(), child: const Text('重试')),
      ],
      if (!loading && error.isEmpty && items.length < total)
        TextButton(
          onPressed: () => load(more: true),
          child: const Text('继续加载目录'),
        ),
      FilledButton(
        onPressed: loading || error.isNotEmpty
            ? null
            : () => Navigator.pop(context, cursor),
        child: Text(cursor.isEmpty ? '使用全部目录' : '使用此目录'),
      ),
    ],
  );
}

class PackTagEditor extends StatelessWidget {
  const PackTagEditor({
    super.key,
    required this.repository,
    required this.ids,
    this.initial = const {},
    this.initialNames = const {},
    this.selectionOnly = false,
    this.appendOnly = false,
  });
  final LibraryRepository repository;
  final Set<String> ids, initial;
  final Map<String, String> initialNames;
  final bool selectionOnly, appendOnly;
  @override
  Widget build(BuildContext context) => MediaTagEditor(
    repository: repository,
    kind: MediaKind.pack,
    ids: ids,
    initial: initial,
    initialNames: initialNames,
    selectionOnly: selectionOnly,
    appendOnly: appendOnly,
    onSaved: (names) => Navigator.pop(
      context,
      selectionOnly ? names.keys.toSet() : PackTagNames(names: names),
    ),
  );
}

class PackFilterSheet extends StatefulWidget {
  const PackFilterSheet({
    super.key,
    required this.repository,
    required this.initial,
  });
  final LibraryRepository repository;
  final PackQuery initial;
  @override
  State<PackFilterSheet> createState() => _PackFilterSheetState();
}

class _PackFilterSheetState extends State<PackFilterSheet> {
  late PackQuery draft = widget.initial;
  late final owner = widget.repository.connectionIdentity;
  List<PackTag> choices = [];
  @override
  void initState() {
    super.initState();
    unawaited(loadChoices());
  }

  Future<void> loadChoices() async {
    try {
      final page = await widget.repository.loadPackTags();
      if (mounted && identical(owner, widget.repository.connectionIdentity)) {
        setState(() => choices = page.items.take(6).toList());
      }
    } catch (_) {
      // The searchable picker remains available if this bounded preview fails.
    }
  }

  @override
  void dispose() {
    widget.repository.cancelPackTagRead();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: '图包筛选',
    footer: Row(
      children: [
        TextButton(
          onPressed: () => setState(
            () => draft = PackQuery(search: draft.search, sort: draft.sort),
          ),
          child: const Text('重置'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context, draft),
          child: const Text('应用筛选'),
        ),
      ],
    ),
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('目录'),
        subtitle: Text(draft.folder.isEmpty ? '全部图包目录' : draft.folder),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final path = await paperSheet<String>(
            context,
            PackFolderPicker(
              repository: widget.repository,
              initial: draft.folder,
            ),
          );
          if (mounted && path != null) {
            setState(() => draft = draft.copy(folder: path));
          }
        },
      ),
      const SizedBox(height: 8),
      const Text('阅读状态'),
      Wrap(
        spacing: 8,
        children: [
          for (final state in PackReadState.values)
            TextButton(
              key: ValueKey('pack-read-state-${state.name}'),
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 48),
                shape: const RoundedRectangleBorder(),
                side: BorderSide.none,
              ),
              onPressed: () =>
                  setState(() => draft = draft.copy(readState: state)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: draft.readState == state
                          ? Paper.of(context).olive
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(switch (state) {
                  PackReadState.all => '全部',
                  PackReadState.unread => '未读',
                  PackReadState.reading => '在读',
                  PackReadState.completed => '已读',
                }),
              ),
            ),
        ],
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('标签 · 同时满足'),
        subtitle: Text('已选 ${draft.tags.length} 个标签'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final tags = await paperSheet<Set<String>>(
            context,
            PackTagEditor(
              repository: widget.repository,
              ids: const {},
              initial: draft.tags,
              selectionOnly: true,
            ),
          );
          if (mounted && tags != null) {
            setState(() => draft = draft.copy(tags: tags));
          }
        },
      ),
      MediaTagChoices(
        children: [
          for (final tag in choices)
            MediaTagChoice(
              label: tag.name,
              selected: draft.tags.contains(tag.id),
              onSelected: (yes) => setState(() {
                final tags = {...draft.tags};
                yes ? tags.add(tag.id) : tags.remove(tag.id);
                draft = draft.copy(tags: tags);
              }),
            ),
        ],
      ),
    ],
  );
}
