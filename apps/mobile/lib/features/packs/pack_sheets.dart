import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';

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
      if (loading) const LinearProgressIndicator(),
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

class PackTagEditor extends StatefulWidget {
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
  final bool selectionOnly;
  final bool appendOnly;
  @override
  State<PackTagEditor> createState() => _PackTagEditorState();
}

class _PackTagEditorState extends State<PackTagEditor> {
  final input = TextEditingController();
  late final chosen =
      widget.selectionOnly || (widget.ids.length == 1 && !widget.appendOnly)
      ? {...widget.initial}
      : <String>{};
  late final names = <String, String>{...widget.initialNames};
  late final unverified = {...chosen};
  final missing = <String>{}, nameVersions = <String, int>{};
  late final owner = widget.repository.connectionIdentity;
  List<PackTag> items = [];
  int total = 0, generation = 0, namesGeneration = 0, nameOrder = 0;
  bool loading = false,
      saving = false,
      namesLoading = false,
      connectionChanged = false;
  bool retryMore = false;
  String? loadedSearch;
  String error = '', namesError = '';
  bool get validConnection =>
      identical(owner, widget.repository.connectionIdentity);
  bool get unresolved => chosen.any(unverified.contains);
  bool get removed => chosen.any(missing.contains);
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(repositoryChanged);
    unawaited(load());
    if (chosen.isNotEmpty) unawaited(resolveNames());
  }

  void repositoryChanged() {
    if (validConnection || connectionChanged) return;
    generation++;
    namesGeneration++;
    widget.repository.cancelPackTagRead();
    widget.repository.cancelPackTagNamesRead();
    setState(() {
      connectionChanged = true;
      loading = namesLoading = false;
      items = [];
      names.clear();
      error = '服务连接已变化，请关闭后重新打开。';
    });
  }

  void acceptNames(
    Map<String, String> found,
    Iterable<String> absent,
    int version,
  ) {
    for (final id in {...found.keys, ...absent}) {
      if (version < (nameVersions[id] ?? 0)) continue;
      nameVersions[id] = version;
      unverified.remove(id);
      if (found.containsKey(id)) {
        names[id] = found[id]!;
        missing.remove(id);
      } else {
        names.remove(id);
        missing.add(id);
      }
    }
  }

  Future<void> resolveNames() async {
    if (!validConnection) return;
    final current = ++namesGeneration, version = ++nameOrder;
    setState(() {
      namesLoading = true;
      namesError = '';
    });
    try {
      final result = await widget.repository.resolvePackTags({...chosen});
      if (!mounted || current != namesGeneration || !validConnection) return;
      setState(() => acceptNames(result.names, result.missing, version));
    } on RequestCancelled {
      // The connection owner or a newer resolution cancelled this read.
    } catch (failure) {
      if (mounted && current == namesGeneration && validConnection) {
        setState(() => namesError = '标签名称未更新，原选择已保留：$failure');
      }
    } finally {
      if (mounted && current == namesGeneration) {
        setState(() => namesLoading = false);
      }
    }
  }

  Future<void> load({bool more = false}) async {
    if (!validConnection || (more && loading)) return;
    final current = ++generation, version = ++nameOrder;
    final search = input.text;
    final append = more && search == loadedSearch;
    final offset = append ? items.length : 0;
    var restartRequired = false;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final page = await widget.repository.loadPackTags(
        search: search,
        offset: offset,
      );
      if (!mounted || current != generation || !validConnection) return;
      final ids = page.items.map((tag) => tag.id).toSet();
      if (page.offset != offset ||
          page.total < offset + page.items.length ||
          (page.items.isEmpty && offset < page.total) ||
          ids.length != page.items.length ||
          (append &&
              (page.total != total ||
                  items.any((tag) => ids.contains(tag.id))))) {
        restartRequired = true;
        throw const LibraryFailure('标签列表已变化，请重新加载');
      }
      setState(() {
        items = append ? [...items, ...page.items] : page.items;
        total = page.total;
        loadedSearch = search;
        retryMore = false;
        acceptNames(
          {for (final tag in page.items) tag.id: tag.name},
          const [],
          version,
        );
      });
    } on RequestCancelled {
      // Preserve the prior list and draft on cancellation.
    } catch (failure) {
      if (mounted && current == generation && validConnection) {
        setState(() {
          error = failure.toString();
          retryMore = append && !restartRequired;
        });
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    if (saving || input.text.trim().isEmpty || !validConnection) return;
    setState(() {
      saving = true;
      error = '';
    });
    try {
      final tag = await widget.repository.createPackTag(input.text);
      if (!mounted || !validConnection) return;
      setState(() {
        acceptNames({tag.id: tag.name}, const [], ++nameOrder);
        chosen.add(tag.id);
        input.clear();
      });
      await load();
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> save() async {
    if (!validConnection || unresolved || removed) return;
    setState(() {
      saving = true;
      error = '';
    });
    try {
      if (widget.selectionOnly) {
        Navigator.pop(context, {...chosen});
        return;
      }
      await widget.repository.setPackTags(
        widget.ids,
        chosen,
        replace: widget.ids.length == 1 && !widget.appendOnly,
      );
      if (mounted) {
        Navigator.pop(
          context,
          PackTagNames(names: {for (final id in chosen) id: names[id]!}),
        );
      }
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    generation++;
    namesGeneration++;
    widget.repository.removeListener(repositoryChanged);
    widget.repository.cancelPackTagRead();
    widget.repository.cancelPackTagNamesRead();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: widget.selectionOnly
        ? '选择图包标签'
        : widget.ids.length == 1 && !widget.appendOnly
        ? '图包标签'
        : '图包标签 · 批量追加',
    closeEnabled: !saving,
    children: [
      note(
        widget.selectionOnly
            ? '只查看同时包含所选标签的图包。'
            : widget.ids.length == 1 && !widget.appendOnly
            ? '标签应用于整个图包。'
            : '将标签追加到 ${widget.ids.length} 个图包，保留原有标签。',
      ),
      if (chosen.isNotEmpty)
        Wrap(
          spacing: 8,
          children: [
            for (final id in chosen)
              InputChip(
                key: Key('chosen-pack-tag-$id'),
                label: Text(
                  missing.contains(id) ? '已移除的标签' : names[id] ?? '名称待确认',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: saving || connectionChanged
                    ? null
                    : () => setState(() => chosen.remove(id)),
              ),
          ],
        ),
      TextField(
        controller: input,
        enabled: !saving && !connectionChanged,
        decoration: InputDecoration(
          labelText: widget.selectionOnly ? '搜索图包标签' : '搜索或新建图包标签',
        ),
        onChanged: (_) => load(),
        onSubmitted: widget.selectionOnly ? null : (_) => create(),
      ),
      if (!widget.selectionOnly &&
          input.text.trim().isNotEmpty &&
          !items.any((tag) => tag.name == input.text.trim()))
        TextButton(
          onPressed: saving || connectionChanged ? null : create,
          child: Text('新建「${input.text.trim()}」'),
        ),
      if (loading || namesLoading) const LinearProgressIndicator(),
      if (removed) note('部分已选标签已被移除，请取消这些选择后再保存。'),
      if (unresolved && namesError.isNotEmpty) ...[
        note(namesError),
        TextButton(
          onPressed: namesLoading || connectionChanged ? null : resolveNames,
          child: const Text('重试读取名称'),
        ),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final tag in items)
            FilterChip(
              label: Text(tag.name),
              selected: chosen.contains(tag.id),
              onSelected: saving || connectionChanged
                  ? null
                  : (value) => setState(() {
                      value ? chosen.add(tag.id) : chosen.remove(tag.id);
                    }),
            ),
        ],
      ),
      if (!loading &&
          error.isEmpty &&
          loadedSearch == input.text &&
          items.length < total)
        TextButton(
          onPressed: () => load(more: true),
          child: const Text('更多标签'),
        ),
      if (error.isNotEmpty) note(error),
      if (error.isNotEmpty && !saving && !connectionChanged)
        TextButton(
          onPressed: () => load(more: retryMore),
          child: const Text('重试读取标签'),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: saving || connectionChanged || unresolved || removed
            ? null
            : save,
        child: Text(
          saving
              ? '正在保存…'
              : widget.selectionOnly
              ? '使用所选标签'
              : widget.ids.length == 1 && !widget.appendOnly
              ? '保存整包标签'
              : '追加所选标签',
        ),
      ),
    ],
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
  @override
  Widget build(BuildContext context) => SheetFrame(
    title: '图包筛选',
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
      DropdownButtonFormField<PackReadState>(
        initialValue: draft.readState,
        key: ValueKey(draft.readState),
        decoration: const InputDecoration(labelText: '阅读状态'),
        items: const [
          DropdownMenuItem(value: PackReadState.all, child: Text('全部')),
          DropdownMenuItem(value: PackReadState.unread, child: Text('未读')),
          DropdownMenuItem(value: PackReadState.reading, child: Text('在读')),
          DropdownMenuItem(value: PackReadState.completed, child: Text('已读')),
        ],
        onChanged: (value) =>
            setState(() => draft = draft.copy(readState: value)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('标签'),
        subtitle: Text('已选 ${draft.tags.length} 个条件 · 同时满足'),
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
      if (draft.tags.isNotEmpty) Text('已选 ${draft.tags.length} 个图包标签'),
      Row(
        children: [
          TextButton(
            onPressed: () => setState(
              () => draft = PackQuery(search: draft.search, sort: draft.sort),
            ),
            child: const Text('重置'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('应用筛选'),
          ),
        ],
      ),
    ],
  );
}
