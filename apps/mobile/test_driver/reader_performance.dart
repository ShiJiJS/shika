import 'dart:io';
import 'dart:convert';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

Future<void> main() async {
  final directory = Directory(Platform.environment['VV_READER_BENCH_OUTPUT']!);
  if (!directory.isAbsolute || !directory.existsSync()) {
    throw StateError('Expected existing output');
  }
  final driver = await FlutterDriver.connect();
  late Response response;
  try {
    response = Response.fromJson(
      await driver.requestData(null, timeout: const Duration(minutes: 65)),
    );
    // Publish the terminal report before closing the driver. flutter drive may
    // stop the App on close; the passive /proc observer needs this boundary.
    final temporary = File('${directory.path}/profile-result.json.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(response.data)}\n',
      flush: true,
    );
    await temporary.rename('${directory.path}/profile-result.json');
  } finally {
    await driver.close();
  }
  if (response.allTestsPassed) {
    stdout.writeln('All tests passed.');
  } else {
    stdout.writeln('Failure Details:\n${response.formattedFailureDetails}');
  }
  exit(response.allTestsPassed ? 0 : 1);
}
