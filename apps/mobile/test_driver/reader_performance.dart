import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 45),
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final directory = Directory(
      Platform.environment['VV_READER_BENCH_OUTPUT']!,
    );
    if (!directory.isAbsolute || !directory.existsSync()) {
      throw StateError('Expected existing output');
    }
    await File('${directory.path}/profile-result.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(data)}\n',
      flush: true,
    );
  },
);
