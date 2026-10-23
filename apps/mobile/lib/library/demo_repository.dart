import 'dart:convert';
import 'dart:math';

import 'models.dart';
import 'repository.dart';
import 'state_store.dart';

LibrarySnapshot demoSeed() {
  LibraryVideo v(
    String id,
    String path,
    bool portrait,
    List<String> tags, {
    String? poster,
    VideoStatus status = VideoStatus.available,
  }) => LibraryVideo(
    id: id,
    path: path,
    rootId: path.startsWith('/videos/') ? 'r1' : 'r2',
    portrait: portrait,
    tags: tags,
    status: status,
    source: MediaSource(
      'assets/media/flower-${portrait ? 'portrait' : 'landscape'}.mp4',
    ),
    poster:
        'assets/media/${poster ?? 'flower-${portrait ? 'portrait' : 'landscape'}'}.jpg',
  );
  return LibrarySnapshot(
    videos: [
      v('v1', '/videos/收集/花草/竖版/花间微风_02.mp4', true, ['自然', '花卉']),
      v('v2', '/videos/收集/花草/横版/庭院片段_01.mp4', false, ['自然', '花卉', '庭院']),
      v('v3', '/videos/收集/花草/竖版/花苞近景_03.mp4', true, [
        '自然',
        '微距',
      ], poster: 'portrait-late'),
      v('v4', '/videos/旅行/公园/公园花草_04.mp4', false, [
        '自然',
        '花卉',
        '散步',
      ], poster: 'landscape-late'),
      v('v5', '/collection/新收藏/庭院随拍_05.mp4', true, [
        '庭院',
      ], poster: 'portrait-early'),
      v('v6', '/collection/新收藏/植物细节_06.mp4', false, [
        '自然',
        '微距',
      ], poster: 'landscape-early'),
      v('v7', '/videos/收集/去年花开_07.mp4', true, [
        '自然',
        '花卉',
      ], status: VideoStatus.missing),
      v('v8', '/videos/收集/窗边花草_08.mp4', false, [
        '庭院',
      ], status: VideoStatus.trash),
    ],
    roots: const [
      MediaRoot('r1', '视频收藏', '/videos'),
      MediaRoot('r2', '收集目录', '/collection'),
    ],
    tags: const ['自然', '花卉', '庭院', '微距', '散步'],
    query: VideoQuery(),
    round: const ['v1', 'v3', 'v2', 'v5', 'v4', 'v6'],
  );
}

class DemoLibraryRepository extends LibraryRepository implements DemoControls {
  DemoLibraryRepository(
    this.store, {
    this._scenario = DemoScenario.normal,
    this.latency = const Duration(milliseconds: 220),
  });
  final StateStore store;
  final Duration latency;
  DemoScenario _scenario;
  LibrarySnapshot _state = demoSeed();
  Future<void> _queue = Future.value();
  int _scanRetries = 0;
  @override
  LibrarySnapshot get snapshot => _state;
  @override
  DemoScenario get scenario => _scenario;

  bool _matches(LibraryVideo v, VideoQuery q, [LibrarySnapshot? state]) {
    final s = state ?? _state;
    return v.status == VideoStatus.available &&
        s.roots.any(
          (r) =>
              r.id == v.rootId &&
              r.available &&
              r.enabled &&
              r.kind == MediaKind.video,
        ) &&
        (q.folder.isEmpty || under(v.path, q.folder)) &&
        v.tags.containsAll(q.tags) &&
        (q.orientation.isEmpty ||
            (q.orientation == 'portrait') == v.portrait) &&
        (q.duration.isEmpty ||
            (q.duration == 'short' ? v.seconds <= 10 : v.seconds > 10)) &&
        (q.type.isEmpty || q.type == v.type);
  }

  @override
  List<LibraryVideo> query({
    VideoQuery? scope,
    String search = '',
    int offset = 0,
    int limit = 100000,
  }) => _state.videos
      .where(
        (v) =>
            _matches(v, scope ?? _state.query) &&
            v.name.toLowerCase().contains(search.toLowerCase()),
      )
      .skip(offset)
      .take(limit)
      .toList();
  @override
  LibraryVideo? get current {
    if (_state.round.isEmpty) return null;
    final id = _state.round[_state.position];
    return _state.videos
        .where((v) => v.id == id && _matches(v, _state.query))
        .firstOrNull;
  }

