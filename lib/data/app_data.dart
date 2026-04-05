/// Data models for content loaded at runtime from the API (`/api/v1/public/config`).
/// Channels, images, carousel, matches, and malipo are not bundled in the app.

class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.cat,
    required this.img,
    required this.free,
    required this.viewers,
    required this.streamUrl,
  });

  final int id;
  final String name;
  final String cat;
  final String img;
  final bool free;
  final String viewers;
  /// Playback URL. Paths ending in `.php` (before `?`/`#`) use in-app WebView; others use native player.
  final String streamUrl;
}

class LiveMatch {
  const LiveMatch({
    required this.id,
    required this.title,
    required this.sport,
    required this.sportIcon,
    required this.img,
    required this.channelId,
  });

  final int id;
  final String title;
  final String sport;
  final String sportIcon;
  final String img;
  final int channelId;
}

class CategoryItem {
  const CategoryItem({required this.key, required this.label, required this.icon});

  final String key;
  final String label;
  final String icon;
}

class PackageItem {
  const PackageItem({
    required this.id,
    required this.name,
    required this.price,
    required this.period,
    required this.features,
    required this.popular,
  });

  final String id;
  final String name;
  final String price;
  final String period;
  final List<String> features;
  final bool popular;
}

class CarouselSlide {
  const CarouselSlide({
    required this.badge,
    required this.badgeIcon,
    required this.title,
    required this.channelId,
    required this.img,
  });

  final String badge;
  final String badgeIcon;
  final String title;
  final int channelId;
  final String img;
}

/// Loader animation copy only (no remote content).
final List<String> kLoadingMessages = [
  'Initializing core systems...',
  'Connecting to CDN servers...',
  'Loading channel database...',
  'Authenticating stream keys...',
  'Fetching live match data...',
  'Calibrating video codecs...',
  'Optimizing for your device...',
  'Preparing HD streams...',
  'Almost ready...',
  'Launch sequence complete ✓',
];
