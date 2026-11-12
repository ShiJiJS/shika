import 'package:flutter/material.dart';

import '../../library/models.dart';
import '../../library/repository.dart';
import '../../library/request_scope.dart';
import '../../ui/paper.dart';
import 'scan_progress_card.dart';

class ScanIssuesPage extends StatefulWidget {
  const ScanIssuesPage({
    super.key,
    required this.repository,
    required this.root,
    required this.initial,
    this.taskId,
  });
  final LibraryRepository repository;
  final MediaRoot root;
  final RootScanProgress initial;
  final String? taskId;

  @override
  State<ScanIssuesPage> createState() => _ScanIssuesPageState();
}

class _ScanIssuesPageState extends State<ScanIssuesPage> {
  late final owner = widget.repository.connectionIdentity;
  RequestScope? work;
  ScanReport? report;
  bool busy = false;
  String error = '';
  bool get current => owner == widget.repository.connectionIdentity;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(ownerChanged);
    load();
  }

  void ownerChanged() {
    if (!current) {
      work?.cancel();
      setState(() {
        report = null;
        busy = false;
        error = '服务连接已变化，请返回后重新打开扫描详情。';
      });
    }
  }

  Future<void> load() async {
    final taskId = widget.taskId;
    if (!current || taskId == null) return;
    work?.cancel();
    final request = work = RequestScope();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final value = await widget.repository.loadScanReport(
        taskId,
        cancel: request,
      );
      if (!mounted || !current || request.cancelled) return;
      setState(() => report = value);
    } catch (failure) {
      if (!mounted || !current || request.cancelled) return;
      setState(
        () => error = failure is LibraryFailure
            ? failure.message
            : '扫描明细暂时无法读取，请检查连接后重新读取。',
      );
    } finally {
      if (mounted && current && !request.cancelled) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(ownerChanged);
    work?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Paper.of(context);
    final facts = report?.root(widget.root.id) ?? widget.initial;
    final issues = report?.issues(widget.root) ?? const <ScanIssue>[];
    final reasons = {
      if (facts.error ?? widget.root.error case final String code) code,
      if (report?.root(widget.root.id) == null && report?.error != null)
        report!.error!,
    };
    final counts = [
      if (facts.count('failed') > 0 && widget.root.kind == MediaKind.video)
        '${facts.count('failed')} 个视频信息读取失败',
      if (facts.pageErrors > 0) '${facts.pageErrors} 张图片无法读取',
      if (facts.count('failed_packs') > 0)
        '${facts.count('failed_packs')} 个图包无法读取',
      if (facts.unreadablePacks > 0) '${facts.unreadablePacks} 个图包没有可阅读的图片',
      if (facts.count('thumbnail_failed') > 0)
        '${facts.count('thumbnail_failed')} 个缩略图未能生成（不影响入库）',
      if (facts.count('deferred') > 0) '${facts.count('deferred')} 项文件仍在变化',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('扫描详情')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.root.name, style: p.title.copyWith(fontSize: 20)),
          const SizedBox(height: 8),
          SelectableText(widget.root.path, style: TextStyle(color: p.muted)),
          const SizedBox(height: 8),
          Text(scanRootLabel(widget.root, facts)),
          if (facts.active)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('扫描仍在后台进行，重新读取可查看最新问题。'),
            ),
          const SizedBox(height: 16),
          if (busy) const PaperLinearProgressIndicator(),
          if (current) ...[
            for (final count in counts) Text(count),
            for (final code in reasons) ...[
              const SizedBox(height: 12),
              Text(scanIssueReason(code), style: TextStyle(color: p.danger)),
              SelectableText(
                '错误代码：$code',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ],
          ],
          if (error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(error, style: TextStyle(color: p.danger)),
          ],
          if (widget.taskId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('scan-report-refresh'),
                onPressed: busy || !current ? null : load,
                icon: const Icon(Icons.refresh),
                label: const Text('重新读取'),
              ),
            ),
          const Divider(height: 32),
          Text('问题原因', style: p.title.copyWith(fontSize: 18)),
          if (current && issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('以下为服务端记录的问题明细，可能仅包含部分文件；数量以目录扫描记录为准。'),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      issue.name?.isNotEmpty == true
                          ? issue.name!
                          : issue.packId != null
                          ? '图包编号：${issue.packId}'
                          : widget.root.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scanIssueReason(issue.code),
                      style: TextStyle(
                        color: issue.warning ? p.muted : p.danger,
                      ),
                    ),
                    SelectableText(
                      '错误代码：${issue.code}',
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
          ] else if (current && !busy) ...[
            const SizedBox(height: 8),
            Text(
              widget.taskId == null
                  ? '这条旧扫描记录没有任务明细，当前可查看上方目录状态和原因。'
                  : report == null
                  ? '明细尚未读取成功，上方保留已有的目录扫描记录。'
                  : counts.isNotEmpty ||
                        reasons.isNotEmpty ||
                        const {
                          'partial',
                          'failed',
                          'interrupted',
                          'unavailable',
                        }.contains(facts.status)
                  ? '服务端未提供具体文件的错误明细，无法进一步确认原因；已有问题数量保留在上方。'
                  : facts.active
                  ? '目前没有记录到问题，扫描尚未完成。'
                  : '这次扫描没有记录到问题。',
            ),
          ],
        ],
      ),
    );
  }
}
