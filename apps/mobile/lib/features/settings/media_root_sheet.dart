import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../ui/paper.dart';

class MediaRootSheet extends StatefulWidget {
  const MediaRootSheet({super.key, required this.repository, this.root});
  final LibraryRepository repository;
  final MediaRoot? root;
  @override
  State<MediaRootSheet> createState() => _MediaRootSheetState();
}

class _MediaRootSheetState extends State<MediaRootSheet> {
  late final name = TextEditingController(text: widget.root?.name ?? '');
  late final path = TextEditingController(text: widget.root?.path ?? '');
  late final Object connection;
  late MediaKind kind = widget.root?.kind ?? MediaKind.video;
  late bool enabled = widget.root?.enabled ?? true;
  bool saving = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    connection = widget.repository.connectionIdentity;
  }

  @override
  void dispose() {
    name.dispose();
    path.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (!identical(connection, widget.repository.connectionIdentity)) {
      setState(() => error = '服务连接已变化，请关闭后重新打开目录设置');
      return;
    }
    final title = name.text.trim(), input = path.text.trim();
    if (title.isEmpty || input.isEmpty) {
      setState(() => error = '请填写名称和挂载目录');
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await widget.repository.saveRoot(
        MediaRoot(
          widget.root?.id ?? '',
          title,
          input.length > 1 ? input.replaceAll(RegExp(r'/+$'), '') : input,
          kind: kind,
          enabled: enabled,
        ),
      );
      if (mounted &&
          identical(connection, widget.repository.connectionIdentity)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: widget.root == null ? '添加媒体目录' : '编辑媒体目录',
    children: [
      TextField(
        key: const Key('root-name'),
        controller: name,
        enabled: !saving,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('root-path'),
        controller: path,
        enabled: !saving,
        decoration: const InputDecoration(labelText: '挂载目录'),
      ),
      const SizedBox(height: 18),
      if (widget.repository.capabilities.typedRoots) ...[
        const Text('媒体类型'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in MediaKind.values)
              ChoiceChip(
                key: Key('root-kind-${value.name}'),
                label: Text(value == MediaKind.video ? '视频' : '图包'),
                selected: kind == value,
                onSelected: saving
                    ? null
                    : (_) {
                        FocusScope.of(context).unfocus();
                        setState(() => kind = value);
                      },
              ),
          ],
        ),
        if (widget.root != null) const Text('已有内容的目录不能直接更改类型，请新建正确类型的接入目录。'),
        SwitchListTile(
          key: const Key('root-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('启用目录'),
          subtitle: const Text('停用后保留标签和阅读记录，暂不显示内容或扫描此目录'),
          value: enabled,
          onChanged: saving
              ? null
              : (value) {
                  FocusScope.of(context).unfocus();
                  setState(() => enabled = value);
                },
        ),
      ] else
        const Text('当前服务仅支持视频目录；升级服务后可选择图包类型或停用目录。'),
      const Text('扫描包含子目录，不修改源文件位置。'),
      const SizedBox(height: 12),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(error, style: TextStyle(color: Paper.of(context).danger)),
        ),
      FilledButton(
        key: const Key('root-save'),
        onPressed: saving ? null : save,
        child: Text(saving ? '正在保存…' : '保存'),
      ),
    ],
  );
}
