/// Customer care WhatsApp (digits only, country code included). Used by FAB & Settings → Chat.
/// Keep in sync with SupaAdmin export field `customerCareWhatsapp` when you ship JSON to users.
const String kCustomerCareWhatsapp = '212600000000';

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
  /// Playback URL. Paths ending in `.php` (before `?`/`#`) use in-app WebView; others use native player (ExoPlayer on Android).
  final String streamUrl;
}

class LiveMatch {
  const LiveMatch({
    required this.id,
    required this.title,
    required this.sport,
    required this.sportIcon,
    required this.img,
  });

  final int id;
  final String title;
  final String sport;
  final String sportIcon;
  final String img;
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

final List<Channel> kChannels = [
  const Channel(
    id: 0,
    name: 'Vero Sports HD',
    cat: 'football',
    img: 'https://picsum.photos/seed/bein1/400/220',
    free: true,
    viewers: '24.1K',
    streamUrl: 'https://example.com/live.php?id=vero',
  ),
  const Channel(
    id: 1,
    name: 'Aero Sports Premier',
    cat: 'football',
    img: 'https://picsum.photos/seed/sky2/400/220',
    free: false,
    viewers: '18.9K',
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  const Channel(
    id: 2,
    name: 'Flixora Originals',
    cat: 'movies',
    img: 'https://picsum.photos/seed/netf3/400/220',
    free: true,
    viewers: '32K',
    streamUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
  ),
  const Channel(
    id: 3,
    name: 'Cinemax Ultra',
    cat: 'movies',
    img: 'https://picsum.photos/seed/hbo4/400/220',
    free: false,
    viewers: '11.3K',
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  const Channel(
    id: 4,
    name: 'SportVex HD',
    cat: 'sports',
    img: 'https://picsum.photos/seed/espn5/400/220',
    free: true,
    viewers: '9.7K',
    streamUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
  ),
  const Channel(
    id: 5,
    name: 'Nexosport HD',
    cat: 'sports',
    img: 'https://picsum.photos/seed/euro6/400/220',
    free: false,
    viewers: '7.2K',
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  const Channel(
    id: 6,
    name: 'Vibra Entertainment',
    cat: 'entertainment',
    img: 'https://picsum.photos/seed/mtv7/400/220',
    free: true,
    viewers: '15K',
    streamUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
  ),
  const Channel(
    id: 7,
    name: 'Explorix Channel',
    cat: 'entertainment',
    img: 'https://picsum.photos/seed/disc8/400/220',
    free: false,
    viewers: '6.4K',
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  const Channel(
    id: 8,
    name: 'Globex World News',
    cat: 'news',
    img: 'https://picsum.photos/seed/bbc9/400/220',
    free: true,
    viewers: '21K',
    streamUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
  ),
  const Channel(
    id: 9,
    name: 'Arivo News Live',
    cat: 'news',
    img: 'https://picsum.photos/seed/alj10/400/220',
    free: false,
    viewers: '13.5K',
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  const Channel(
    id: 10,
    name: 'Lorium Liga TV',
    cat: 'football',
    img: 'https://picsum.photos/seed/laliga11/400/220',
    free: false,
    viewers: '8.8K',
    streamUrl: 'https://gateway.example.com/embed/player.php?c=10',
  ),
  const Channel(
    id: 11,
    name: 'Cinevox Movies 4K',
    cat: 'movies',
    img: 'https://picsum.photos/seed/action12/400/220',
    free: true,
    viewers: '19K',
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
];

final List<LiveMatch> kLiveMatches = [
  const LiveMatch(id: 0, title: 'Lorem FC vs Ipsum United', sport: 'Lorem League', sportIcon: 'football-outline', img: 'https://picsum.photos/seed/live1/400/220'),
  const LiveMatch(id: 1, title: 'Dolor City vs Amet FC', sport: 'Ipsum Liga', sportIcon: 'football-outline', img: 'https://picsum.photos/seed/live2/400/220'),
  const LiveMatch(id: 2, title: 'Lorem Hawks vs Ipsum Bulls', sport: 'Lorem Basketball', sportIcon: 'basketball-outline', img: 'https://picsum.photos/seed/live3/400/220'),
  const LiveMatch(id: 3, title: 'Lorem Open Final', sport: 'Lorem Tennis', sportIcon: 'tennisball-outline', img: 'https://picsum.photos/seed/live4/400/220'),
  const LiveMatch(id: 4, title: 'Lorem Grand Prix Series', sport: 'Ipsum Racing', sportIcon: 'car-sport-outline', img: 'https://picsum.photos/seed/live5/400/220'),
  const LiveMatch(id: 5, title: 'Lorem Championship Fight', sport: 'Dolor Combat', sportIcon: 'barbell-outline', img: 'https://picsum.photos/seed/live6/400/220'),
];

final List<PackageItem> kPackages = [
  const PackageItem(
    id: 'daily',
    name: 'Daily Pass',
    price: r'$1.99',
    period: '/day',
    features: ['All Channels', 'HD Quality', '1 Device'],
    popular: false,
  ),
  const PackageItem(
    id: 'weekly',
    name: 'Weekly Pack',
    price: r'$7.99',
    period: '/week',
    features: ['All Channels', 'Full HD', '2 Devices', 'Catch-up TV'],
    popular: true,
  ),
  const PackageItem(
    id: 'monthly',
    name: 'Monthly Pro',
    price: r'$19.99',
    period: '/month',
    features: ['All Channels', '4K Ultra', '4 Devices', 'Catch-up TV', 'Download'],
    popular: false,
  ),
];

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

final List<CarouselSlide> kCarouselSlides = [
  const CarouselSlide(badge: 'LIVE NOW', badgeIcon: 'radio-outline', title: 'Lorem Cup\nFinal 2025', channelId: 0, img: 'https://picsum.photos/seed/match1/800/400'),
  const CarouselSlide(badge: 'NEW MOVIE', badgeIcon: 'film-outline', title: 'The Lorem\nIpsum', channelId: 2, img: 'https://picsum.photos/seed/movie22/800/400'),
  const CarouselSlide(badge: 'TONIGHT', badgeIcon: 'trophy-outline', title: 'Lorem League\nDerby Night', channelId: 1, img: 'https://picsum.photos/seed/sport5/800/400'),
  const CarouselSlide(badge: 'ENTERTAINMENT', badgeIcon: 'musical-notes-outline', title: 'Dolor Night\nLive Stream', channelId: 3, img: 'https://picsum.photos/seed/enter9/800/400'),
];

final List<CategoryItem> kCategories = [
  const CategoryItem(key: 'all', label: 'All', icon: 'flame-outline'),
  const CategoryItem(key: 'football', label: 'Football', icon: 'football-outline'),
  const CategoryItem(key: 'movies', label: 'Movies', icon: 'film-outline'),
  const CategoryItem(key: 'sports', label: 'Sports', icon: 'trophy-outline'),
  const CategoryItem(key: 'entertainment', label: 'Entertainment', icon: 'musical-notes-outline'),
  const CategoryItem(key: 'news', label: 'News', icon: 'newspaper-outline'),
];

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

Channel? channelById(int id) {
  for (final c in kChannels) {
    if (c.id == id) return c;
  }
  return null;
}
