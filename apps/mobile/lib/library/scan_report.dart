import 'models.dart';

/// Read the existing scan task, never start a scan or change the library.
/// Issue lists are server-bounded samples; they are not full error inventories.
class ScanReport {
  ScanReport(Map<String, dynamic> data)
    : id = data['id'] as String,
      status = data['status'] as String,
      error = data['error'] as String?,
      result = Map<String, dynamic>.from(data['result'] as Map) {
    if (data['kind'] != 'scan') {
      throw const FormatException('Expected a scan task');
    }
  }

  final String id, status;
  final String? error;
  final Map<String, dynamic> result;

  RootScanProgress? root(String id) {
    for (final value
        in (result['root_scans'] ?? result['roots']) as List? ?? []) {
      if (value is Map && value['id'] == id) {
        return RootScanProgress({'scan': Map<String, dynamic>.from(value)});
      }
    }
    return null;
  }

  List<ScanIssue> issues(MediaRoot root) {
    final summary = root.kind == MediaKind.pack ? result['packs'] : result;
    if (summary is! Map) return const [];
    return [
      for (final key in ['issues', 'warnings'])
        for (final value in summary[key] is List ? summary[key] as List : [])
          if (value is Map &&
              value['root_id'] == root.id &&
              value['code'] is String)
            ScanIssue(
              value['code'] as String,
              value['name'] as String?,
              value['pack_id'] as String?,
              warning: key == 'warnings',
            ),
    ];
  }
}

class ScanIssue {
  const ScanIssue(this.code, this.name, this.packId, {this.warning = false});
  final String code;
  final String? name, packId;
  final bool warning;
}

String scanIssueReason(String code) => switch (code) {
  'root_unmapped' => '目录尚未连接，请检查媒体目录设置。',
  'root_unavailable' || 'pack_directory_unavailable' => '目录无法访问，请检查挂载、连接和读取权限。',
  'permission_denied' => '读取权限不足，请检查文件或目录权限。',
  'file_missing' => '文件已移走或不存在，请重新同步目录。',
  'probe_timeout' => '读取视频信息超时，可以稍后重试。',
  'probe_failed' || 'invalid_metadata' => '无法解析媒体信息，文件可能不完整或格式不受支持。',
  'probe_unavailable' => '服务端的视频探测工具不可用。',
  'no_video_stream' => '文件中没有找到视频轨道。',
  'invalid_duration' || 'invalid_dimensions' => '视频时长或尺寸信息不完整。',
  'image_probe_timeout' => '读取图片超时，可以稍后重试。',
  'image_probe_failed' => '图片无法解码，可能已损坏、格式不受支持或超出服务端的解码资源。',
  'image_probe_unavailable' => '服务端的图片解码工具不可用。',
  'image_too_large' => '图片超出当前服务端的解码资源限制。',
  'no_readable_images' => '没有可阅读的图片；目录可能为空，或其中的图片均未能读取。',
  'no_images' || 'pack_empty' => '目录中没有找到支持的图片。',
  'identity_ambiguous' => '内容身份存在冲突，本次没有自动合并，请检查是否有重复目录。',
  'pack_scan_incomplete' => '部分图包未能读取，原有记录已保留。',
  'files_changing' => '文件仍在写入或发生变化，稳定后可重新扫描。',
  'service_restarted' || 'scan_interrupted' => '扫描已中断，可以重新扫描此目录。',
  'scan_failed' => '本次扫描未完成，请检查服务端状态后重试。',
  'thumbnail_timeout' => '生成缩略图超时，不影响内容入库。',
  'thumbnail_resource_limit' => '生成缩略图时资源不足，不影响内容入库。',
  'thumbnail_failed' || 'thumbnail_unavailable' => '缩略图未能生成，不影响内容入库。',
  _ => '服务端记录了读取异常，具体错误代码见下方。',
};
