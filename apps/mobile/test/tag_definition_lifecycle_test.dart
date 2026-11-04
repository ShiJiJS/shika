import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/library/tag_catalog_page.dart';
import 'package:shika/library/models.dart';
import 'package:shika/library/repository.dart';
import 'package:shika/ui/paper.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary;

class DelayedDefinitionReload extends WorkspaceLibrary {
  Completer<void>? reload;
  int reads = 0, counts = 0;

  Future<void> waitForReload() async {
    reads++;
    await reload?.future;
  }

  @override
  Future<CatalogPage<VideoTag>> loadVideoTags({
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    await waitForReload();
    return super.loadVideoTags(search: search, offset: offset, limit: limit);
  }

  @override
  Future<CatalogPage<PackTag>> loadPackTags({
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    await waitForReload();
    return super.loadPackTags(search: search, offset: offset, limit: limit);
  }

  @override
  Future<VideoPage> loadVideoEntry(
    VideoEntryScope entry, {
    int offset = 0,
    int limit = 24,
  }) {
    counts++;
    return super.loadVideoEntry(entry, offset: offset, limit: limit);
  }

  @override
  Future<CatalogPage<LibraryPack>> loadPacks(
    PackQuery query, {
    int offset = 0,
    int limit = 24,
  }) {
    counts++;
    return super.loadPacks(query, offset: offset, limit: limit);
  }
}

void main() {
  for (final kind in MediaKind.values) {
    for (final dispose in [false, true]) {
      testWidgets(
        '${kind.name} definition reload cannot recount after ${dispose ? 'disposal' : 'leaving tags'}',
        (t) async {
          final repo = DelayedDefinitionReload();
          await repo.initialize();
          addTearDown(() async {
            if (repo.reload?.isCompleted == false) repo.reload!.complete();
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            repo.dispose();
          });
          var active = true;
          late StateSetter update;
          await t.pumpWidget(
            MaterialApp(
              theme: Paper.theme,
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return TagCatalogPage(
                      repository: repo,
                      kind: kind,
                      active: active,
                      onView: (_) {},
                    );
                  },
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          final page = t.state<TagCatalogPageState>(
            find.byType(TagCatalogPage),
          );
          unawaited(page.form());
          await t.pumpAndSettle();
          repo.reload = Completer<void>();
          final beforeReads = repo.reads;
          await t.tap(find.byTooltip('关闭面板'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 500));
          await t.pump();
          expect(repo.reads, beforeReads + 1);
          expect(page.loading, isTrue);
          final beforeCounts = repo.counts;
          if (dispose) {
            await t.pumpWidget(const SizedBox());
          } else {
            update(() => active = false);
            await t.pump();
          }
          repo.reload!.complete();
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(repo.counts, beforeCounts);
        },
      );
    }
  }
}
