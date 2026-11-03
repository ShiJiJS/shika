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
  final selections = PackPurgeSelections(files);
  final choice = await selections.save(ids);
  final commands = <PackFileCommand>[];
  var remaining = choice.remaining;
  while (remaining.isNotEmpty) {
    final batch = remaining.take(1000).toList();
    final command = PackFileCommand.deleteDirectories(
      packFileRequestId(),
      batch,
      selectionId: choice.id,
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
  var accepted = 0;
  for (final command in commands) {
    if (!files.isCurrent()) return;
    try {
      final task = await files.send(command);
      accepted += command.targets.length;
      if (task.settled && !task.result!.needsAttention) {
        await files.acknowledgeTask(task);
      }
      repository.packFilesChanged();
      notify?.call('已提交 $accepted 个图包，服务器正在后台删除，可在任务页查看结果');
    } catch (_) {
      if (!files.isCurrent()) return;
      // A lost response is queried by its original ID, never re-POSTed here.
      try {
        final task = await files.receipt(command);
        if (!files.isCurrent()) return;
        if (task != null) {
          accepted += command.targets.length;
          if (task.settled && !task.result!.needsAttention) {
            await files.acknowledgeTask(task);
          }
          repository.packFilesChanged();
          notify?.call('已提交 $accepted 个图包，服务器正在后台删除，可在任务页查看结果');
          continue;
        }
      } catch (_) {
        // The original command stays available in pending operations.
      }
      notify?.call('删除请求已保存，连接结果待确认，可在待处理操作中查询；不会重复提交');
    }
  }
}
