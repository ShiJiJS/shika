import 'dart:async';

import 'package:flutter/material.dart';

import '../library/models.dart';
import '../library/repository.dart';
import 'paper.dart';
import 'paper_form.dart';

/// One assignment workflow; every repository operation stays in its namespace.
/// The public video/pack wrappers retain their existing typed route results.
class MediaTagEditor extends StatefulWidget {
  const MediaTagEditor({
    super.key,
    required this.repository,
    required this.kind,
    required this.ids,
    required this.onSaved,
    this.initial = const {},
    this.initialNames = const {},
    this.initialKnown = true,
    this.selectionOnly = false,
    this.appendOnly = false,
    this.allowRemoval = false,
  });
  final LibraryRepository repository;
  final MediaKind kind;
  final Set<String> ids, initial;
  final Map<String, String> initialNames;
  final bool initialKnown, selectionOnly, appendOnly, allowRemoval;
  final ValueChanged<Map<String, String>> onSaved;
  @override
  State<MediaTagEditor> createState() => _MediaTagEditorState();
}

class _TagChoice {
  const _TagChoice(this.id, this.name);
  final String id, name;
}

class _MediaTagEditorState extends State<MediaTagEditor> {
  final search = TextEditingController(), newName = TextEditingController();
  final errorAnchor = GlobalKey();
  late final targets = Set<String>.unmodifiable(widget.ids);
  late final chosen = widget.selectionOnly || single
      ? {...widget.initial}
      : <String>{};
  late final names = <String, String>{...widget.initialNames};
  late final unverified = {...chosen};
  final missing = <String>{}, nameVersions = <String, int>{};
  late final owner = repo.connectionIdentity;
  List<_TagChoice> items = [];
  int total = 0, generation = 0, namesGeneration = 0, nameOrder = 0;
  bool loading = false,
      saving = false,
      namesLoading = false,
      connectionChanged = false,
      retryMore = false,
      remove = false;
  String? loadedSearch;
  String error = '', readError = '', namesError = '';
  LibraryRepository get repo => widget.repository;
  bool get pack => widget.kind == MediaKind.pack;
  String get type => pack ? '图包' : '视频';
  bool get single => targets.length == 1 && !widget.appendOnly;
  bool get validConnection => identical(owner, repo.connectionIdentity);
  bool get writable => validConnection && !repo.backupRestorePending;
  bool get unresolved => chosen.any(unverified.contains);
  bool get removed => chosen.any(missing.contains);
  @override
  void initState() {
    super.initState();
    repo.addListener(repositoryChanged);
    unawaited(load());
    if (chosen.isNotEmpty) unawaited(resolveNames());
  }

  void cancelReads() {
    if (pack) {
      repo.cancelPackTagRead();
      repo.cancelPackTagNamesRead();
    } else {
      repo.cancelVideoTagRead();
    }
  }

