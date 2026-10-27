import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_viewer/features/packs/pack_reader_page.dart';
import 'package:video_viewer/library/models.dart';
import 'package:video_viewer/library/repository.dart';
import 'package:video_viewer/ui/paper.dart';

import 'media_workspace_widget_test.dart' show WorkspaceLibrary;

class AssetReadingLibrary extends WorkspaceLibrary {
  MediaSource Function(String packId, int index)? pageImage;
  MediaSource Function(String packId, int index)? pageThumbnail;
  final prefs = <String, ReaderPreferences>{};
  final marks = <String, ReaderMark>{};
  final revisions = <String, int>{};
  int openedCount = 0, scopes = 0;
  Completer<void>? preferenceStarted, preferenceRelease;
  @override
  ServiceCapabilities get capabilities => ServiceCapabilities([
    'image_packs',
    'pack_tags',
    'pack_reading_sessions',
  ]);
  @override
  PackReader createPackReader() => _AssetReader(this);
}

class _AssetReader implements PackReader {
  _AssetReader(this.repo);
  final AssetReadingLibrary repo;
  bool alive = true;
  String selected = 'p0', identity = '';
  int revision = 0;
  @override
  bool get isCurrent => alive;
  ReaderPreferences get preferences =>
      repo.prefs[selected] ?? const ReaderPreferences();
  ReaderPage page(int index) => ReaderPage(
    id: '$selected-$index',
    packId: selected,
    name: '${index + 1}.jpg',
    ordinal: index,
    width: 400,
    height: 600,
    version: 1,
    image:
        repo.pageImage?.call(selected, index) ??
        const MediaSource('assets/media/flower-portrait.jpg', asset: true),
    thumbnail:
        repo.pageThumbnail?.call(selected, index) ??
        const MediaSource('assets/media/flower-portrait.jpg', asset: true),
  );
  ReaderState get state {
    final mark = repo.marks[selected] ?? ReaderMark('$selected-0');
    final index = int.parse(mark.pageId.split('-').last);
    return ReaderState(
      page: page(index),
      pageIndex: index,
      mark: mark,
      revision: repo.revisions[selected] ?? 0,
      version: 1,
      preferences: preferences,
      sessionRevision: revision,
    );
  }

  LibraryPack get pack => LibraryPack(
    id: selected,
    rootId: 'root',
    path: '/packs/$selected',
    name: '阅读图包${selected.substring(1)}',
    pageCount: 3,
    readableCount: 3,
    contentVersion: 1,
    status: 'available',
    createdAt: 1,
  );
  PackReadingRange get range => PackReadingRange(
    id: identity,
    revision: revision,
    candidateCount: 2,
    availableCount: 2,
    cursor: selected == 'p0' ? 0 : 1,
    finished: false,
    pack: pack,
    resume: state,
    source: BrowseSource.library,
    random: false,
    previous: selected == 'p1' ? const ReaderNeighbor('p0', 0) : null,
    next: selected == 'p0' ? const ReaderNeighbor('p1', 1) : null,
  );
  @override
  Future<T> submit<T>(ReaderCommand<T> command) async {
    final Object result;
    switch (command) {
      case final CreatePackReading value:
        identity = 'range-${repo.scopes++}';
        selected = value.entry.anchorId ?? 'p0';
        result = range;
        break;
      case final OpenPackReading value:
        repo.openedCount++;
        repo.marks[selected] ??= ReaderMark(value.pageId);
        repo.revisions[selected] = (repo.revisions[selected] ?? 0) + 1;
        result = state;
        break;
      case final WritePackProgress value:
        repo.marks[selected] = value.mark;
        repo.revisions[selected] = (repo.revisions[selected] ?? 0) + 1;
        result = state;
        break;
      case final WritePackPreferences value:
        if (repo.preferenceStarted != null &&
            !repo.preferenceStarted!.isCompleted) {
          repo.preferenceStarted!.complete();
        }
        if (repo.preferenceRelease != null) {
          await repo.preferenceRelease!.future;
        }
        final p = value.preferences;
        repo.prefs[selected] = ReaderPreferences(
          mode: p.mode,
          direction: p.direction,
          gap: p.gap,
          fit: p.fit,
          revision: p.revision + 1,
          overridden: true,
        );
        result = preferences;
        break;
      case final MovePackReading value:
        selected = value.packId!;
        revision++;
        result = range;
        break;
      case WriteReaderDefaults():
        throw UnimplementedError();
    }
    return result as T;
  }

