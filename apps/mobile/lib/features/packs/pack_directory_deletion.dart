import 'dart:async';

import '../../library/models.dart';
import '../../library/repository.dart';

/// Persist all selected batches before networking. The caller returns to the
/// library; HTTP acceptance and folder work never own a modal or reader.
Future<List<PackFileCommand>> enqueueDirectoryDeletion(
  LibraryRepository repository,
  PackFiles files,
  Iterable<String> ids, {
  void Function(String message)? notify,
}) async {
  if (!repository.capabilities.packDirectoryDelete ||
      !files.isCurrent() ||
      files.readOnly) {
    throw const LibraryFailure('请先升级服务端再删除图包文件夹');
  }
  final commands = <PackFileCommand>[];
  final selected = ids.toSet().toList()..sort();
  final pending = await files.pending();
  final alreadyDeleting = {
    for (final c in pending.where((c) => c.kind == 'directory_delete'))
      ...c.targets,
  };
  var remaining = selected
      .where((id) => !alreadyDeleting.contains(id))
      .toList();
  while (remaining.isNotEmpty) {
    final batch = remaining.take(1000).toList();
    final command = PackFileCommand.deleteDirectories(
      packFileRequestId(),
      batch,
    );
    await files.journal.remember(files.scope, command);
    commands.add(command);
    remaining = remaining.skip(batch.length).toList();
  }
  // Commands remain in the durable log if the app closes or a reply is lost.
  unawaited(_submit(repository, files, commands, notify));
  return commands;
}

Future<void> _submit(
  LibraryRepository repository,
  PackFiles files,
  List<PackFileCommand> commands,
  void Function(String)? notify,
) async {
  for (final command in commands) {
    if (!files.isCurrent()) return;
    try {
      final task = await files.send(command);
      repository.packFilesChanged();
      if (task.settled) {
        notify?.call(task.result!.failed == 0 ? '已永久删除' : '部分图包未删除，请重试');
      }
    } catch (_) {
      if (!files.isCurrent()) return;
      // A lost response is queried by its original ID, never re-POSTed here.
      try {
        final task = await files.receipt(command);
        if (!files.isCurrent()) return;
        if (task != null) {
          repository.packFilesChanged();
          if (task.settled) {
            notify?.call(task.result!.failed == 0 ? '已永久删除' : '部分图包未删除，请重试');
          }
          continue;
        }
      } catch (_) {
        // The original command stays available in pending operations.
      }
      if (!files.isCurrent()) return;
      if (!(await files.pending()).any(
        (c) => c.requestId == command.requestId,
      )) {
        continue;
      }
      notify?.call('网络连接不稳定，稍后会自动刷新');
    }
  }
}