  void repositoryChanged() {
    if (!mounted) return;
    if (!validConnection && !connectionChanged) {
      generation++;
      namesGeneration++;
      cancelReads();
      setState(() {
        connectionChanged = true;
        loading = namesLoading = false;
        items = [];
        names.clear();
        error = '服务连接已变化，请关闭后重新打开。';
      });
    } else {
      // The video snapshot contains all tag definitions, including off-page IDs.
      // Pack names require the independent ID-resolution read below.
      setState(() {
        if (!pack && validConnection) acceptVideoNames(++nameOrder);
      });
    }
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

  void acceptVideoNames(int version) {
    final ids = repo.snapshot.tags.toSet();
    acceptNames(
      {for (final id in ids) id: repo.tagName(id)},
      chosen.where((id) => !ids.contains(id)),
      version,
    );
  }

  Future<void> resolveNames() async {
    if (!validConnection) return;
    final current = ++namesGeneration, version = ++nameOrder;
    setState(() {
      namesLoading = true;
      namesError = '';
    });
    try {
      if (pack) {
        final result = await repo.resolvePackTags({...chosen});
        if (!mounted || current != namesGeneration || !validConnection) return;
        setState(() => acceptNames(result.names, result.missing, version));
      } else {
        setState(() => acceptVideoNames(version));
      }
    } on RequestCancelled {
      // A newer owner or resolution cancelled this read; keep the draft.
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
    final query = search.text, append = more && search.text == loadedSearch;
    final offset = append ? items.length : 0;
    var restartRequired = false;
    setState(() {
      loading = true;
      readError = '';
    });
    try {
      final List<_TagChoice> pageItems;
      final int pageOffset, pageTotal;
      if (pack) {
        final page = await repo.loadPackTags(search: query, offset: offset);
        pageItems = page.items.map((t) => _TagChoice(t.id, t.name)).toList();
        pageOffset = page.offset;
        pageTotal = page.total;
      } else {
        final page = await repo.loadVideoTags(search: query, offset: offset);
        pageItems = page.items.map((t) => _TagChoice(t.id, t.name)).toList();
        pageOffset = page.offset;
        pageTotal = page.total;
      }
      if (!mounted || current != generation || !validConnection) return;
      final ids = pageItems.map((tag) => tag.id).toSet();
      if (pageOffset != offset ||
          pageTotal < offset + pageItems.length ||
          (pageItems.isEmpty && offset < pageTotal) ||
          ids.length != pageItems.length ||
          (append &&
              (pageTotal != total ||
                  items.any((tag) => ids.contains(tag.id))))) {
        restartRequired = true;
        throw const LibraryFailure('标签列表已变化，请重新加载');
      }
      setState(() {
        items = append ? [...items, ...pageItems] : pageItems;
        total = pageTotal;
        loadedSearch = query;
        retryMore = false;
        acceptNames(
          {for (final t in pageItems) t.id: t.name},
          const [],
          version,
        );
      });
    } on RequestCancelled {
      // Preserve the prior list and selection on cancellation.
    } catch (failure) {
      if (mounted && current == generation && validConnection) {
        setState(() {
          readError = failure.toString();
          retryMore = append && !restartRequired;
        });
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  void showError(String message) {
    if (!mounted) return;
    setState(() => error = message);
    revealFormError(errorAnchor);
  }

  Future<bool> addDraft() async {
    final name = newName.text.trim();
    if (name.isEmpty) return true;
    if (name.runes.length > 100) {
      showError('请输入1至100字的标签名称');
      return false;
    }
    if (chosen.length >= 256) {
      showError('最多选择256个标签');
      return false;
    }
    String id;
    if (pack) {
      final tag = await repo.createPackTag(name);
      id = tag.id;
    } else {
      // editTag synchronizes the complete video definition cache before return.
      await repo.editTag(name: name);
      if (!mounted || !writable) return false;
      final matches = repo.snapshot.tags
          .where((id) => repo.tagName(id) == name)
          .toList();
      if (matches.length != 1) {
        throw const LibraryFailure('标签已提交，但名称尚未确认，请重新读取标签');
      }
      id = matches.single;
    }
    if (!mounted || !writable) return false;
    setState(() {
      acceptNames({id: name}, const [], ++nameOrder);
      chosen.add(id);
      newName.clear();
    });
    return true;
  }

  Future<void> create() async {
    if (saving ||
        !writable ||
        newName.text.trim().isEmpty ||
        widget.selectionOnly) {
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      if (await addDraft()) await load();
    } catch (failure) {
      if (validConnection) showError(failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> save() async {
    if (saving ||
        !writable ||
        unresolved ||
        removed ||
        !widget.initialKnown ||
        (!widget.selectionOnly && targets.isEmpty)) {
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      if (!widget.selectionOnly && !await addDraft()) return;
      if (!mounted || !writable) return;
      if (!widget.selectionOnly) {
        if (pack) {
          await repo.setPackTags(targets, {...chosen}, replace: single);
        } else {
          await repo.setVideoTags(
            targets,
            {...chosen},
            remove: remove,
            replace: single,
          );
        }
      }
      if (mounted && writable) {
        widget.onSaved({for (final id in chosen) id: names[id]!});
      }
    } catch (failure) {
      if (validConnection) showError(failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    generation++;
    namesGeneration++;
    repo.removeListener(repositoryChanged);
    cancelReads();
    search.dispose();
    newName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    final enabled = !saving && writable;
    return PopScope(
      canPop: !saving,
      child: SheetFrame(
        title: widget.selectionOnly
            ? '选择图包标签'
            : single
            ? (pack ? '整包标签' : '视频标签')
            : '批量标签',
        closeEnabled: !saving,
        footer: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('tag-assignment-save'),
              onPressed:
                  enabled &&
                      !unresolved &&
                      !removed &&
                      widget.initialKnown &&
                      (widget.selectionOnly || targets.isNotEmpty)
                  ? save
                  : null,
              child: Text(
                saving
                    ? '正在保存…'
                    : widget.selectionOnly
                    ? '使用所选标签'
                    : single
                    ? (pack ? '保存整包标签' : '保存视频标签')
                    : remove
                    ? '移除所选标签'
                    : '追加所选标签',
              ),
            ),
          ],
        ),
        children: [
          Text(
            widget.selectionOnly
                ? '只查看同时包含所选标签的图包。'
                : single
                ? (pack ? '标签应用于整个图包。' : '只修改这个视频的标签。')
                : remove
                ? '从 ${targets.length} 个视频移除所选标签，保留其他标签。'
                : '将标签追加到 ${targets.length} 个$type，保留原有标签。',
            style: TextStyle(fontSize: 13, height: 1.7, color: p.catalogMeta),
          ),
          if (!widget.initialKnown) note('当前视频未载入，请关闭后重新打开。'),
          if (widget.allowRemoval && !single)
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('添加标签'),
                  selected: !remove,
                  onSelected: enabled
                      ? (_) => setState(() => remove = false)
                      : null,
                ),
                ChoiceChip(
                  label: const Text('移除标签'),
                  selected: remove,
                  onSelected: enabled
                      ? (_) => setState(() => remove = true)
                      : null,
                ),
              ],
            ),
          if (chosen.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final id in chosen)
                  InputChip(
                    key: Key('chosen-${pack ? 'pack' : 'video'}-tag-$id'),
                    label: Text(
                      missing.contains(id) ? '已移除的标签' : names[id] ?? '名称待确认',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: enabled
                        ? () => setState(() => chosen.remove(id))
                        : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          PaperField(
            label: '搜索$type标签',
            child: TextField(
              key: const Key('tag-assignment-search'),
              controller: search,
              enabled: enabled,
              decoration: const InputDecoration(hintText: '输入标签名称'),
              onChanged: (_) => load(),
              textInputAction: TextInputAction.search,
            ),
          ),
          const SizedBox(height: 12),
          if (loading || namesLoading) const LinearProgressIndicator(),
          if (removed) note('部分已选标签已被移除，请取消这些选择后再保存。'),
          if (unresolved && namesError.isNotEmpty) ...[
            note(namesError),
            TextButton(
              onPressed: namesLoading || !enabled ? null : resolveNames,
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
                  onSelected: enabled
                      ? (value) {
                          if (value && chosen.length >= 256) {
                            showError('最多选择256个标签');
                            return;
                          }
                          setState(() {
                            value ? chosen.add(tag.id) : chosen.remove(tag.id);
                          });
                        }
                      : null,
                ),
            ],
          ),
          if (!loading && items.isEmpty && readError.isEmpty)
            note('没有匹配的$type标签'),
          if (!loading &&
              readError.isEmpty &&
              loadedSearch == search.text &&
              items.length < total)
            TextButton(
              onPressed: enabled ? () => load(more: true) : null,
              child: const Text('更多标签'),
            ),
          if (!widget.selectionOnly) ...[
            const SizedBox(height: 16),
            PaperField(
              label: '新增$type标签',
              child: TextField(
                key: const Key('tag-assignment-new'),
                controller: newName,
                enabled: enabled,
                maxLength: 100,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: '输入新标签名称'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => create(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('tag-assignment-add'),
                onPressed: enabled && newName.text.trim().isNotEmpty
                    ? create
                    : null,
                child: const Text('添加'),
              ),
            ),
          ],
          if (!writable && !connectionChanged) note('正在恢复管理数据，请完成后重新打开。'),
          if (error.isNotEmpty)
            Padding(
              key: errorAnchor,
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                key: const Key('tag-assignment-error'),
                style: TextStyle(fontSize: 13, height: 1.7, color: p.danger),
              ),
            ),
          if (readError.isNotEmpty)
            Text(
              readError,
              key: const Key('tag-assignment-read-error'),
              style: TextStyle(fontSize: 13, height: 1.7, color: p.danger),
            ),
          if (readError.isNotEmpty && enabled)
            TextButton(
              onPressed: () => load(more: retryMore),
              child: const Text('重试读取标签'),
            ),
        ],
      ),
    );
  }
}
