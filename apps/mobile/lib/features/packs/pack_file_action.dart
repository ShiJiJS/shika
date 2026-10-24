import 'dart:async';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../ui/paper.dart';

class PackFileOutcome {
  const PackFileOutcome(this.files, this.command, this.task);
  final PackFiles files;
  final PackFileCommand command;
  final PackFileTask task;
}

Future<PackFileOutcome?> showPackFileAction(
  BuildContext context, {
  required PackFiles files,
  required PackFileCommand command,
  required String title,
  String? description,
  bool confirm = true,
}) => paperSheet<PackFileOutcome>(
  context,
  PackFileAction(
    files: files,
    command: command,
    title: title,
    description: description,
    confirm: confirm,
  ),
);

/// Dismissing an unresolved sheet preserves its durable intent for read-only recovery.
class PackFileAction extends StatefulWidget {
  const PackFileAction({
    super.key,
    required this.files,
    required this.command,
    required this.title,
    this.description,
    this.confirm = true,
  });
  final PackFiles files;
  final PackFileCommand command;
  final String title;
  final String? description;
  final bool confirm;
  @override
  State<PackFileAction> createState() => _PackFileActionState();
}

class _PackFileActionState extends State<PackFileAction> {
  late PackFileCommand command = widget.command;
  bool busy = true, attempted = false, resend = false;
  String error = '';
  String get actionLabel => switch (command.kind) {
    'restore' => '恢复图包',
    'undo' => '撤销移除',
    'retry' => '重试未完成项',
    _ => '移入回收站',
  };
  @override
  void initState() {
    super.initState();
    unawaited(prepare());
  }

  Future<void> prepare() async {
    try {
      final pending = await widget.files.pending();
      if (!mounted) return;
      final previous = pending
          .where(
            (value) =>
                value.resources.intersection(command.resources).isNotEmpty,
          )
          .firstOrNull;
      if (previous != null) {
        command = previous;
        await perform(false);
      } else if (!widget.confirm) {
        await perform(true);
      }
    } catch (failure) {
      if (mounted) setState(() => error = packFileFailureMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> perform(bool submit) async {
    setState(() {
      busy = true;
      attempted = true;
      resend = false;
      error = '';
    });
    try {
      final task = await widget.files.resolve(command, submit: submit);
      if (!mounted || !widget.files.isCurrent()) return;
      if (task?.settled == true) {
        Navigator.pop(context, PackFileOutcome(widget.files, command, task!));
      } else {
        final mayResend = task == null && await widget.files.canResend(command);
        if (!mounted) return;
        setState(() {
          resend = mayResend;
          error = task == null
              ? '未找到原请求。请核对回收站和当前内容后，再决定是否重新提交。'
              : task.status == 'interrupted' || task.status == 'failed'
              ? '操作已中断，服务恢复后可查询原结果。'
              : '服务仍在处理，可稍后查询原结果。';
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = packFileFailureMessage(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: attempted ? '核对图包操作' : widget.title,
    children: [
      if (widget.description != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(widget.description!),
        ),
      if (!attempted && widget.confirm && command.kind == 'trash')
        const Text('从媒体库中移除，保留源文件、整包标签和阅读进度。可以在图包回收站恢复。'),
      if (busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: LinearProgressIndicator(),
        ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(error, key: const Key('pack-operation-error')),
        ),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(attempted ? '稍后处理' : '取消'),
          ),
          if (resend)
            TextButton(
              onPressed: busy ? null : () => perform(true),
              child: const Text('重新提交原请求'),
            ),
          FilledButton(
            style: attempted || command.kind != 'trash'
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Paper.of(context).danger,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
            onPressed: busy ? null : () => perform(!attempted),
            child: Text(attempted ? '查询原结果' : actionLabel),
          ),
        ],
      ),
    ],
  );
}

void showPackUndo(
  BuildContext context,
  LibraryRepository repository,
  PackFileOutcome outcome, {
  Future<void> Function(PackFileOutcome)? onRestored,
}) {
  final result = outcome.task.result;
  if (result == null || result.succeeded == 0) return;
  final remaining = outcome.task.remainingUndo();
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('整包已移入回收站，源文件保留'),
        duration: remaining > Duration.zero
            ? remaining
            : const Duration(seconds: 3),
        action: remaining <= Duration.zero
            ? null
            : SnackBarAction(
                label: '撤销',
                onPressed: () {
                  unawaited(
                    () async {
                      if (!context.mounted || !outcome.files.isCurrent()) {
                        return;
                      }
                      final undone = await showPackFileAction(
                        context,
                        files: outcome.files,
                        command: PackFileCommand.undo(
                          packFileRequestId(),
                          outcome.task.id,
                          readerContext: outcome.command.readerContext,
                        ),
                        title: '撤销整包移除',
                        confirm: false,
                      );
                      if (undone == null) return;
                      await undone.files.acknowledge(undone.command);
                      repository.packFilesChanged();
                      if (context.mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              undone.task.result!.succeeded > 0
                                  ? '已恢复图包'
                                  : '未能恢复图包，请在回收站核对',
                            ),
                          ),
                        );
                        if (onRestored != null) await onRestored(undone);
                      }
                    }().catchError((Object failure) {
                      if (context.mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(packFileFailureMessage(failure)),
                          ),
                        );
                      }
                    }),
                  );
                },
              ),
      ),
    );
}
