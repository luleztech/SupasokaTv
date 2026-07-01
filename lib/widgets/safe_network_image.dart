import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supasoka/player/stream_url_classifier.dart';
import 'package:supasoka/util/image_url.dart';
import 'package:supasoka/widgets/pro_shimmer.dart';

/// Cached network image with URL cleanup, browser-like headers, and silent error UI
/// (avoids decode spam when a CDN returns HTML or a URL was saved with line breaks).
class SafeNetworkImage extends StatefulWidget {
  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholderColor,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.onLoadingChanged,
  });

  final String imageUrl;
  final BoxFit? fit;
  final Color? placeholderColor;
  final double? width;
  final double? height;
  final Alignment alignment;
  final int? memCacheWidth;
  final ValueChanged<bool>? onLoadingChanged;

  @override
  State<SafeNetworkImage> createState() => _SafeNetworkImageState();
}

class _SafeNetworkImageState extends State<SafeNetworkImage> {
  bool? _lastReportedLoading;
  bool _resolved = false;

  void _reportLoading(bool loading) {
    if (loading && _resolved) return;
    if (!loading) _resolved = true;
    if (_lastReportedLoading == loading) return;
    _lastReportedLoading = loading;
    final cb = widget.onLoadingChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(loading);
    });
  }

  @override
  void didUpdateWidget(covariant SafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _resolved = false;
      _lastReportedLoading = null;
      _reportLoading(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = sanitizeImageUrl(widget.imageUrl);
    final bg = widget.placeholderColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF18181b)
            : const Color(0xFFE4E4E7));

    if (url.isEmpty) {
      _resolved = true;
      _reportLoading(false);
      if (widget.width != null || widget.height != null) {
        return ColoredBox(
          color: bg,
          child: SizedBox(width: widget.width, height: widget.height),
        );
      }
      return SizedBox.expand(child: ColoredBox(color: bg));
    }

    final image = CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      memCacheWidth: widget.memCacheWidth,
      httpHeaders: const {
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'User-Agent': kBrowserPlaybackUserAgent,
      },
      placeholder: (context, imageUrl) {
        if (!_resolved) _reportLoading(true);
        return ProShimmer(
          child: SizedBox.expand(child: ColoredBox(color: bg)),
        );
      },
      imageBuilder: (context, imageProvider) {
        _resolved = true;
        _reportLoading(false);
        return SizedBox.expand(
          child: Image(
            image: imageProvider,
            fit: widget.fit ?? BoxFit.cover,
            alignment: widget.alignment,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        );
      },
      errorWidget: (context, imageUrl, error) {
        _resolved = true;
        _reportLoading(false);
        return SizedBox.expand(child: ColoredBox(color: bg));
      },
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
    );

    if (widget.width == null && widget.height == null) {
      return SizedBox.expand(child: image);
    }
    return image;
  }
}
