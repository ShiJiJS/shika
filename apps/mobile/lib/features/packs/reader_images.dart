import 'dart:async';
import 'dart:io' show HttpException, SocketException;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import '../../library/repository.dart';
import '../../library/models.dart';
import 'reader_thumbnail_image.dart';

/// Reader-owned decoded providers are resized and evicted as a bounded LRU.
class ReaderImages {
  static const maximumBytes = 48 * 1024 * 1024, maximumEntries = 6;
  final _entries = <String, ({ImageProvider provider, int bytes})>{};
  int get estimatedBytes =>
      _entries.values.fold(0, (sum, item) => sum + item.bytes);
  int get length => _entries.length;
  ImageProvider provider(
    ReaderPage page,
    Size viewport,
    double dpr, {
    bool thumbnail = false,
    bool widthFit = false,
    ImageProvider? networkImage,
  }) {
    final source = thumbnail ? page.thumbnail : page.image;
    if (source == null) throw const LibraryFailure('这张图片暂时不可读取');
    final w = max(1, page.width), h = max(1, page.height);
    final factor = min(
      1.0,
      min(
        (thumbnail ? 160.0 : viewport.width * dpr) / w,
        thumbnail || widthFit ? double.infinity : viewport.height * dpr / h,
      ),
    );
    final budget = sqrt((2 * 1024 * 1024) / (w * h));
    final scale = min(factor, min(budget, 4096 / max(w, h)));
    final width = max(1, (w * scale).round()),
        height = max(1, (h * scale).round());
    final key =
        '${source.location}:$width:$height:${networkImage == null ? '' : identityHashCode(networkImage)}';
    final prior = _entries.remove(key);
    if (prior != null) {
      _entries[key] = prior;
      return prior.provider;
    }
    final ImageProvider original = source.asset
        ? AssetImage(source.location)
        : networkImage ??
              NetworkImage(source.location, headers: source.headers);
    final resized = ResizeImage(original, width: width, height: height);
    _entries[key] = (provider: resized, bytes: width * height * 4);
    while (_entries.length > maximumEntries || estimatedBytes > maximumBytes) {
      final old = _entries.remove(_entries.keys.first)!;
      unawaited(old.provider.evict());
    }
    return resized;
  }

  void evict(ReaderPage page) {
    for (final key
        in _entries.keys
            .where(
              (key) =>
                  key.startsWith('${page.image?.location}:') ||
                  key.startsWith('${page.thumbnail?.location}:'),
            )
            .toList()) {
      unawaited(_entries.remove(key)!.provider.evict());
    }
  }

  void dispose() {
    for (final item in _entries.values) {
      unawaited(item.provider.evict());
    }
    _entries.clear();
  }
}

class ReaderImage extends StatefulWidget {
  const ReaderImage({
    super.key,
    required this.page,
    required this.images,
    required this.viewport,
    this.thumbnail = false,
    this.active = true,
    this.widthFit = false,
    this.onFrame,
    this.onSkip,
    this.onUnauthorized,
  });
  final ReaderPage page;
  final ReaderImages images;
  final Size viewport;
  final bool thumbnail, widthFit, active;
  final VoidCallback? onFrame, onSkip, onUnauthorized;
  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  int attempt = 0;
  int generation = 0;
  int imageRevision = 0;
  Timer? retry;
  ModalRoute<dynamic>? route;
  ReaderThumbnailRequest? thumbnailRequest;
  ReaderThumbnailImage? thumbnailImage;

  MediaSource? source(ReaderImage image) =>
      image.thumbnail ? image.page.thumbnail : image.page.image;

  void cancelWork() {
    generation++;
    retry?.cancel();
    retry = null;
    thumbnailRequest?.cancel();
  }

  void routeChanged() {
    if (route?.isCurrent != true) cancelWork();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if (next != route) {
      route?.animation?.removeListener(routeChanged);
      route = next;
      route?.animation?.addListener(routeChanged);
    }
    routeChanged();
  }

