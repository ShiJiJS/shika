import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';
import '../../ui/paper_form.dart';

class TagCatalogItem {
  const TagCatalogItem(this.id, this.name, this.count);
  final String id, name;
  final int count;
}

class TagCatalogPage extends StatefulWidget {
  const TagCatalogPage({
    super.key,
    required this.repository,
    required this.kind,
    required this.active,
    required this.onView,
    this.onPreview,
    this.initial = const {},
  });
  final LibraryRepository repository;
  final MediaKind kind;
  final bool active;
  final Set<String> initial;
  final void Function(Set<String>) onView;
  final void Function(Set<String>)? onPreview;
  @override
  State<TagCatalogPage> createState() => TagCatalogPageState();
}

class TagCatalogPageState extends State<TagCatalogPage> {
  LibraryRepository get repo => widget.repository;
  bool get pack => widget.kind == MediaKind.pack;
  String get type => pack ? '图包' : '视频';
  final search = TextEditingController();
  late final selected = {...widget.initial};
  List<TagCatalogItem> tags = [];
  int total = 0, generation = 0, countGeneration = 0;
  int? matching;
  bool loading = false, saving = false, retryMore = false;
  String? loadedSearch;
  String error = '';
  @override
  void initState() {
    super.initState();
    repo.addListener(repositoryChanged);
    if (widget.active) scheduleLoad();
  }

