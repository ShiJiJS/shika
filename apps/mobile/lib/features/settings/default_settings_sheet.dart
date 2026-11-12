import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';
import '../../ui/paper.dart';
import '../../ui/paper_form.dart';
import '../../ui/paper_icons.dart';
import '../../ui/media_layout.dart';
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
  final errorAnchor = GlobalKey();
  String lastError = '';

  void revealFailure() {
    if (session.error.isNotEmpty && session.error != lastError) {
      revealFormError(errorAnchor);
    }
    lastError = session.error;
  }

  late final session = DefaultSettingsSession(
    widget.repository,
    widget.local,
    video: widget.video,
  );
  @override
  void initState() {
    super.initState();
    session.addListener(revealFailure);
    session.load();
  }

  @override
  void dispose() {
    session.removeListener(revealFailure);
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
      title: widget.video ? '默认播放顺序' : '图包阅读偏好',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.ready)
            FilledButton(
              key: const Key('defaults-save'),
              onPressed: session.blocked ? null : save,
              child: const Text('保存默认设置'),
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
      children: [
        Text(
          widget.video
              ? '保存在当前服务，只影响新进入的预览范围。当前预览顺序不变。'
              : '保存在当前服务，作为未阅读图包的默认方式。已阅读图包继续使用各自偏好。',
          style: TextStyle(
            fontSize: 13,
            height: 1.7,
            color: Paper.of(context).catalogMeta,
          ),
        ),
        const SizedBox(height: 16),
        if (session.busy) const PaperLinearProgressIndicator(),
        if (session.ready) ...[
          if (widget.video) ...[
            for (final value in [PlayOrder.sequential, PlayOrder.random])
              ListTile(
                contentPadding: EdgeInsets.zero,
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
            Row(
              children: [
                for (final value in ReaderMode.values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: value == ReaderMode.vertical ? 5 : 0,
                        right: value == ReaderMode.horizontal ? 5 : 0,
                      ),
                      child: Semantics(
                        selected: session.preferences.mode == value,
                        child: OutlinedButton(
                          key: Key('default-mode-${value.name}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 97),
                            padding: const EdgeInsets.symmetric(
                              vertical: 15,
                              horizontal: 8,
                            ),
                            backgroundColor: session.preferences.mode == value
                                ? Paper.of(context).soft
                                : null,
                            foregroundColor: session.preferences.mode == value
                                ? Paper.of(context).olive
                                : Paper.of(context).ink,
                            side: BorderSide(
                              color: session.preferences.mode == value
                                  ? Paper.of(context).olive
                                  : Paper.of(context).line,
                            ),
                          ),
                          onPressed: session.blocked
                              ? null
                              : () => session.selectPreferences(
                                  session.preferences.copy(mode: value),
                                ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PaperIcon(
                                value == ReaderMode.horizontal
                                    ? PaperGlyph.horizontal
                                    : PaperGlyph.vertical,
                                size: 29,
                                color: session.preferences.mode == value
                                    ? Paper.of(context).olive
                                    : Paper.of(context).ink,
                              ),
                              const SizedBox(height: 9),
                              Text(
                                value == ReaderMode.horizontal
                                    ? '横向翻页'
                                    : '纵向拼接',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: MediaLayout.largeText(context) ? 16 : 0),
            PaperSettingRow(
              label: '默认翻页方向',
              child: PaperDropdownButtonFormField<ReaderDirection>(
                key: const Key('default-reader-direction'),
                initialValue: session.preferences.direction,
                isExpanded: true,
                isDense: false,
                alignment: AlignmentDirectional.centerEnd,
                decoration: PaperSettingRow.decoration,
                items: [
                  for (final value in ReaderDirection.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == ReaderDirection.ltr ? '从左向右' : '从右向左',
                      ),
                    ),
                ],
                onChanged: session.blocked
                    ? null
                    : (value) {
                        if (value != null) {
                          session.selectPreferences(
                            session.preferences.copy(direction: value),
                          );
                        }
                      },
              ),
            ),
            SwitchListTile(
              key: const Key('default-reader-gap'),
              contentPadding: EdgeInsets.zero,
              title: const Text('纵向图片间距'),
              value: session.preferences.gap,
              onChanged: session.blocked
                  ? null
                  : (v) => session.selectPreferences(
                      session.preferences.copy(gap: v),
                    ),
            ),
            SizedBox(height: MediaLayout.largeText(context) ? 16 : 0),
            PaperSettingRow(
              label: '图片适配',
              child: PaperDropdownButtonFormField<ReaderFit>(
                key: const Key('default-reader-fit'),
                initialValue: session.preferences.fit,
                isExpanded: true,
                isDense: false,
                alignment: AlignmentDirectional.centerEnd,
                decoration: PaperSettingRow.decoration,
                items: [
                  for (final value in ReaderFit.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value == ReaderFit.contain ? '完整显示' : '铺满宽度'),
                    ),
                ],
                onChanged: session.blocked
                    ? null
                    : (value) {
                        if (value != null) {
                          session.selectPreferences(
                            session.preferences.copy(fit: value),
                          );
                        }
                      },
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
        if (session.error.isNotEmpty)
          Padding(
            key: errorAnchor,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              session.error,
              key: const Key('defaults-error'),
              style: TextStyle(color: Paper.of(context).danger),
            ),
          ),
      ],
    ),
  );
}