  @override
  List<FolderEntry> folders(String parent) {
    if (parent.isEmpty) {
      return _state.roots
          .where((r) => r.kind == MediaKind.video)
          .map(
            (r) => FolderEntry(
              r.name,
              r.path,
              available: r.available && r.enabled,
            ),
          )
          .toList();
    }
    if (!_state.roots.any((r) => under(parent, r.path))) {
      throw const LibraryFailure('只能选择已挂载媒体目录内的文件夹');
    }
    final paths = <String>{};
    for (final v in _state.videos) {
      final dir = v.path.substring(0, v.path.lastIndexOf('/'));
      if (dir.startsWith('$parent/')) {
        paths.add(
          '$parent/${dir.substring(parent.length + 1).split('/').first}',
        );
      }
    }
    return (paths.toList()..sort())
        .map((p) => FolderEntry(basename(p), p))
        .toList();
  }

  String _encode(LibrarySnapshot s) => jsonEncode({
    'format': 'video-viewer-flutter-demo',
    'version': 1,
    'data': s.toJson(),
  });
  LibrarySnapshot _round(LibrarySnapshot s) {
    final items = s.videos.where((v) => _matches(v, s.query, s)).toList();
    if (s.order == PlayOrder.random) {
      items.shuffle(Random());
    } else {
      items.sort((a, b) => a.path.compareTo(b.path));
    }
    return s.copy(round: items.map((v) => v.id), position: 0);
  }

  LibrarySnapshot _reconcile(LibrarySnapshot s) {
    final id = s.round.isEmpty ? null : s.round[s.position];
    final round = s.round
        .where(
          (id) => s.videos.any((v) => v.id == id && _matches(v, s.query, s)),
        )
        .toList();
    final index = round.indexOf(id ?? '');
    return s.copy(
      round: round,
      position: round.isEmpty
          ? 0
          : index >= 0
          ? index
          : min(s.position, round.length - 1),
    );
  }

  Future<void> _commit(
    LibrarySnapshot Function(LibrarySnapshot) update, {
    bool fileOperation = false,
  }) {
    final result = _queue.then((_) async {
      await Future<void>.delayed(latency);
      if (fileOperation && _scenario == DemoScenario.writeFailure) {
        throw const LibraryFailure('操作失败：目录没有写入权限，视频仍在原位置');
      }
      final next = update(_state);
      if (_scenario == DemoScenario.storageFailure) {
        throw const LibraryFailure('保存失败，修改未生效，请重试');
      }
      try {
        await store.write(_encode(next));
      } catch (_) {
        throw const LibraryFailure('保存失败，修改未生效，请重试');
      }
      _state = next;
      notifyListeners();
    });
    _queue = result.then<void>((_) {}, onError: (Object e, StackTrace st) {});
    return result;
  }

  @override
  Future<void> initialize() async {
    final saved = await store.read();
    if (saved != null) _state = BackupPreview.parse(saved).snapshot;
    _state = _reconcile(_state);
    _applyScenario();
    notifyListeners();
  }

  void _applyScenario() {
    if (_scenario == DemoScenario.empty) {
      _state = _state.copy(videos: [], round: [], position: 0);
    }
    if (_scenario == DemoScenario.offline) {
      _state = _state.copy(connected: false);
    }
    if (_scenario == DemoScenario.unavailable) {
      _state = _reconcile(
        _state.copy(
          roots: _state.roots.map(
            (r) => MediaRoot(
              r.id,
              r.name,
              r.path,
              available: r.id != 'r2',
              kind: r.kind,
              enabled: r.enabled,
              lastScan: r.lastScan,
            ),
          ),
        ),
      );
    }
  }

  @override
  Future<void> reset({DemoScenario scenario = DemoScenario.normal}) async {
    await _queue;
    _scanRetries = 0;
    _scenario = scenario;
    _state = demoSeed();
    _applyScenario();
    await store.write(_encode(_state));
    notifyListeners();
  }