  void scheduleLoad() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && widget.active) {
      unawaited(load());
      unawaited(count());
    }
  });
  @override
  void didUpdateWidget(TagCatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        scheduleLoad();
      } else {
        generation++;
        countGeneration++;
        if (pack) {
          repo.cancelPackTagRead();
          repo.cancelPackRead();
        } else {
          repo.cancelVideoTagRead();
          repo.cancelVideoRead();
        }
        loading = false;
      }
    }
  }

  void repositoryChanged() {
    if (widget.active && !saving) scheduleLoad();
  }

  Future<void> load({bool more = false}) async {
    if (!widget.active || (more && loading)) return;
    final current = ++generation;
    final text = search.text;
    final append = more && loadedSearch == text;
    final offset = append ? tags.length : 0;
    var restartRequired = false;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final List<TagCatalogItem> batch;
      final int count;
      final int pageOffset;
      if (pack) {
        final page = await repo.loadPackTags(search: text, offset: offset);
        pageOffset = page.offset;
        batch = page.items
            .map((tag) => TagCatalogItem(tag.id, tag.name, tag.count))
            .toList();
        count = page.total;
      } else {
        final page = await repo.loadVideoTags(search: text, offset: offset);
        pageOffset = page.offset;
        batch = page.items
            .map((tag) => TagCatalogItem(tag.id, tag.name, tag.count))
            .toList();
        count = page.total;
      }
      if (!mounted || current != generation) return;
      final ids = batch.map((tag) => tag.id).toSet();
      if (pageOffset != offset ||
          count < offset + batch.length ||
          (batch.isEmpty && offset < count) ||
          ids.length != batch.length ||
          (append &&
              (count != total || tags.any((tag) => ids.contains(tag.id))))) {
        restartRequired = true;
        throw const LibraryFailure('标签列表已变化，请重新加载');
      }
      setState(() {
        tags = append ? [...tags, ...batch] : batch;
        loadedSearch = text;
        retryMore = false;
        total = count;
        loading = false;
      });
    } on RequestCancelled {
      if (mounted && current == generation) setState(() => loading = false);
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() {
          loading = false;
          error = '标签未更新，原列表已保留：$failure';
          retryMore = append && !restartRequired;
        });
      }
    }
  }

  Future<void> count() async {
    if (!mounted || !widget.active) return;
    final current = ++countGeneration;
    setState(() => matching = null);
    try {
      final result = pack
          ? (await repo.loadPacks(PackQuery(tags: selected), limit: 1)).total
          : (await repo.loadVideoEntry(
              VideoEntryScope(
                query: VideoQuery(tags: selected),
                source: BrowseSource.tags,
                sort: VideoSort.name,
              ),
              limit: 1,
            )).total;
      if (mounted && widget.active && current == countGeneration) {
        setState(() => matching = result);
      }
    } catch (failure) {
      if (mounted && widget.active && current == countGeneration) {
        setState(() => error = failure.toString());
      }
    }
  }

  Future<void> form() => edit();

  Future<void> edit([TagCatalogItem? tag]) async {
    if (saving || repo.backupRestorePending) return;
    final identity = repo.connectionIdentity;
    final editingPack = pack, editingType = type;
    final input = TextEditingController(text: tag?.name ?? '');
    final errorAnchor = GlobalKey();
    var formError = '';
    var confirming = false;
    final removed = await paperSheet<bool>(
      context,
      AnimatedBuilder(
        animation: repo,
        builder: (context, _) => StatefulBuilder(
          builder: (context, local) {
            final p = Paper.of(context);
            final current =
                identical(identity, repo.connectionIdentity) &&
                !repo.backupRestorePending;
            Future<void> write({bool remove = false}) async {
              if (saving ||
                  !identical(identity, repo.connectionIdentity) ||
                  repo.backupRestorePending) {
                return;
              }
              final name = input.text.trim();
              if (!remove && (name.isEmpty || name.runes.length > 100)) {
                local(() => formError = '请输入1至100字的标签名称');
                revealFormError(errorAnchor);
                return;
              }
              local(() {
                saving = true;
                formError = '';
              });
              try {
                if (editingPack) {
                  await repo.editPackTag(
                    original: tag?.id,
                    name: name,
                    delete: remove,
                  );
                } else {
                  await repo.editTag(
                    original: tag?.id,
                    name: name,
                    delete: remove,
                  );
                }
                if (context.mounted &&
                    identical(identity, repo.connectionIdentity) &&
                    !repo.backupRestorePending) {
                  Navigator.pop(context, remove);
                }
              } catch (failure) {
                if (context.mounted) {
                  local(() => formError = failure.toString());
                  revealFormError(errorAnchor);
                }
              } finally {
                if (context.mounted) {
                  local(() => saving = false);
                } else {
                  saving = false;
                }
              }
            }

            if (confirming) {
              return PopScope(
                canPop: !saving,
                child: SheetFrame(
                  title: '移除$editingType标签',
                  closeEnabled: !saving,
                  footer: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => local(() {
                                confirming = false;
                                formError = '';
                              }),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        key: const Key('tag-definition-remove-confirm'),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.danger,
                          foregroundColor: p.background,
                        ),
                        onPressed: saving || !current
                            ? null
                            : () => write(remove: true),
                        child: Text(saving ? '正在移除…' : '确认移除标签'),
                      ),
                    ],
                  ),
                  children: [
                    Text(
                      tag!.name,
                      style: TextStyle(fontSize: 14, height: 1.6, color: p.ink),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '移除这个$editingType标签及其关联，保留所有媒体内容。另一类同名标签不受影响。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: p.catalogMeta,
                      ),
                    ),
                    if (!current)
                      Text(
                        '连接或管理数据已变化，请关闭后重新打开。',
                        key: const Key('tag-definition-stale'),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: p.danger,
                        ),
                      ),
                    if (formError.isNotEmpty)
                      Padding(
                        key: errorAnchor,
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          formError,
                          key: const Key('tag-definition-error'),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.7,
                            color: p.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }
            return PopScope(
              canPop: !saving,
              child: SheetFrame(
                title: tag == null ? '新建$editingType标签' : '管理$editingType标签',
                closeEnabled: !saving,
                footer: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      key: const Key('tag-definition-save'),
                      onPressed: saving || !current ? null : () => write(),
                      child: Text(
                        saving
                            ? '正在保存…'
                            : tag == null
                            ? '创建标签'
                            : '保存名称',
                      ),
                    ),
                    if (tag != null)
                      TextButton(
                        key: const Key('tag-definition-remove'),
                        style: TextButton.styleFrom(foregroundColor: p.danger),
                        onPressed: saving || !current
                            ? null
                            : () => local(() {
                                confirming = true;
                                formError = '';
                              }),
                        child: const Text('移除这个标签'),
                      ),
                  ],
                ),
                children: [
                  Text(
                    tag == null
                        ? '新标签只出现在$editingType分类中。'
                        : '只修改$editingType标签及其关联。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: p.catalogMeta,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PaperField(
                    label: '标签名称',
                    child: TextField(
                      key: const Key('tag-name'),
                      controller: input,
                      enabled: !saving && current,
                      style: TextStyle(fontSize: 16, color: p.ink),
                      decoration: const InputDecoration(hintText: '输入标签名称'),
                      maxLength: 100,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => write(),
                    ),
                  ),
                  if (!current)
                    Text(
                      '连接或管理数据已变化，请关闭后重新打开。',
                      key: const Key('tag-definition-stale'),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: p.danger,
                      ),
                    ),
                  if (formError.isNotEmpty)
                    Padding(
                      key: errorAnchor,
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        formError,
                        key: const Key('tag-definition-error'),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.7,
                          color: p.danger,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    input.dispose();
    if (mounted && widget.active) {
      if (removed == true && identical(identity, repo.connectionIdentity)) {
        selected.remove(tag!.id);
      }
      await load();
      await count();
    }
  }

  @override
  void dispose() {
    generation++;
    countGeneration++;
    repo.removeListener(repositoryChanged);
    if (pack) {
      repo.cancelPackTagRead();
    } else {
      repo.cancelVideoTagRead();
    }
    search.dispose();
    super.dispose();
  }

  Widget heading(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$type标签', style: Paper.of(context).title.copyWith(fontSize: 23)),
        const SizedBox(height: 9),
        Text(
          pack ? '选择一个或多个标签，找到图包。' : '选择一个或多个标签，确定视频预览范围。',
          style: TextStyle(
            fontSize: 13,
            height: 1.7,
            color: Paper.of(context).catalogMeta,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: Key('${widget.kind.name}-tag-search'),
          controller: search,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: '搜索标签',
            fillColor: Colors.transparent,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (_) => load(),
        ),
      ],
    ),
  );

  Widget row(BuildContext context, TagCatalogItem tag) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Paper.of(context).line)),
    ),
    child: Semantics(
      selected: selected.contains(tag.id),
      child: ListTile(
        key: Key('${widget.kind.name}-tag-${tag.id}'),
        minLeadingWidth: 20,
        horizontalTitleGap: 16,
        minTileHeight: 65,
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected.contains(tag.id) ? Paper.of(context).olive : null,
            border: Border.all(
              color: Paper.of(context).olive.withValues(alpha: .7),
            ),
          ),
          child: selected.contains(tag.id)
              ? Icon(Icons.check, size: 15, color: Paper.of(context).background)
              : null,
        ),
        title: Text(
          tag.name,
          style: Paper.of(context).title.copyWith(fontSize: 20),
        ),
        subtitle: Text(
          '${tag.count} 个$type',
          style: TextStyle(fontSize: 12, color: Paper.of(context).muted),
        ),
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            selected.contains(tag.id)
                ? selected.remove(tag.id)
                : selected.add(tag.id);
          });
          unawaited(count());
        },
        trailing: IconButton(
          tooltip: '管理$type标签 ${tag.name}',
          onPressed: repo.backupRestorePending ? null : () => edit(tag),
          icon: const Icon(Icons.more_horiz),
          iconSize: 18,
        ),
      ),
    ),
  );

  Widget dock(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Paper.of(context).background,
      border: Border(top: BorderSide(color: Paper.of(context).line)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selected.isEmpty ? '全部$type' : '同时包含 ${selected.length} 个标签',
                  style: TextStyle(
                    fontSize: 13,
                    color: Paper.of(context).catalogMeta,
                  ),
                ),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        setState(selected.clear);
                        unawaited(count());
                      },
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('清除选择'),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    matching == null ? '正在统计…' : '匹配 $matching 个$type',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                if (!pack)
                  TextButton(
                    key: const Key('tag-view-results'),
                    onPressed: matching == null
                        ? null
                        : () => widget.onView({...selected}),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('查看结果 →'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            key: Key(pack ? 'tag-view-results' : 'tag-preview-results'),
            style: FilledButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed:
                matching == null ||
                    matching == 0 ||
                    (!pack && repo.backupRestorePending)
                ? null
                : () => !pack && widget.onPreview != null
                      ? widget.onPreview!({...selected})
                      : widget.onView({...selected}),
            child: Text(
              matching == null
                  ? '正在统计…'
                  : pack
                  ? '查看 $matching 个图包'
                  : '预览这 $matching 个视频',
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (error.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Text(
                    error,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: Paper.of(context).danger,
                    ),
                  ),
                ),
              ),
              TextButton(
                key: const Key('tag-read-retry'),
                onPressed: loading
                    ? null
                    : () {
                        unawaited(load(more: retryMore));
                        unawaited(count());
                      },
                child: const Text('重试'),
              ),
            ],
          ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: heading(context)),
              if (tags.isEmpty && !loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          search.text.isEmpty ? '还没有$type标签' : '没有匹配的$type标签',
                        ),
                        TextButton(
                          onPressed: repo.backupRestorePending
                              ? null
                              : () => form(),
                          child: const Text('新建标签'),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: tags.length + (tags.length < total ? 1 : 0),
                  itemBuilder: (context, index) => index == tags.length
                      ? TextButton(
                          onPressed: loading || loadedSearch != search.text
                              ? null
                              : () => load(more: true),
                          child: const Text('更多标签'),
                        )
                      : row(context, tags[index]),
                ),
              ),
            ],
          ),
        ),
        if (MediaQuery.viewInsetsOf(context).bottom == 0)
          ConstrainedBox(
            // IndexedStack also lays out inactive pages while Scaffold is
            // resizing for the keyboard. Bound the dock by actual room rather
            // than the insets Scaffold has already consumed; retain list space.
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .6),
            child: SingleChildScrollView(
              key: Key('${widget.kind.name}-tag-actions-scroll'),
              primary: false,
              child: dock(context),
            ),
          ),
      ],
    ),
  );
}
