import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../library/models.dart';

/// One overview cell owns this transport, including a response still streaming
/// when its sheet is popped. It never closes Flutter's shared image client.
class ReaderThumbnailRequest {
  bool _cancelled = false;
  final _transfers = <_ThumbnailTransfer>{};

  void cancel() {
    _cancelled = true;
    for (final transfer in _transfers.toList()) {
      transfer.cancel();
    }
  }

  Future<ui.Codec> load(MediaSource source, ImageDecoderCallback decode) async {
    if (_cancelled) throw const RequestCancelled();
    final transfer = _ThumbnailTransfer();
    _transfers.add(transfer);
    try {
      return await transfer.load(source, decode);
    } finally {
      _transfers.remove(transfer);
    }
  }
}

/// Leave capacity for the reader's full image. Waiting cells own no socket and
/// can be removed before a permit becomes available on a later page.
class _ThumbnailTransfer {
  static const maximumConcurrent = 3;
  static int _running = 0;
  static final _waiting = <_ThumbnailTransfer>[];
  final _ready = Completer<void>();
  bool _leased = false;
  HttpClient? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
    _client = null;
    if (_waiting.remove(this)) _ready.completeError(const RequestCancelled());
  }

  static void _drain() {
    while (_running < maximumConcurrent && _waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      next._leased = true;
      _running++;
      next._ready.complete();
    }
  }

  Future<ui.Codec> load(MediaSource source, ImageDecoderCallback decode) async {
    _waiting.add(this);
    _drain();
    await _ready.future;
    HttpClient? client;
    try {
      if (_cancelled) throw const RequestCancelled();
      client = _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      return await (() async {
        final uri = Uri.parse(source.location);
        final request = await client!.getUrl(uri);
        if (_cancelled) throw const RequestCancelled();
        source.headers.forEach(request.headers.set);
        final response = await request.close();
        if (_cancelled) throw const RequestCancelled();
        if (response.statusCode != HttpStatus.ok) {
          throw NetworkImageLoadException(
            statusCode: response.statusCode,
            uri: uri,
          );
        }
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (_cancelled) throw const RequestCancelled();
        return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      })().timeout(const Duration(seconds: 15));
    } finally {
      client?.close(force: true);
      _client = null;
      if (_leased) {
        _leased = false;
        _running--;
        _drain();
      }
    }
  }
}

/// Identity belongs to one cell and attempt; cancelled/old-credential requests
/// cannot be reused from the global image cache by another overview.
@immutable
class ReaderThumbnailImage extends ImageProvider<ReaderThumbnailImage> {
  const ReaderThumbnailImage(this.source, this.request);
  final MediaSource source;
  final ReaderThumbnailRequest request;

  @override
  Future<ReaderThumbnailImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ReaderThumbnailImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: request.load(source, decode),
    scale: 1,
  );
}
