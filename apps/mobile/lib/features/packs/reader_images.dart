import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../library/repository.dart';
import '../../library/models.dart';

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
    final key = '${source.location}:$width:$height';
    final prior = _entries.remove(key);
    if (prior != null) {
      _entries[key] = prior;
      return prior.provider;
    }
    final ImageProvider original = source.asset
        ? AssetImage(source.location)
        : NetworkImage(source.location, headers: source.headers);
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
    this.widthFit = false,
    this.onFrame,
    this.onSkip,
    this.onUnauthorized,
  });
  final ReaderPage page;
  final ReaderImages images;
  final Size viewport;
  final bool thumbnail, widthFit;
  final VoidCallback? onFrame, onSkip, onUnauthorized;
  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  int attempt = 0;
  Timer? retry;
  @override
  void didUpdateWidget(ReaderImage old) {
    super.didUpdateWidget(old);
    if (old.page.id != widget.page.id ||
        old.page.version != widget.page.version) {
      retry?.cancel();
      retry = null;
      attempt = 0;
    }
  }

  @override
  void dispose() {
    retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                widget.images.evict(widget.page);
                setState(() => attempt++);
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
    if (widget.thumbnail && widget.page.thumbnail == null) {
      return const Center(child: Icon(Icons.image_not_supported_outlined));
    }
    if (!widget.page.readable) return failure();
    return Image(
      key: ValueKey('${widget.page.id}-$attempt'),
      image: widget.images.provider(
        widget.page,
        widget.viewport,
        MediaQuery.devicePixelRatioOf(context),
        thumbnail: widget.thumbnail,
        widthFit: widget.widthFit,
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
            if (mounted) widget.onFrame?.call();
          });
        }
        return child;
      },
      errorBuilder: (context, error, stack) {
        assert(() {
          debugPrint('READER_IMAGE_FAILURE ${widget.page.id}: $error');
          return true;
        }());
        if (error is NetworkImageLoadException &&
            [429, 503].contains(error.statusCode) &&
            attempt < 2 &&
            retry == null &&
            ModalRoute.of(context)?.isCurrent == true) {
          retry = Timer(Duration(milliseconds: 400 * (attempt + 1)), () {
            retry = null;
            if (mounted) {
              widget.images.evict(widget.page);
              setState(() => attempt++);
            }
          });
        }

        if (error is NetworkImageLoadException && error.statusCode == 401) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onUnauthorized?.call();
          });
        }
        return failure();
      },
    );
  }
}
