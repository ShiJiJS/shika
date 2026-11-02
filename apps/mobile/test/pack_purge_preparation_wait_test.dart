import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_purge_review.dart';
import 'package:video_viewer/features/packs/pack_purge_review_session.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/server_api.dart';
import 'package:video_viewer/ui/paper.dart';

import 'support/pack_purge_fixture.dart';

class SlowLibrary extends PurgeLibrary {
  bool complete = false, losePost = false;
  int processed = 0, readFailures = 0, planReads = 0, receiptReads = 0;
  final requests = <String, List<String>>{};
  int preparationPosts = 0;
  @override
  PackPurgeGateway createPackPurge() => SlowGateway(this);
  PackPurgePlan value(List<String> ids) {
    final raw = purgePlanJson(ids, expired: expired);
    if (!complete) {
      raw['status'] = 'running';
      raw['ready'] = false;
      raw['digest'] = null;
      for (final (index, member) in (raw['items'] as List).indexed) {
        if (index >= processed) {
          member['digest'] = null;
          member['image_count'] = 0;
          member['image_bytes'] = 0;
        }
      }
    }
    return PackPurgePlan(raw);
  }

  void read() {
    if (readFailures > 0) {
      readFailures--;
      throw const ApiFailure('连接超时，请检查服务后重试', code: 'timeout');
    }
  }
}

class SlowGateway extends PurgeGateway {
  SlowGateway(this.slow) : super(slow);
  final SlowLibrary slow;
  @override
  Future<PackPurgePlan> prepare(String requestId, List<String> trashIds) async {
    slow.preparationPosts++;
    slow.requests[requestId] = List.of(trashIds);
    if (slow.losePost) {
      slow.losePost = false;
      throw const ApiFailure('连接超时，请检查服务后重试', code: 'timeout');
    }
    return slow.value(trashIds);
  }

  @override
  Future<PackPurgePlan?> receipt(String requestId) async {
    slow.receiptReads++;
    slow.read();
    final ids = slow.requests[requestId];
    return ids == null ? null : slow.value(ids);
  }

  @override
  Future<PackPurgePlan> plan(String id) async {
    slow.planReads++;
    slow.read();
    return slow.value(slow.requests.values.last);
  }
}

