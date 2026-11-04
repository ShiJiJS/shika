import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/models.dart';

import 'support/root_scan_fixture.dart';

void main() {
  test(
    'an interrupted legacy round cannot leave its root pretending to scan',
    () {
      final value = LibraryPreparation.fromJson({
        'ready': true,
        'scanning': false,
        'status': 'interrupted',
        'phase': 'interrupted',
        'roots': [
          {
            'id': 'A',
            'scan': {
              'id': 'A',
              'kind': 'pack',
              'status': 'discovering',
              'processed': 11,
            },
          },
        ],
      });
      expect(value.rootProgress('A').status, 'interrupted');
      expect(value.rootProgress('A').active, false);
      expect(value.rootProgress('A').legacyProcessed, 11);
    },
  );
  test(
    'pack progress uses images and packs independently from video totals',
    () {
      final value = LibraryPreparation.fromJson(scanFixture());
      final a = value.rootProgress('A'), b = value.rootProgress('B');
      expect(a.status, 'completed');
      expect(a.processed, 40);
      expect(a.packsProcessed, 1);
      expect(b.processed, 63);
      expect(b.discovered, 180);
      expect(b.packsProcessed, 1);
      expect(b.packsDiscovered, 2);
      expect(b.totalKnown, false);
      expect(b.packTotalKnown, true);
      expect(value.label, '正在读取图片');
      expect(value.summary, isNot(contains('600')));
      final offline = value.offline();
      expect(offline.rootProgress('A').scan, a.scan);
      expect(offline.rootProgress('B').processed, 63);
      expect(offline.media, value.media);
      expect(offline.syncError, isNotNull);
    },
  );

  test(
    'queue preserves prior completed facts and absent values stay unknown',
    () {
      final body = scanFixture(running: false);
      (body['roots'] as List)[1]['queued_task_ids'] = ['next-A'];
      final value = LibraryPreparation.fromJson(body);
      expect(value.rootProgress('A').status, 'completed');
      expect(value.rootProgress('A').queued, true);
      expect(value.rootProgress('A').processed, 40);
      expect(value.rootProgress('missing').known, false);
      expect(value.rootProgress('missing').processed, isNull);
      final malformed = RootScanProgress({
        'scan': {
          'status': 7,
          'finished_at': 1e100,
          'progress': {'processed': -1, 'discovered': '180'},
        },
        'queued_task_ids': 'wrong',
      });
      expect(malformed.processed, isNull);
      expect(malformed.discovered, isNull);
      expect(malformed.finishedAt, isNull);
      expect(malformed.queued, false);
      expect(malformed.status, 'unknown');
    },
  );
}
