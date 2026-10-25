import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../ui/paper.dart';
import '../../ui/preferences.dart';
import 'default_settings_session.dart';

class DefaultSettingsSheet extends StatefulWidget {
  const DefaultSettingsSheet({
    super.key,
    required this.repository,
    required this.local,
    required this.video,
  });
  final LibraryRepository repository;
  final UiPreferences local;
  final bool video;
  @override
  State<DefaultSettingsSheet> createState() => _DefaultSettingsSheetState();
}

class _DefaultSettingsSheetState extends State<DefaultSettingsSheet> {
  late final session = DefaultSettingsSession(
    widget.repository,
    widget.local,
    video: widget.video,
  );
  @override
  void initState() {
    super.initState();
    session.load();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  Future<void> save({bool query = false}) async {
    if (await session.save(query: query) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => SheetFrame(
      title: widget.video ? '默认播放顺序' : '阅读偏好',
      children: [
        Text(
          widget.video
              ? '保存在当前服务，只影响新进入的预览范围。当前预览顺序不变。'
              : '保存在当前服务，作为未阅读图包的默认方式。已阅读图包继续使用各自偏好。',
          style: TextStyle(fontSize: 13, color: Paper.of(context).muted),
        ),
        const SizedBox(height: 16),
        if (session.busy) const LinearProgressIndicator(),
        if (session.ready) ...[
          if (widget.video) ...[
            for (final value in PlayOrder.values)
              ListTile(
                title: Text(value == PlayOrder.random ? '随机播放' : '顺序播放'),
                subtitle: Text(
                  value == PlayOrder.random ? '范围内随机排列' : '沿用入口列表的排序',
                ),
                trailing: session.order == value
                    ? const Icon(Icons.check)
                    : null,
                onTap: session.blocked
                    ? null
                    : () => session.selectOrder(value),
              ),
            if (session.migrationOffered) ...[
              const Divider(),
              Text(
                '此设备旧默认：${widget.local.videoOrder == PlayOrder.random ? '随机播放' : '顺序播放'}。可明确迁移到当前服务，或沿用服务端设置。其它服务分别选择。',
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: session.blocked
                        ? null
                        : () => session.selectOrder(widget.local.videoOrder!),
                    child: const Text('选用本机旧顺序'),
                  ),
                  TextButton(
                    onPressed: session.blocked ? null : session.keepServer,
                    child: const Text('沿用服务端设置'),
                  ),
                ],
              ),
            ],
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in ReaderMode.values)
                  ChoiceChip(
                    label: Text(
                      value == ReaderMode.horizontal ? '横向翻页' : '纵向拼接',
                    ),
                    selected: session.preferences.mode == value,
                    onSelected: session.blocked
                        ? null
                        : (_) => session.selectPreferences(
                            session.preferences.copy(mode: value),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in ReaderDirection.values)
                  ChoiceChip(
                    label: Text(value == ReaderDirection.ltr ? '从左向右' : '从右向左'),
                    selected: session.preferences.direction == value,
                    onSelected: session.blocked
                        ? null
                        : (_) => session.selectPreferences(
                            session.preferences.copy(direction: value),
                          ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('图片间距'),
              subtitle: const Text('纵向拼接时留出间距'),
              value: session.preferences.gap,
              onChanged: session.blocked
                  ? null
                  : (v) => session.selectPreferences(
                      session.preferences.copy(gap: v),
                    ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in ReaderFit.values)
                  ChoiceChip(
                    label: Text(value == ReaderFit.contain ? '完整显示' : '铺满宽度'),
                    selected: session.preferences.fit == value,
                    onSelected: session.blocked
                        ? null
                        : (_) => session.selectPreferences(
                            session.preferences.copy(fit: value),
                          ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: session.blocked ? null : save,
            child: const Text('保存默认设置'),
          ),
        ],
        if (session.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              session.error,
              style: TextStyle(color: Paper.of(context).danger),
            ),
          ),
        if (session.pending)
          OutlinedButton(
            onPressed: session.busy || !session.current
                ? null
                : () => save(query: true),
            child: const Text('核对原设置请求'),
          ),
        if (!session.ready || session.pending || session.needsReload)
          TextButton(
            onPressed: session.busy || !session.current ? null : session.load,
            child: const Text('读取服务端当前设置'),
          ),
      ],
    ),
  );
}