  @override
  void didUpdateWidget(ReaderImage old) {
    super.didUpdateWidget(old);
    final before = source(old), after = source(widget);
    if (old.page.id != widget.page.id ||
        old.page.packId != widget.page.packId ||
        old.page.version != widget.page.version ||
        old.thumbnail != widget.thumbnail ||
        old.active != widget.active ||
        before?.location != after?.location ||
        before?.asset != after?.asset ||
        !mapEquals(before?.headers, after?.headers) ||
        old.images != widget.images) {
      cancelWork();
      old.images.evict(old.page);
      thumbnailRequest = null;
      thumbnailImage = null;
      attempt = 0;
      imageRevision++;
    }
  }

  @override
  void dispose() {
    route?.animation?.removeListener(routeChanged);
    cancelWork();
    if (thumbnailImage != null) widget.images.evict(widget.page);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentGeneration = generation;
    bool current() =>
        mounted &&
        widget.active &&
        generation == currentGeneration &&
        route?.isCurrent == true;
    void reload({bool manual = false}) {
      if (!current()) return;
      cancelWork();
      widget.images.evict(widget.page);
      thumbnailRequest = null;
      thumbnailImage = null;
      setState(() {
        attempt = manual ? 0 : attempt + 1;
        imageRevision++;
      });
    }

    final errorButtonStyle = widget.thumbnail
        ? null
        : TextButton.styleFrom(foregroundColor: Colors.white);
    Widget failure() => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.thumbnail)
              const Text(
                '这一张暂时无法载入',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            TextButton.icon(
              style: errorButtonStyle,
              key: Key('reader-image-retry-${widget.page.id}'),
              onPressed: () {
                reload(manual: true);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
            if (widget.onSkip != null)
              TextButton(
                key: Key('reader-image-skip-${widget.page.id}'),
                style: errorButtonStyle,
                onPressed: widget.onSkip,
                child: const Text('跳过这一张'),
              ),
          ],
        ),
      ),
    );
    if (!widget.active) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (widget.thumbnail && widget.page.thumbnail == null) {
      return const Center(child: Icon(Icons.image_not_supported_outlined));
    }
    if (!widget.page.readable) return failure();
    final media = source(widget);
    if (widget.thumbnail &&
        media != null &&
        !media.asset &&
        thumbnailImage == null) {
      thumbnailRequest = ReaderThumbnailRequest();
      thumbnailImage = ReaderThumbnailImage(media, thumbnailRequest!);
    }
    return Image(
      key: ValueKey('${widget.page.id}-$imageRevision'),
      image: widget.images.provider(
        widget.page,
        widget.viewport,
        MediaQuery.devicePixelRatioOf(context),
        thumbnail: widget.thumbnail,
        widthFit: widget.widthFit,
        networkImage: thumbnailImage,
      ),
      width: widget.widthFit ? widget.viewport.width : null,
      fit: widget.widthFit ? BoxFit.fitWidth : BoxFit.contain,
      gaplessPlayback: false,
      frameBuilder: (context, child, frame, synchronous) {
        if (frame == null) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (widget.onFrame != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (current()) widget.onFrame?.call();
          });
        }
        return child;
      },
      errorBuilder: (context, error, stack) {
        assert(() {
          debugPrint('READER_IMAGE_FAILURE ${widget.page.id}: $error');
          return true;
        }());
        final transient =
            error is SocketException ||
            error is HttpException ||
            error is TimeoutException ||
            (error is NetworkImageLoadException &&
                [429, 503].contains(error.statusCode));
        if (transient && attempt < 2 && retry == null && current()) {
          retry = Timer(Duration(milliseconds: 400 * (attempt + 1)), () {
            retry = null;
            reload();
          });
        }

        if (error is NetworkImageLoadException && error.statusCode == 401) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (current()) widget.onUnauthorized?.call();
          });
        }
        return failure();
      },
    );
  }
}