  @override
  Future<T?> receipt<T>(ReaderCommand<T> command) async => null;
  @override
  Future<PackReadingRange> read(String id) async => range;
  @override
  Future<PackManifest> pages(
    String id, {
    required int version,
    int offset = 0,
    int limit = 40,
  }) async => PackManifest(
    pages: [for (var i = offset; i < 3 && i < offset + limit; i++) page(i)],
    packId: selected,
    version: 1,
    total: 3,
    offset: offset,
    limit: limit,
  );
  @override
  Future<ReaderQueuePage> queue(
    String id, {
    int offset = 0,
    int limit = 40,
  }) async => ReaderQueuePage(
    entries: [],
    total: 2,
    offset: offset,
    limit: limit,
    revision: revision,
  );
  @override
  Future<ReaderPreferences> defaults() async => const ReaderPreferences();
  @override
  void cancelMetadata() {}
  @override
  void cancelPages() {}
  @override
  void cancelQueue() {}
  @override
  void dispose() {
    alive = false;
  }
}

void main() {
  for (final sample in [
    (const Size(390, 844), 1.0),
    (const Size(360, 740), 2.0),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets(
      'reader actual asset frames, mode change, saved resume and layout ${sample.$1} / ${sample.$2}',
      (t) async {
        final repo = AssetReadingLibrary();
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = sample.$1;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          repo.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await t.pumpWidget(
          MaterialApp(
            theme: Paper.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(sample.$2),
                gestureSettings: const DeviceGestureSettings(touchSlop: 8),
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PackReaderPage(
                          repository: repo,
                          entry: PackReadingEntry(PackQuery(), anchorId: 'p0'),
                          editTags: (_) async {},
                        ),
                      ),
                    ),
                    child: const Text('打开图包'),
                  ),
                ),
              ),
            ),
          ),
        );
        PackReaderPageState state() =>
            t.state<PackReaderPageState>(find.byType(PackReaderPage));
        Future<void> until(bool Function() condition) async {
          for (var i = 0; i < 150; i++) {
            await t.pump(const Duration(milliseconds: 30));
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 3)),
            );
            expect(t.takeException(), isNull);
            if (condition()) return;
          }
          fail('Reader did not reach expected state');
        }

        Future<void> tap(Finder finder) async {
          await t.pump(const Duration(milliseconds: 500));
          await t.ensureVisible(finder);
          await t.pump(const Duration(milliseconds: 500));
          expect(finder.hitTestable(), findsOneWidget);
          await t.tap(finder);
          await t.pump(const Duration(milliseconds: 500));
        }

        await tap(find.text('打开图包'));
        await until(
          () =>
              find.byType(PackReaderPage).evaluate().isNotEmpty &&
              state().session.opened &&
              !state().session.busy,
        );
        await t.pump(const Duration(milliseconds: 500));
        expect(repo.openedCount, 1);
        final compact = sample.$1.width > sample.$1.height;
        if (compact) {
          // The picture uses the full reading surface; chrome floats over it.
          final canvas = t.getRect(find.byKey(const Key('reader-canvas')));
          expect(canvas.top, 0);
          expect(canvas.height, sample.$1.height);
          expect(find.byKey(const Key('reader-tools')), findsNothing);
          expect(find.byKey(const Key('reader-scope')), findsNothing);
          final actions = t.getRect(find.byKey(const Key('reader-controls')));
          expect(actions.width, lessThan(sample.$1.width / 2));
          expect(actions.bottom, lessThanOrEqualTo(canvas.bottom));
          await tap(find.byTooltip('图包更多'));
          await tap(find.text('页码总览'));
          expect(
            find.byKey(const Key('reader-overview-sheet')),
            findsOneWidget,
          );
          await t.binding.handlePopRoute();
          await t.pumpAndSettle();
          expect(state().session.index, 0);
          expect(repo.openedCount, 1);
        }
        final horizontal = find.byKey(const Key('reader-horizontal'));
        expect(horizontal, findsOneWidget);
        final hold = await t.startGesture(t.getCenter(horizontal));
        await hold.moveBy(Offset(-sample.$1.width * .25, 0));
        await t.pump(const Duration(milliseconds: 30));
        final pager = t.widget<PageView>(horizontal).controller!;
        expect(pager.page, greaterThan(.05));
        expect(pager.page, lessThan(.5));
        await hold.up();
        await until(() => (pager.page ?? 1).abs() < .001);
        expect(state().session.index, 0);
        await t.drag(horizontal, Offset(-sample.$1.width * .65, 0));
        await until(
          () => state().session.index == 1 && state().session.unsaved,
        );
        expect(await state().session.flush(), isTrue);
        await t.drag(horizontal, Offset(sample.$1.width * .65, 0));
        await until(
          () => state().session.index == 0 && state().session.unsaved,
        );
        expect(await state().session.flush(), isTrue);
        await tap(find.byTooltip('阅读设置'));
        await tap(find.byType(DropdownButtonFormField<ReaderDirection>));
        await tap(find.text('从右向左').last);
        await until(
          () =>
              state().session.preferences.direction == ReaderDirection.rtl &&
              !state().session.busy,
        );
        await tap(find.text('继续阅读'));
        expect(t.widget<PageView>(horizontal).reverse, isTrue);
        await t.drag(horizontal, Offset(sample.$1.width * .65, 0));
        await until(
          () => state().session.index == 1 && state().session.unsaved,
        );
        expect(await state().session.flush(), isTrue);
        await t.drag(horizontal, Offset(-sample.$1.width * .65, 0));
        await until(
          () => state().session.index == 0 && state().session.unsaved,
        );
        expect(await state().session.flush(), isTrue);
        final center = t.getCenter(horizontal);
        final left = await t.startGesture(center - const Offset(30, 0));
        final right = await t.startGesture(center + const Offset(30, 0));
        await t.pump(const Duration(milliseconds: 50));
        for (var i = 1; i <= 4; i++) {
          await left.moveTo(center - Offset(30 + i * 15, 0));
          await right.moveTo(center + Offset(30 + i * 15, 0));
          await t.pump(const Duration(milliseconds: 30));
        }
        await until(() => state().zoomed);
        await left.up();
        await right.up();
        await t.pump(const Duration(milliseconds: 200));
        await t.drag(horizontal, const Offset(-140, 0));
        await t.pump(const Duration(milliseconds: 300));
        expect(
          state().session.index,
          0,
          reason: 'pinch and zoom pan cannot flip',
        );
        await t.binding.handlePopRoute();
        await until(() => !state().zoomed);
        expect(find.byType(PackReaderPage), findsOneWidget);
        expect(state().controls, isTrue);
        await tap(find.byTooltip('下一张'));
        await until(
          () => state().session.index == 1 && state().session.unsaved,
        );
        expect(await state().session.flush(), isTrue);
        await tap(find.byTooltip('阅读设置'));
        await until(
          () => find.text('纵向拼接').hitTestable().evaluate().isNotEmpty,
        );
        await tap(find.text('纵向拼接'));
        await until(
          () =>
              state().session.preferences.mode == ReaderMode.vertical &&
              !state().session.busy,
        );
        await tap(find.text('继续阅读'));
        await until(() => find.text('继续阅读').evaluate().isEmpty);
        await t.drag(
          find.byKey(const Key('reader-vertical')),
          const Offset(0, -80),
        );
        await until(
          () => state().session.index == 1 && state().session.offsetRatio > .04,
        );
        final ratio = state().session.offsetRatio;
        expect(state().session.unsaved, isTrue);
        final beforePause = repo.revisions['p0']!;
        final pausedAt = t.binding.clock.now();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await t.pump();
        // No fake-clock time advances: the 700ms autosave cannot satisfy this.
        expect(t.binding.clock.now(), pausedAt);
        expect(state().session.unsaved, isFalse);
        expect(repo.revisions['p0'], greaterThan(beforePause));
        expect(repo.marks['p0']!.offsetRatio, closeTo(ratio, .02));
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        expect(await state().session.flush(), isTrue);
        expect(repo.marks['p0']!.pageId, 'p0-1');
        final pageId = state().session.currentPage!.id;
        // Reflow the actual live reader, including a partially read strip.
        t.view.physicalSize = compact
            ? const Size(390, 844)
            : const Size(844, 390);
        await until(
          () =>
              state().session.currentPage?.id == pageId &&
              (state().session.offsetRatio - ratio).abs() < .02,
        );
        await t.pump(const Duration(milliseconds: 500));
        expect(state().session.currentPage!.id, pageId);
        expect(state().session.offsetRatio, closeTo(ratio, .02));
        expect(repo.openedCount, 1);
        expect(repo.scopes, 1);
        t.view.physicalSize = sample.$1;
        await until(() => (state().session.offsetRatio - ratio).abs() < .02);
        await tap(find.byTooltip('返回来源'));
        await until(() => find.byType(PackReaderPage).evaluate().isEmpty);
        await tap(find.text('打开图包'));
        await until(
          () =>
              find.byType(PackReaderPage).evaluate().isNotEmpty &&
              state().session.opened &&
              !state().session.busy,
        );
        expect(state().session.index, 1);
        expect(state().session.preferences.mode, ReaderMode.vertical);
        expect(state().session.offsetRatio, closeTo(ratio, .02));
        expect(repo.openedCount, 2);
        expect(repo.scopes, 2);
        expect(t.takeException(), isNull);
      },
    );
  }
}
