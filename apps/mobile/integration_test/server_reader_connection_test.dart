import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shika/features/packs/pack_reader_page.dart';
import 'package:shika/features/packs/reader_images.dart';
import 'package:shika/library/credentials.dart';
import 'package:shika/library/server_repository.dart';
import 'package:shika/main.dart';
import 'package:shika/ui/preferences.dart';

/// Diagnostic profile entry only. The normal App never sends these reports.
Future<void> observe(Map<String, dynamic> value) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://10.0.2.2:8776/reader-connection'),
    );
    request.headers.set('X-Fixture-Key', 'reader-connection-owned-only');
    request.headers.contentType = ContentType.json;
    final bytes = utf8.encode(jsonEncode(value));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(const Duration(seconds: 20));
    expect(response.statusCode, 200);
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  testWidgets(
    'observe repeated reader commands without automatic write replay',
    (t) async {
      expect(kProfileMode, isTrue);
      final repo = ServerLibraryRepository(MemoryCredentialStore(), port: 8775);
      final prefs = UiPreferences(dark: true, preloadAdjacent: false);
      final result = <String, dynamic>{
        'diagnostic_profile_entry': true,
        'normal_release_acceptance': false,
        'original_issue100_reproduced': false,
        'cycles': <Map<String, dynamic>>[],
      };
      binding.reportData = {'reader_connection': result};
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pump();
        repo.dispose();
        prefs.dispose();
      });
      PackReaderPageState? current() =>
          find.byType(PackReaderPage).evaluate().isEmpty
          ? null
          : t.state<PackReaderPageState>(find.byType(PackReaderPage));

      Future<void> until(bool Function() ready, String why) async {
        final end = DateTime.now().add(const Duration(seconds: 45));
        while (!ready()) {
          final diagnostic = current()?.session.lastCommandFailure;
          if (diagnostic != null) {
            final failure = diagnostic.failure;
            final cause = failure.transportCause;
            final value = <String, dynamic>{
              'event': 'command_failure',
              'waiting_for': why,
              'kind': diagnostic.kind,
              'request_id': diagnostic.requestId,
              'receipt_lookup': diagnostic.receiptLookup,
              'code': failure.code,
              'status': failure.status,
              'phase': failure.transportPhase?.name,
              'cause_type': cause?.runtimeType.toString(),
              'cause_message': cause?.toString(),
              if (cause is SocketException)
                'os_error': {
                  'code': cause.osError?.errorCode,
                  'message': cause.osError?.message,
                  'address': cause.address?.address,
                  'port': cause.port,
                },
            };
            result['failure'] = value;
            debugPrint('READER_CONNECTION_FAILURE:${jsonEncode(value)}');
            await observe(value);
            // A read-only original receipt lookup is separate from resending.
            final session = current()!.session;
            await session.checkPending();
            result['after_original_query'] = {
              'pending': session.hasPending,
              'can_resend': session.canResend,
              'error': session.error,
              'original_diagnostic_retained': identical(
                diagnostic,
                session.lastCommandFailure,
              ),
            };
            fail('Captured reader command failure; no write was replayed');
          }
          if (DateTime.now().isAfter(end)) {
            fail('Reader observation timeout: $why');
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(t.takeException(), isNull);
      }

      Future<void> pause(int milliseconds) async {
        final end = DateTime.now().add(Duration(milliseconds: milliseconds));
        while (DateTime.now().isBefore(end)) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> tap(Finder target) async {
        await until(() => target.evaluate().length == 1, 'unique $target');
        await t.ensureVisible(target);
        await until(
          () => target.hitTestable().evaluate().length == 1,
          'hit $target',
        );
        await t.tap(target);
        await t.pump();
        await pause(1800);
      }

      await repo.connect(
        'http://10.0.2.2',
        8775,
        'reader-connection-owned-only',
      );
      await t.pumpWidget(
        ShikaApp(
          repository: repo,
          preferences: prefs,
          initializeRepository: false,
        ),
      );
      const idle = [0, 4800, 5200, 9500, 0, 5200, 0, 4800, 5200, 9500, 0, 5200];
      for (var cycle = 0; cycle < idle.length; cycle++) {
        await tap(find.byKey(const Key('nav-library')));
        await tap(find.byKey(const Key('kind-pack')));
        await until(
          () =>
              find.byKey(const Key('pack-continuation')).evaluate().length == 1,
          'real continuation',
        );
        await pause(idle[cycle]);
        await tap(find.byKey(const Key('pack-continuation')));
        await until(() {
          final page = current();
          if (page == null ||
              page.session.inputBlocked ||
              !page.session.opened) {
            return false;
          }
          return find
              .descendant(
                of: find.byType(ReaderImage),
                matching: find.byType(RawImage),
              )
              .evaluate()
              .any((e) => (e.widget as RawImage).image != null);
        }, 'decoded reader image and acknowledged command');
        expect(current()!.session.index, 1);
        await binding.handlePopRoute();
        await until(
          () => current() == null,
          'reader disposed after Android back',
        );
        await tap(find.byKey(const Key('nav-tags')));
        await tap(find.byKey(const Key('kind-video')));
        await until(
          () => find.text('LEGACY_ONLY').evaluate().isNotEmpty,
          'separate video tag',
        );
        expect(find.text('PACK_ONLY'), findsNothing);
        await tap(find.byKey(const Key('kind-pack')));
        await until(
          () => find.text('PACK_ONLY').evaluate().isNotEmpty,
          'separate pack tag',
        );
        expect(find.text('LEGACY_ONLY'), findsNothing);
        await tap(find.byKey(const Key('nav-settings')));
        final sample = {
          'event': 'cycle_complete',
          'cycle': cycle + 1,
          'idle_ms': idle[cycle],
        };
        (result['cycles'] as List).add(sample);
        await observe(sample);
      }
      result['bounded_sequence_completed'] = true;
      result['original_issue100_reproduced'] = false;
    },
  );
}