  @override
  Future<void> connect(String address, int port, String passphrase) async {
    if (address.trim().isEmpty || port < 1 || port > 65535) {
      throw const LibraryFailure('请填写地址和 1–65535 之间的端口');
    }
    if (address.contains('unreachable') || _scenario == DemoScenario.offline) {
      throw const LibraryFailure('暂时无法连接服务，请检查地址和网络');
    }
    if (passphrase != 'demo') throw const LibraryFailure('访问口令不正确');
    await _commit(
      (s) => s.copy(address: address.trim(), port: port, connected: true),
    );
  }

  @override
  Future<void> setScope(VideoQuery scope, {PlayOrder? order}) => _commit((s) {
    if (scope.folder.isNotEmpty &&
        !s.roots.any(
          (r) =>
              r.available &&
              r.enabled &&
              r.kind == MediaKind.video &&
              under(scope.folder, r.path),
        )) {
      throw const LibraryFailure('所选目录暂时无法访问');
    }
    return _round(s.copy(query: scope, order: order));
  });
  @override
  Future<void> newRound() => _commit(_round);
  @override
  Future<void> step(int delta) => _commit(
    (s) => s.copy(
      position: s.round.isEmpty
          ? 0
          : (s.position + delta).clamp(0, s.round.length - 1),
    ),
  );
  @override
  Future<void> openVideo(String id) => _commit((s) {
    final next = s.round.contains(id) ? s : _round(s);
    if (!next.round.contains(id)) throw const LibraryFailure('这段视频暂时无法播放');
    return next.copy(position: next.round.indexOf(id));
  });
  @override
  Future<void> setVideoTags(
    Set<String> ids,
    Set<String> tags, {
    bool remove = false,
    bool replace = false,
  }) => _commit((s) {
    if (!s.tags.toSet().containsAll(tags)) {
      throw const LibraryFailure('标签已改变，请重新选择');
    }
    return _reconcile(
      s.copy(
        videos: s.videos.map(
          (v) => !ids.contains(v.id)
              ? v
              : v.copy(
                  tags: replace
                      ? tags
                      : remove
                      ? v.tags.difference(tags)
                      : v.tags.union(tags),
                ),
        ),
      ),
    );
  });
  @override
  Future<void> editTag({String? original, String? name, bool delete = false}) =>
      _commit((s) {
        final clean = name?.trim() ?? '';
        if (!delete &&
            (clean.isEmpty || s.tags.any((t) => t == clean && t != original))) {
          throw const LibraryFailure('标签名称不能为空或重复');
        }
        final tags = s.tags.where((t) => t != original).toList();
        if (!delete) tags.add(clean);
        final queryTags = {...s.query.tags};
        if (original != null && queryTags.remove(original) && !delete) {
          queryTags.add(clean);
        }
        final videos = s.videos.map((v) {
          if (original == null || !v.tags.contains(original)) return v;
          final changed = {...v.tags}..remove(original);
          if (!delete) changed.add(clean);
          return v.copy(tags: changed);
        });
        final next = s.copy(
          tags: tags,
          videos: videos,
          query: s.query.copy(tags: queryTags),
        );
        return delete && original != null && s.query.tags.contains(original)
            ? _round(next)
            : _reconcile(next);
      });
  @override
  Future<void> deleteVideos(Set<String> ids, {required String requestId}) =>
      _commit((s) {
        if (s.completedRequests.contains(requestId)) return s;
        final found = s.videos
            .where(
              (v) => ids.contains(v.id) && v.status == VideoStatus.available,
            )
            .map((v) => v.id)
            .toList();
        if (found.isEmpty) throw const LibraryFailure('没有可删除的视频');
        final requests = [...s.completedRequests, requestId];
        return _reconcile(
          s.copy(
            videos: s.videos.map(
              (v) => !found.contains(v.id)
                  ? v
                  : v.copy(status: VideoStatus.trash, originalPath: v.path),
            ),
            lastDelete: DeleteOperation(requestId, found, s.round, s.position),
            completedRequests: requests.skip(max(0, requests.length - 100)),
          ),
        );
      }, fileOperation: true);
  bool _conflict(LibrarySnapshot s, LibraryVideo v) =>
      _scenario == DemoScenario.conflict ||
      s.videos.any(
        (other) =>
            other.id != v.id &&
            other.status == VideoStatus.available &&
            other.path == (v.originalPath ?? v.path),
      );
  @override
  Future<void> undoDelete({required String operationId}) => _commit((s) {
    if (s.completedRequests.contains('undo:$operationId')) return s;
    final op = s.lastDelete;
    if (op == null || op.id != operationId) {
      throw const LibraryFailure('这次删除已失效，请在回收站查看');
    }
    final targets = s.videos.where(
      (v) => op.ids.contains(v.id) && v.status == VideoStatus.trash,
    );
    if (targets.any((v) => _conflict(s, v))) {
      throw const LibraryFailure('恢复失败：原位置已有同名文件，没有覆盖');
    }
    final next = s.copy(
      videos: s.videos.map(
        (v) => op.ids.contains(v.id)
            ? v.copy(
                status: VideoStatus.available,
                path: v.originalPath ?? v.path,
              )
            : v,
      ),
      round: op.round,
      position: op.position,
      clearDelete: true,
      completedRequests: [...s.completedRequests, 'undo:$operationId'],
    );
    return _reconcile(next);
  }, fileOperation: true);
  @override
  Future<List<String>> restoreVideos(Set<String> ids) async {
    final errors = <String>[];
    await _commit((s) {
      final restored = <String>{};
      final videos = s.videos.map((v) {
        if (!ids.contains(v.id) || v.status != VideoStatus.trash) return v;
        if (_conflict(s, v)) {
          errors.add('${v.name}：原位置已有同名文件，没有覆盖');
          return v;
        }
        restored.add(v.id);
        return v.copy(
          status: VideoStatus.available,
          path: v.originalPath ?? v.path,
        );
      }).toList();
      return s.copy(
        videos: videos,
        clearDelete: s.lastDelete?.ids.any(restored.contains) ?? false,
      );
    }, fileOperation: true);
    return errors;
  }

