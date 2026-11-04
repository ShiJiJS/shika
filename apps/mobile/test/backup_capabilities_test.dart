import 'package:flutter_test/flutter_test.dart';
import 'package:shika/library/models.dart';

Map<String, dynamic> completeInfo() => {
  'capabilities': ['backup_v2', 'management_authority', 'management_history'],
  'management_history_available': false,
  'management_backups': {
    'versions': [1, 2],
    'max_bytes': 32 * 1024 * 1024,
    'max_roots': 256,
  },
};

void main() {
  test('old services and limits alone keep the legacy backup path', () {
    expect(ServiceCapabilities.fromInfo({}).backupV2, isFalse);
    final info = completeInfo();
    info['capabilities'] = ['management_authority', 'management_history'];
    expect(ServiceCapabilities.fromInfo(info).backupV2, isFalse);
  });

  test(
    'public complete backup accepts negotiated limits and empty history',
    () {
      for (final maximum in [
        4096,
        32 * 1024 * 1024,
        64 * 1024 * 1024,
        256 * 1024 * 1024,
      ]) {
        final info = completeInfo();
        (info['management_backups'] as Map)['max_bytes'] = maximum;
        final capabilities = ServiceCapabilities.fromInfo(info);
        expect(capabilities.backupV2, isTrue);
        expect(capabilities.archiveMaximumBytes, maximum);
        expect(capabilities.historyAvailable, isFalse);
      }
    },
  );

  test(
    'incomplete public backup protocol is rejected before opening restore',
    () {
      final invalid = <Map<String, dynamic>>[];
      for (final field in ['max_bytes', 'max_roots', 'versions']) {
        final info = completeInfo();
        (info['management_backups'] as Map).remove(field);
        invalid.add(info);
      }
      for (final maximum in [4095, 256 * 1024 * 1024 + 1, '33554432']) {
        final info = completeInfo();
        (info['management_backups'] as Map)['max_bytes'] = maximum;
        invalid.add(info);
      }
      for (final dependency in ['management_authority', 'management_history']) {
        final info = completeInfo();
        (info['capabilities'] as List).remove(dependency);
        invalid.add(info);
      }
      final missingHistory = completeInfo()
        ..remove('management_history_available');
      invalid.add(missingHistory);
      final legacyOnly = completeInfo();
      (legacyOnly['management_backups'] as Map)['versions'] = [1];
      invalid.add(legacyOnly);
      for (final info in invalid) {
        expect(
          () => ServiceCapabilities.fromInfo(info),
          throwsA(isA<LibraryFailure>()),
        );
      }
    },
  );
}
