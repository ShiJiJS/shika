import 'dart:convert';

import 'package:video_viewer/library/models.dart';

const scanRoots = [
  MediaRoot('V', '视频收藏', '/media/video'),
  MediaRoot('A', '图包 A', '/media/packs-a', kind: MediaKind.pack),
  MediaRoot(
    'B',
    '图包 B',
    '/media/packs-b',
    kind: MediaKind.pack,
    available: false,
  ),
];

Map<String, dynamic> scanFixture({bool running = true}) => jsonDecode(
  jsonEncode({
    'ready': true,
    'scanning': running,
    'status': running ? 'running' : 'completed',
    'phase': running ? 'pack_inspecting' : 'completed',
    'task_id': 'round-1',
    'progress': {'discovered': 600, 'processed': 600},
    'media': {
      'video': {'ready': true, 'scanning': false, 'indexed': 600},
      'pack': {
        'ready': !running,
        'scanning': running,
        'indexed': 3,
        'counts': {
          'progress': {
            'processed': running ? 103 : 220,
            'packs_processed': running ? 2 : 3,
          },
        },
      },
    },
    'roots': [
      for (final root in scanRoots)
        {
          'id': root.id,
          'kind': root.kind.name,
          'enabled': true,
          'available': true,
          'ready': root.id != 'B' || !running,
          'last_scan': root.id != 'B' || !running ? 1710000000 : null,
          'queued_task_ids': <String>[],
          'scan': {
            'id': root.id,
            'task_id': 'round-1',
            'kind': root.kind.name,
            'status': root.id == 'B' && running
                ? 'processing_media'
                : 'completed',
            'phase': root.id == 'B' && running
                ? 'processing_media'
                : 'completed',
            'finished_at': root.id == 'B' && running ? null : 1710000000,
            'discovered': root.id == 'V'
                ? 600
                : root.id == 'A'
                ? 1
                : 2,
            'processed': root.id == 'V'
                ? 600
                : root.id == 'A' || running
                ? 1
                : 2,
            'counts': {'imported': root.id == 'V' ? 600 : 1},
            'progress': {
              'discovered': root.id == 'V'
                  ? 600
                  : root.id == 'A'
                  ? 40
                  : 180,
              'processed': root.id == 'V'
                  ? 600
                  : root.id == 'A'
                  ? 40
                  : running
                  ? 63
                  : 180,
              'discovery_complete': root.id != 'B' || !running,
              if (root.kind == MediaKind.pack) ...{
                'packs_discovered': root.id == 'A' ? 1 : 2,
                'packs_processed': root.id == 'A' || running ? 1 : 2,
                'packs_discovery_complete': true,
              },
            },
          },
        },
    ],
  }),
) as Map<String, dynamic>;
