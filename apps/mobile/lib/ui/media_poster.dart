import 'package:flutter/material.dart';

import '../library/models.dart';

class MediaPoster extends StatelessWidget {
  const MediaPoster({
    super.key,
    required this.video,
    this.fit = BoxFit.cover,
    this.onUnauthorized,
  });
  final LibraryVideo video;
  final BoxFit fit;
  final VoidCallback? onUnauthorized;

  @override
  Widget build(BuildContext context) {
    Widget unavailable(BuildContext context, Object error, StackTrace? stack) {
      if (error is NetworkImageLoadException && error.statusCode == 401) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onUnauthorized?.call(),
        );
      }
      return const ColoredBox(
        color: Color(0xff20231f),
        child: Center(
          child: Icon(Icons.video_library_outlined, color: Colors.white38),
        ),
      );
    }

    if (video.poster.isEmpty) {
      return unavailable(context, const FormatException(), null);
    }
    return video.source.asset
        ? Image.asset(video.poster, fit: fit, errorBuilder: unavailable)
        : Image.network(
            video.poster,
            headers: video.source.headers,
            fit: fit,
            errorBuilder: unavailable,
          );
  }
}