  @override
  Future<int> forgetMissingVideos() async {
    final count = missingCount;
    await _commit(
      (s) => s.copy(
        videos: s.videos.where((v) => v.status != VideoStatus.missing),
      ),
    );
    return count;
  }

  @override
  Future<void> permanentlyDelete(Set<String> ids) => _commit(
    (s) => s.copy(
      videos: s.videos.where(
        (v) => !(ids.contains(v.id) && v.status == VideoStatus.trash),
      ),
      clearDelete: s.lastDelete?.ids.any(ids.contains) ?? false,
    ),
    fileOperation: true,
  );
  @override
  Future<void> saveRoot(MediaRoot root) => _commit((s) {
    if (root.id.isEmpty) {
      root = MediaRoot(
        'r${DateTime.now().microsecondsSinceEpoch}',
        root.name,
        root.path,
        available: root.available,
        kind: root.kind,
        enabled: root.enabled,
        lastScan: root.lastScan,
      );
    }
    if (root.name.trim().isEmpty ||
        !root.path.startsWith('/') ||
        root.path == '/' ||
        root.path.split('/').contains('..')) {
      throw const LibraryFailure('请填写名称和具体挂载目录');
    }
    if (s.roots.any(
      (r) =>
          r.id != root.id &&
          (under(r.path, root.path) || under(root.path, r.path)),
    )) {
      throw const LibraryFailure('这个目录与已有媒体目录重叠');
    }
    final old = s.roots.where((r) => r.id == root.id).firstOrNull;
    if (old != null &&
        old.kind != root.kind &&
        s.videos.any((v) => v.rootId == old.id)) {
      throw const LibraryFailure('已有内容的目录不能直接更改媒体类型');
    }
    final pathChanged = old != null && old.path != root.path;
    return _reconcile(
      s.copy(
        roots: [...s.roots.where((r) => r.id != root.id), root],
        videos: pathChanged
            ? s.videos.map(
                (v) => v.rootId == root.id && v.status == VideoStatus.available
                    ? v.copy(status: VideoStatus.missing)
                    : v,
              )
            : s.videos,
        query: pathChanged && under(s.query.folder, old.path)
            ? s.query.copy(folder: '')
            : s.query,
      ),
    );
  });
  @override
  Future<void> refresh() => _commit((s) {
    if (s.roots.any((r) => !r.available)) {
      if (_scenario != DemoScenario.unavailable || _scanRetries++ == 0) {
        throw const LibraryFailure('收集目录暂不可用，已保留原有视频及标签');
      }
      return s.copy(
        roots: s.roots.map(
          (r) => MediaRoot(
            r.id,
            r.name,
            r.path,
            kind: r.kind,
            enabled: r.enabled,
            lastScan: '刚刚',
          ),
        ),
      );
    }
    if (_scenario == DemoScenario.identityConflict) {
      return _reconcile(
        s.copy(
          videos: [
            ...s.videos
                .where((v) => !['v10', 'v11'].contains(v.id))
                .map(
                  (v) => v.id == 'v1' ? v.copy(status: VideoStatus.missing) : v,
                ),
            for (final pair in [
              ('v10', '/videos/收集/花草/竖版/花间微风_02.mp4'),
              ('v11', '/videos/重复副本/花间微风_副本.mp4'),
            ])
              LibraryVideo(
                id: pair.$1,
                path: pair.$2,
                rootId: 'r1',
                portrait: true,
                source: const MediaSource('assets/media/flower-portrait.mp4'),
                poster: 'assets/media/flower-portrait.jpg',
              ),
          ],
        ),
      );
    }
    if (_scenario == DemoScenario.changedFiles) {
      return _reconcile(
        s.copy(
          videos: s.videos.map(
            (v) => v.id == 'v1'
                ? v.copy(path: '/videos/外部移动/花间微风_改名.mp4')
                : v.id == 'v7'
                ? v.copy(status: VideoStatus.available)
                : v,
          ),
        ),
      );
    }
    return s.copy(
      roots: s.roots.map(
        (r) => MediaRoot(
          r.id,
          r.name,
          r.path,
          kind: r.kind,
          enabled: r.enabled,
          lastScan: '刚刚',
        ),
      ),
      videos: s.videos.any((v) => v.id == 'v9')
          ? s.videos
          : [
              ...s.videos,
              LibraryVideo(
                id: 'v9',
                path: '/collection/新收藏/新收集片段_09.mp4',
                rootId: 'r2',
                portrait: false,
                source: const MediaSource('assets/media/flower-landscape.mp4'),
                poster: 'assets/media/landscape-early.jpg',
              ),
            ],
    );
  });
  String exportBackup() => const JsonEncoder.withIndent('  ').convert({
    'format': 'video-viewer-flutter-demo',
    'version': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'data': _state.toJson(connection: false),
  });
  BackupPreview inspectBackup(String text) => BackupPreview.parse(text);
  @override
  Future<String> exportBackupFile() async => exportBackup();
  @override
  Future<BackupPreview> inspectBackupFile(String text) async =>
      inspectBackup(text);
  @override
  Future<void> restoreBackup(
    String text,
    Map<String, String> rootMappings,
  ) async {
    final incoming = inspectBackup(text).snapshot;
    if (rootMappings.values.any(
      (p) => !p.startsWith('/') || p == '/' || p.split('/').contains('..'),
    )) {
      throw const LibraryFailure('请检查媒体目录映射');
    }
    await store.saveRecovery(_encode(_state));
    await _commit((s) {
      String remap(String path, MediaRoot r) => under(path, r.path)
          ? '${rootMappings[r.id] ?? r.path}${path.substring(r.path.length)}'
          : path;
      final roots = incoming.roots
          .map(
            (r) => MediaRoot(
              r.id,
              r.name,
              rootMappings[r.id] ?? r.path,
              available: r.available,
              kind: r.kind,
              enabled: r.enabled,
              lastScan: r.lastScan,
            ),
          )
          .toList();
      if (roots.any(
        (r) => roots.any((o) => r.id != o.id && under(r.path, o.path)),
      )) {
        throw const LibraryFailure('恢复目录不能重叠');
      }
      final videos = incoming.videos.map((v) {
        final r = incoming.roots.firstWhere((r) => r.id == v.rootId);
        return v.copy(
          path: remap(v.path, r),
          originalPath: v.originalPath == null
              ? null
              : remap(v.originalPath!, r),
        );
      });
      var folder = incoming.query.folder;
      for (final r in incoming.roots) {
        if (folder.isNotEmpty && under(folder, r.path)) {
          folder = remap(folder, r);
          break;
        }
      }
      return _reconcile(
        incoming.copy(
          roots: roots,
          videos: videos,
          query: incoming.query.copy(folder: folder),
          address: s.address,
          port: s.port,
          connected: s.connected,
        ),
      );
    }, fileOperation: true);
  }
}
