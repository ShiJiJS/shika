import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/packs/pack_purge_result.dart';
import 'package:shika/features/packs/pack_purge_review.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/library/models.dart';
import 'package:shika/ui/paper.dart';

import 'support/pack_purge_fixture.dart';
import 'support/reveal_action.dart';

class _Repository extends PurgeLibrary {
  _Repository() : super(count: 27);
  bool failImages = false, failResults = false;
  final imageOffsets = <int>[], resultOffsets = <int>[];
  @override
  PackPurgeGateway createPackPurge() => _Gateway(this);
}

class _Gateway extends PurgeGateway {
  _Gateway(this.source) : super(source);
  final _Repository source;
  @override
  Future<PackPurgePlan> prepare(String requestId, List<String> ids) async {
    await super.prepare(requestId, ids);
    final data = purgePlanJson(ids);
    (data['result'] as Map)['image_count'] = 102;
    (data['result'] as Map)['image_bytes'] = 10200;
    (data['items'] as List).single['image_count'] = 102;
    (data['items'] as List).single['image_bytes'] = 10200;
    return source.prepared[requestId] = PackPurgePlan(data);
  }

  @override
  Future<CatalogPage<PackPurgeImage>> images(
    PackPurgePlan plan,
    PackPurgeMember member, {
    int offset = 0,
    int limit = 100,
  }) async {
    source.imageOffsets.add(offset);
    if (source.failImages) {
      throw const LibraryFailure('图片分页读取失败，原页保留');
    }
    return CatalogPage(
      items: [
        for (var i = offset; i < 102 && i < offset + limit; i++)
          PackPurgeImage({
            'id': 'image-$i',
            'path': '${member.path}/子目录/原图${i + 1}.jpg',
            'relative_path': '子目录/原图${i + 1}.jpg',
            'size': 100,
            'sha256': purgeHash,
            'signature': [
              '37',
              '33837',
              100,
              '1792884555250765506',
              '1792884555250765506',
            ],
          }, member),
      ],
      total: 102,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<CatalogPage<PackPurgeStep>> steps(
    String operationId, {
    int offset = 0,
    int limit = 24,
    bool unfinished = true,
  }) async {
    source.resultOffsets.add(offset);
    if (source.failResults) {
      throw const LibraryFailure('图片结果读取失败，原页保留');
    }
    final total = unfinished ? 54 : 81;
    return CatalogPage(
      items: [
        for (var i = offset; i < total && i < offset + limit; i++)
          PackPurgeStep({
            'id': 'step-$i',
            'pack_id': 'pack-${i ~/ (unfinished ? 2 : 3)}',
            'pack_name': '图包${i ~/ (unfinished ? 2 : 3) + 1}',
            'kind': 'image',
            'relative_path': '${i % (unfinished ? 2 : 3) + 1}.jpg',
            'phase': !unfinished && i % 3 == 0 ? 'committed' : 'prepared',
            'outcome': !unfinished && i % 3 == 0 ? 'succeeded' : 'failed',
            'error': null,
          }),
      ],
      total: total,
      offset: offset,
      limit: limit,
    );
  }
}

void main() {
  for (final profile in [
    (390.0, 844.0, 1.0),
    (360.0, 740.0, 2.0),
    (844.0, 390.0, 1.0),
    (844.0, 390.0, 2.0),
  ]) {
    Future<_Repository> host(
      WidgetTester t,
      Widget Function(_Repository) content,
    ) async {
      final repo = _Repository();
      await repo.initialize();
      t.view.physicalSize = Size(profile.$1, profile.$2);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = profile.$3;
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        repo.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme,
          home: Scaffold(body: content(repo)),
        ),
      );
      await t.pumpAndSettle();
      return repo;
    }

    Future<void> tap(WidgetTester t, Finder target) async {
      await revealAction(t, target);
      await t.tap(target);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    testWidgets(
      'exact images use one full page, retain page on failure and preserve unconfirmed review $profile',
      (t) async {
        final repo = await host(
          t,
          (repo) => Builder(
            builder: (context) => TextButton(
              onPressed: () => showPackPurgeReview(context, repo, ['trash-0']),
              child: const Text('打开复核'),
            ),
          ),
        );
        await tap(t, find.text('打开复核'));
        final submit = find.byKey(const Key('pack-purge-submit'));
        expect(t.widget<FilledButton>(submit).onPressed, isNull);
        await tap(t, find.text('查看图包和图片清单'));
        await tap(t, find.text('海边散步图包 trash-0'));
        await revealAction(t, find.text('子目录/原图50.jpg'));
        await revealAction(t, find.text('子目录/原图100.jpg'));
        expect(find.text('海边散步图包 trash-0').hitTestable(), findsNothing);
        repo.failImages = true;
        await tap(t, find.text('下一页'));
        expect(find.byKey(const Key('purge-images-error')), findsOneWidget);
        await revealAction(t, find.text('子目录/原图1.jpg'));
        expect(repo.imageOffsets.last, 100);
        repo.failImages = false;
        await tap(t, find.text('重新读取'));
        expect(repo.imageOffsets.last, 0);
        await revealAction(t, find.text('子目录/原图50.jpg'));
        await tap(t, find.text('下一页'));
        await revealAction(t, find.text('子目录/原图101.jpg'));
        expect(repo.imageOffsets.last, 100);
        expect(find.text('子目录/原图102.jpg'), findsOneWidget);
        await tap(t, find.byTooltip('返回图包清单'));
        await tap(t, find.byTooltip('返回删除复核'));
        expect(
          t
              .widget<CheckboxListTile>(
                find.byKey(const Key('pack-purge-confirmation')),
              )
              .value,
          isFalse,
        );
        expect(t.widget<FilledButton>(submit).onPressed, isNull);
        await tap(t, find.text('取消'));
        expect(repo.physicalPosts, isEmpty);
        expect(repo.preparations, hasLength(1));
      },
    );
    testWidgets(
      'partial result pages scroll together, retain old page after error and expose original retry $profile',
      (t) async {
        final repo = await host(
          t,
          (repo) => Builder(
            builder: (context) => TextButton(
              onPressed: () {
                final raw = purgeTaskJson(
                  List.generate(27, (i) => 'trash-$i'),
                  failed: true,
                );
                repo.receipts['purge-op'] = raw;
                showPackPurgeResult(
                  context,
                  repo,
                  repo.createPackFiles(),
                  PackFileTask.fromJson(raw),
                );
              },
              child: const Text('打开结果'),
            ),
          ),
        );
        await tap(t, find.text('打开结果'));
        expect(find.text('已确认删除 27/81 张'), findsOneWidget);
        await tap(t, find.text('下一页'));
        expect(repo.resultOffsets.last, 24);
        await revealAction(t, find.text('图包13 · 1.jpg'));
        repo.failResults = true;
        await tap(t, find.text('查询原结果'));
        expect(find.byKey(const Key('purge-result-error')), findsOneWidget);
        await revealAction(t, find.text('图包13 · 1.jpg'));
        repo.failResults = false;
        await tap(t, find.text('查询原结果'));
        expect(repo.resultOffsets.last, 0);
        await tap(t, find.text('全部'));
        await revealAction(t, find.text('共 81 项'));
        await revealAction(t, find.text('重试原任务'));
        expect(find.text('重试原任务').hitTestable(), findsOneWidget);
        await tap(t, find.text('关闭'));
        expect(repo.physicalPosts, isEmpty);
      },
    );
  }
}