void main() {
  test(
    'a slow preparation continues beyond the former 25 second wait',
    () async {
      final repo = SlowLibrary();
      final review = PackPurgeReviewSession(repo.createPackPurge(), [
        'trash-0',
      ]);
      addTearDown(review.dispose);
      addTearDown(repo.dispose);
      final pending = review.load(submit: true);
      await Future<void>.delayed(const Duration(seconds: 26));
      expect(review.busy, isTrue);
      expect(repo.planReads, greaterThanOrEqualTo(12));
      expect(review.error, isEmpty);
      expect(review.canConfirm, isFalse);
      expect(() => review.authorize(), throwsA(isA<LibraryFailure>()));
      repo.complete = true;
      await pending.timeout(const Duration(seconds: 4));
      expect(review.canConfirm, isTrue);
      expect(review.checked, isFalse);
      expect(repo.preparationPosts, 1);
      expect(repo.physicalPosts, isEmpty);
    },
  );

  testWidgets(
    'lost submission reply and transient reads recover only the original key',
    (t) async {
      final repo = SlowLibrary()..losePost = true;
      final review = PackPurgeReviewSession(repo.createPackPurge(), [
        'trash-0',
      ]);
      final pending = review.load(submit: true);
      await t.pump();
      final key = review.requestId;
      expect(review.waitingMessage, contains('查询原清单'));
      repo.readFailures = 1;
      await t.pump(const Duration(seconds: 5));
      expect(review.error, isEmpty);
      expect(review.waitingMessage, contains('连接暂时不稳定'));
      repo.complete = true;
      await t.pump(const Duration(seconds: 5));
      await pending;
      expect(review.requestId, key);
      expect(repo.requests.keys, [key]);
      expect(repo.preparationPosts, 1);
      expect(review.canConfirm, isTrue);
      expect(review.checked, isFalse);
      expect(repo.physicalPosts, isEmpty);
      review.dispose();
      repo.dispose();
    },
  );

  testWidgets(
    'saved batch reopens its original running preparation without another POST',
    (t) async {
      final repo = SlowLibrary();
      PackPurgeReviewSession open(List<String> ids) => PackPurgeReviewSession(
        repo.createPackPurge(),
        ids,
        selectionId: 'saved-choice',
      );
      final first = open(['trash-1', 'trash-0']);
      final waiting = first.load(submit: true);
      await t.pump();
      final key = first.requestId;
      first.dispose();
      await t.pump(const Duration(seconds: 2));
      await waiting;
      final second = open(['trash-0', 'trash-1']);
      final resumed = second.load(submit: true);
      await t.pump();
      expect(second.requestId, key);
      expect(repo.preparationPosts, 1);
      expect(second.busy, isTrue);
      expect(second.canRenew, isFalse);
      repo.complete = true;
      await t.pump(const Duration(seconds: 2));
      await resumed;
      expect(second.canConfirm, isTrue);
      expect(second.checked, isFalse);
      expect(repo.physicalPosts, isEmpty);
      second.dispose();
      repo.dispose();
    },
  );

  testWidgets(
    'cancelling during network recovery stops reads and cannot authorize',
    (t) async {
      final repo = SlowLibrary()..losePost = true;
      final review = PackPurgeReviewSession(repo.createPackPurge(), [
        'trash-0',
      ]);
      final pending = review.load(submit: true);
      await t.pump();
      review.dispose();
      repo.complete = true;
      await t.pump(const Duration(seconds: 5));
      await pending;
      expect(repo.receiptReads, 0);
      expect(review.plan, isNull);
      expect(() => review.authorize(), throwsA(isA<LibraryFailure>()));
      expect(repo.physicalPosts, isEmpty);
      repo.dispose();
    },
  );

  test('renewed request survives a fresh journal reader and reopening still only queries', () async {
    final repo = SlowLibrary()..complete = true;
    final selected = PackPurgeSelections(repo.createPackFiles());
    final saved = await selected.save(['trash-0']);
    PackPurgeReviewSession open() => PackPurgeReviewSession(
      repo.createPackPurge(),
      saved.ids,
      selectionId: saved.id,
      requestIdentity: (replace) =>
          PackPurgeSelections(repo.createPackFiles())
              .reviewRequest(saved.id, saved.ids, replace: replace),
    );
    final first = open();
    await first.load(submit: true);
    final original = first.requestId;
    await first.load(renew: true);
    final renewed = first.requestId;
    expect(renewed, isNot(original));
    first.dispose();
    final second = open();
    await second.load(submit: true);
    expect(second.requestId, renewed);
    expect(repo.preparationPosts, 2);
    expect(second.canConfirm, isTrue);
    expect(second.checked, isFalse);
    expect(repo.physicalPosts, isEmpty);
    second.dispose();
    repo.dispose();
  });

  for (final sample in [(390.0, 844.0, 1.0), (360.0, 640.0, 2.0)]) {
    testWidgets(
      'large batch progress and cancel fit ${sample.$1}/${sample.$3}',
      (t) async {
        final repo = SlowLibrary()..processed = 123;
        t.view.physicalSize = Size(sample.$1, sample.$2);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = sample.$3;
        final ids = List.generate(622, (i) => 'trash-$i');
        final saved = await PackPurgeSelections(repo.createPackFiles())
            .save(ids);
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPackPurgeReview(
                    context,
                    repo,
                    ids,
                    selectionId: saved.id,
                  ),
                  child: const Text('核对'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('核对'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('已核对 123 / 622 个图包'), findsOneWidget);
        expect(find.text('已核对 369 张图片'), findsOneWidget);
        expect(find.text('重新准备'), findsNothing);
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('pack-purge-submit')))
              .onPressed,
          isNull,
        );
        expect(repo.physicalPosts, isEmpty);
        expect(t.takeException(), isNull);
        await t.tap(find.text('取消'));
        await t.pump();
        await t.pump(const Duration(seconds: 6));
        expect(find.byType(PackPurgeReview), findsNothing);
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      },
    );
  }
}
