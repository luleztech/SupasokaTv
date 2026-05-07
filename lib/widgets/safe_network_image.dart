import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supasoka/player/stream_url_classifier.dart';
import 'package:supasoka/util/image_url.dart';

/// Cached network image with URL cleanup, browser-like headers, and silent error UI
/// (avoids decode spam when a CDN returns HTML or a URL was saved with line breaks).
class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholderColor,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.memCacheWidth,
  });

  final String imageUrl;
  final BoxFit? fit;
  final Color? placeholderColor;
  final double? width;
  final double? height;
  final Alignment alignment;
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final url = sanitizeImageUrl(imageUrl);
    final bg = placeholderColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF18181b)
            : const Color(0xFFE4E4E7));

    if (url.isEmpty) {
      if (width != null || height != null) {
        return ColoredBox(color: bg, child: SizedBox(width: width, height: height));
      }
      return SizedBox.expand(child: ColoredBox(color: bg));
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      alignment: alignment,
      memCacheWidth: memCacheWidth,
      httpHeaders: const {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'User-Agent': kBrowserPlaybackUserAgent,
      },
      placeholder: (context, imageUrl) => ColoredBox(color: bg),
      errorWidget: (context, imageUrl, error) => ColoredBox(color: bg),
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
    );
  }
}
