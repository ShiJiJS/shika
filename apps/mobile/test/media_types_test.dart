import 'package:flutter_test/flutter_test.dart';
import 'package:shika/features/library/browse_context.dart';
import 'package:shika/library/models.dart';

void main() {
  test(
    'old root snapshots default to enabled video and typed flags roundtrip',
    () {
      final old = MediaRoot.fromJson({
        'id': 'root',
        'name': '视频',
        'path': '/media',
        'available': true,
        'lastScan': '已扫描',
      });
      expect(old.kind, MediaKind.video);
      expect(old.enabled, isTrue);
      const pack = MediaRoot(
        'pack',
        '图包',
        '/packs',
        kind: MediaKind.pack,
        enabled: false,
      );
      final restored = MediaRoot.fromJson(pack.toJson());
      expect(restored.kind, MediaKind.pack);
      expect(restored.enabled, isFalse);
      expect(restored.available, isTrue);
    },
  );

  test(
    'pack filter identity is independent of tag order and scroll position',
    () {
      final context = PackBrowseContext(
        query: PackQuery(
          folder: '/packs',
          tags: {'b', 'a'},
          search: 'cos',
          readState: PackReadState.reading,
          sort: PackSort.newest,
        ),
      );
      final reordered = PackBrowseContext(
        query: PackQuery(
          folder: '/packs',
          tags: {'a', 'b'},
          search: 'cos',
          readState: PackReadState.reading,
          sort: PackSort.newest,
        ),
      );
      expect(context.queryKey, reordered.queryKey);
      expect(
        context.copyWith(scrollOffset: 520, scrollAnchor: 'p2').queryKey,
        context.queryKey,
      );
      expect(
        context.copyWith(source: BrowseSource.tags).queryKey,
        isNot(context.queryKey),
      );
      expect(
        context
            .copyWith(
              query: context.query.copy(readState: PackReadState.completed),
            )
            .queryKey,
        isNot(context.queryKey),
      );
      expect(context.query.count, 4);
      expect(context.query.toJson().containsKey('orientation'), isFalse);
      expect(() => context.query.tags.add('c'), throwsUnsupportedError);
    },
  );
}
