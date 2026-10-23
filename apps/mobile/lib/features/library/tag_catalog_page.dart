import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';

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
  bool loading = false, saving = false;
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
        pack ? repo.cancelPackTagRead() : repo.cancelVideoRead();
      }
    }
  }

  void repositoryChanged() {
    if (widget.active && !saving) scheduleLoad();
  }

  Future<void> load({bool more = false}) async {
    final current = ++generation;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final List<TagCatalogItem> batch;
      final int count;
      if (pack) {
        final page = await repo.loadPackTags(
          search: search.text,
          offset: more ? tags.length : 0,
        );
        batch = page.items
            .map((tag) => TagCatalogItem(tag.id, tag.name, tag.count))
            .toList();
        count = page.total;
      } else {
        batch = repo.snapshot.tags
            .where((id) => repo.tagName(id).contains(search.text))
            .map(
              (id) =>
                  TagCatalogItem(id, repo.tagName(id), repo.tagVideoCount(id)),
            )
            .toList();
        count = batch.length;
      }
      if (!mounted || current != generation) return;
      setState(() {
        tags = more ? [...tags, ...batch] : batch;
        total = count;
        loading = false;
      });
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() {
          loading = false;
          error = failure.toString();
        });
      }
    }
  }

  Future<void> count() async {
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
    if (repo.backupRestorePending) return;
    final input = TextEditingController(text: tag?.name ?? '');
    await paperSheet<bool>(
      context,
      StatefulBuilder(
        builder: (context, local) => SheetFrame(
          title: tag == null ? '新建$type标签' : '管理$type标签',
          closeEnabled: !saving,
          children: [
            TextField(
              key: const Key('tag-name'),
              controller: input,
              enabled: !saving,
              decoration: const InputDecoration(labelText: '标签名称'),
              maxLength: 100,
            ),
            if (error.isNotEmpty) note(error),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      local(() {
                        saving = true;
                        error = '';
                      });
                      try {
                        if (pack) {
                          await repo.editPackTag(
                            original: tag?.id,
                            name: input.text,
                          );
                        } else {
                          await repo.editTag(
                            original: tag?.id,
                            name: input.text,
                          );
                        }
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (failure) {
                        if (context.mounted) {
                          local(() => error = failure.toString());
                        }
                      } finally {
                        if (context.mounted) {
                          local(() => saving = false);
                        } else {
                          saving = false;
                        }
                      }
                    },
              child: Text(saving ? '正在保存…' : '保存'),
            ),
            if (tag != null)
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        final confirmed = await paperSheet<bool>(
                          context,
                          SheetFrame(
                            title: '移除$type标签',
                            children: [
                              note('移除「${tag.name}」及其关联，保留所有媒体内容。另一类同名标签不受影响。'),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('确认移除标签'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !context.mounted) return;
                        local(() {
                          saving = true;
                          error = '';
                        });
                        try {
                          if (pack) {
                            await repo.editPackTag(
                              original: tag.id,
                              delete: true,
                            );
                          } else {
                            await repo.editTag(original: tag.id, delete: true);
                          }
                          selected.remove(tag.id);
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (failure) {
                          if (context.mounted) {
                            local(() => error = failure.toString());
                          }
                        } finally {
                          if (context.mounted) {
                            local(() => saving = false);
                          } else {
                            saving = false;
                          }
                        }
                      },
                child: const Text('移除这个标签'),
              ),
          ],
        ),
      ),
    );
    input.dispose();
    if (mounted && widget.active) {
      await load();
      await count();
    }
  }

  @override
  void dispose() {
    generation++;
    countGeneration++;
    repo.removeListener(repositoryChanged);
    if (pack) repo.cancelPackTagRead();
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
          pack ? '选择一个或多个标签，找到整包图片。' : '选择一个或多个标签，确定视频预览范围。',
          style: TextStyle(
            fontSize: 13,
            height: 1.7,
            color: Paper.of(context).muted,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: Key('${widget.kind.name}-tag-search'),
          controller: search,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            hintText: '搜索标签',
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
    child: ListTile(
      key: Key('${widget.kind.name}-tag-${tag.id}'),
      minLeadingWidth: 20,
      horizontalTitleGap: 16,
      minTileHeight: 65,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected.contains(tag.id)
            ? Icons.check_circle
            : Icons.radio_button_unchecked,
        color: Paper.of(context).olive,
        size: 20,
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
                    color: Paper.of(context).muted,
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
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('清除选择'),
              ),
            ],
          ),
          Row(
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
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('查看结果 →'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FilledButton(
            key: Key(pack ? 'tag-view-results' : 'tag-preview-results'),
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
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: heading(context)),
            if (loading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (error.isNotEmpty)
              SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: note(error)),
                    TextButton(
                      onPressed: () {
                        unawaited(load());
                        unawaited(count());
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            if (tags.isEmpty && !loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(search.text.isEmpty ? '还没有$type标签' : '没有匹配的$type标签'),
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
                        onPressed: loading ? null : () => load(more: true),
                        child: const Text('更多标签'),
                      )
                    : row(context, tags[index]),
              ),
            ),
          ],
        ),
      ),
      if (MediaQuery.viewInsetsOf(context).bottom == 0) dock(context),
    ],
  );
}
