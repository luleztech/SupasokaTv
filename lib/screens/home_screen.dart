import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/player/channel_playback.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supasoka/widgets/unlock_all_promo.dart';
import 'package:supasoka/widgets/channel_card.dart';
import 'package:supasoka/widgets/safe_network_image.dart';
import 'package:supasoka/widgets/whatsapp_fab.dart';

const List<String> _kHomeCategoryOrder = [
  'mpira',
  'football',
  'sports',
  'tamthilia',
  'movies',
  'habari',
  'news',
];

const List<({String title, List<String> keys})> _kHomeCategorySections = [
  (title: 'Mpira', keys: ['mpira', 'football', 'sports']),
  (title: 'tamthilia', keys: ['tamthilia', 'movies']),
  (title: 'habari', keys: ['habari', 'news']),
];

/// Fixed channel card size on home rails (poster area).
const double _kHomeRailTileWidth = 180;
const double _kHomeRailPosterHeight = 220;
const double _kHomeRailTileHeight = _kHomeRailPosterHeight + 44;
const double _kHomeSectionGap = 8;
const double _kHomeSectionHeaderGap = 6;

String _homeCategoryTitle(String cat) {
  switch (cat) {
    case 'football':
    case 'mpira':
    case 'sports':
      return 'Mpira';
    case 'movies':
    case 'tamthilia':
      return 'tamthilia';
    case 'news':
    case 'habari':
      return 'habari';
    default:
      return categoryPillLabel(cat);
  }
}

int _homeCategoryRankKey(String key) {
  final rank = _kHomeCategoryOrder.indexOf(key);
  return rank == -1 ? 1000 : rank;
}

String _avatarLetters(String? publicId) {
  if (publicId == null || publicId.isEmpty) return 'SK';
  final tail = publicId.startsWith('User-') && publicId.length > 5
      ? publicId.substring(5)
      : publicId;
  final alnum = tail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  if (alnum.length >= 2) return alnum.substring(0, 2).toUpperCase();
  if (alnum.isNotEmpty) return alnum[0].toUpperCase();
  return 'SK';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';
  bool _searchOpen = false;
  String? _displayName;
  final _searchFocus = FocusNode();
  final _carousel = PageController();
  int _carouselIndex = 0;
  Timer? _carouselTimer;

  static const _carouselAutoInterval = Duration(seconds: 4);
  static const _carouselAnimDuration = Duration(milliseconds: 700);

  String _swahiliGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Habari za asubuhi';
    if (h < 17) return 'Habari za mchana';
    return 'Habari za jioni';
  }

  Future<void> _loadDisplayName() async {
    final id = await UserIdentity.getOrCreatePublicId();
    if (!mounted) return;
    setState(() => _displayName = id);
  }

  void _restartCarouselAutoPlay() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(_carouselAutoInterval, (_) => _advanceCarousel());
  }

  void _advanceCarousel() {
    if (!mounted) return;
    final slides = context.read<ContentStore>().carouselSlides;
    if (slides.length < 2 || !_carousel.hasClients) return;
    final current = _carousel.page?.round() ?? _carouselIndex;
    final next = (current + 1) % slides.length;
    _carousel.animateToPage(
      next,
      duration: _carouselAnimDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  void _onCarouselPageChanged(int index) {
    setState(() => _carouselIndex = index);
    _restartCarouselAutoPlay();
  }

  List<Channel> _filteredChannels(List<Channel> channels, String catKey) {
    var list = catKey == 'all'
        ? List<Channel>.from(channels)
        : channels.where((c) => c.cat == catKey).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((c) => c.name.toLowerCase().contains(q) || c.cat.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _restartCarouselAutoPlay();
    unawaited(_loadDisplayName());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<ContentStore>();
      if (store.ready && store.channels.isEmpty && !store.refreshing) {
        unawaited(store.refresh());
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carousel.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openChannel(BuildContext context, int channelId) {
    final ch = context.read<ContentStore>().channelById(channelId);
    final isPremium = SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;
    if (ch != null && !ch.free && !isPremium) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PaymentScreen()));
    } else {
      openChannelPlayback(context, channelId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ContentStore>();
    final channels = store.channels;
    final carouselSlides = store.carouselSlides;
    final filtered = _filteredChannels(channels, 'all');

    return ValueListenableBuilder<DateTime?>(
      valueListenable: SubscriptionStore.premiumUntilNotifier,
      builder: (context, value, child) {
        final isPremium = SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;

        final browseSlivers = <Widget>[];

        if ((!store.ready || store.refreshing) && channels.isEmpty) {
          browseSlivers.add(
            const SliverToBoxAdapter(
              child: _HomeLoadingSection(),
            ),
          );
        } else if (filtered.isEmpty) {
          browseSlivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 32),
                child: Column(
                  children: [
                    Icon(Ionicons.tv_outline, size: 44, color: BrandPalette.white.withValues(alpha: 0.25)),
                    const SizedBox(height: 14),
                    Text(
                      channels.isEmpty ? 'Hakuna channel bado' : 'Hakuna channel',
                      textAlign: TextAlign.center,
                      style: rajdhani(15, weight: FontWeight.w700).copyWith(
                        color: BrandPalette.white.withValues(alpha: 0.65),
                      ),
                    ),
                    if (channels.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Vuta chini ili kupakia tena',
                        textAlign: TextAlign.center,
                        style: rajdhani(12, weight: FontWeight.w500).copyWith(
                          color: BrandPalette.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        } else {
          final freeChannels = channels.where((ch) => ch.free).toList();
          if (freeChannels.isNotEmpty) {
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRailSection(
                  title: 'Chaneli za bure',
                  sectionStyle: HomeSectionStyle.forTitle('bure'),
                  channels: freeChannels,
                  lockedFor: (_) => false,
                  onChannel: (ch) => _openChannel(context, ch.id),
                ),
              ),
            );
          }
          if (!isPremium) {
            browseSlivers.add(
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: UnlockAllPromoCard(
                    onPressed: () => context.read<AppNav>().setTab(AppTab.unlock),
                  ),
                ),
              ),
            );
          }
          final newest = channels.reversed.take(12).toList();
          if (newest.isNotEmpty) {
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRailSection(
                  title: 'Mpya Zilizoongezwa',
                  sectionStyle: HomeSectionStyle.forTitle('mpya'),
                  channels: newest,
                  lockedFor: (ch) => !ch.free && !isPremium,
                  onChannel: (ch) => _openChannel(context, ch.id),
                ),
              ),
            );
          }
          final renderedKeys = <String>{};
          for (final section in _kHomeCategorySections) {
            final keySet = section.keys.toSet();
            final list = channels.where((ch) => keySet.contains(ch.cat)).toList();
            if (list.isEmpty) continue;
            renderedKeys.addAll(section.keys);
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRailSection(
                  title: section.title,
                  sectionStyle: HomeSectionStyle.forTitle(section.title),
                  channels: list,
                  lockedFor: (ch) => !ch.free && !isPremium,
                  onChannel: (ch) => _openChannel(context, ch.id),
                ),
              ),
            );
          }
          final remainingKeys = channels
              .map((ch) => ch.cat)
              .toSet()
              .where((key) => !renderedKeys.contains(key))
              .toList()
            ..sort((a, b) {
              final byRank = _homeCategoryRankKey(a).compareTo(_homeCategoryRankKey(b));
              if (byRank != 0) return byRank;
              return categoryPillLabel(a).compareTo(categoryPillLabel(b));
            });
          for (final key in remainingKeys) {
            final list = channels.where((ch) => ch.cat == key).toList();
            if (list.isEmpty) continue;
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRailSection(
                  title: _homeCategoryTitle(key),
                  sectionStyle: HomeSectionStyle.forCategoryKey(key),
                  channels: list,
                  lockedFor: (ch) => !ch.free && !isPremium,
                  onChannel: (ch) => _openChannel(context, ch.id),
                ),
              ),
            );
          }
        }

        return ColoredBox(
      color: BrandPalette.bgDeep,
      child: Stack(
      fit: StackFit.expand,
      children: [
        const _HomeAmbientBackground(),
        RefreshIndicator(
          color: BrandPalette.accent,
          backgroundColor: BrandPalette.bgMid,
          onRefresh: () => context.read<ContentStore>().refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (store.loadError != null && !store.connectionBlocked)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _HomeErrorBanner(
                      message: store.loadError!,
                      onRetry: () => store.refresh(),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: _HomeTopBar(
                  greeting: _swahiliGreeting(),
                  avatarLetters: _avatarLetters(_displayName),
                  searchOpen: _searchOpen,
                  onSearchTap: () {
                    setState(() {
                      _searchOpen = !_searchOpen;
                      if (_searchOpen) {
                        _searchFocus.requestFocus();
                      } else {
                        _searchFocus.unfocus();
                        _query = '';
                      }
                    });
                  },
                  onProfileTap: () => context.read<AppNav>().setTab(AppTab.profile),
                ),
              ),
              if (_searchOpen)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: _HomeSearchBar(
                      focusNode: _searchFocus,
                      query: _query,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
              if (carouselSlides.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _HomeHeroCarousel(
                      controller: _carousel,
                      slides: carouselSlides,
                      activeIndex: _carouselIndex,
                      onPageChanged: _onCarouselPageChanged,
                      onDotTap: (i) {
                        _onCarouselPageChanged(i);
                        _carousel.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                        );
                      },
                    ),
                ),
              ),
              ...browseSlivers,
              const SliverToBoxAdapter(child: SizedBox(height: 108)),
            ],
          ),
        ),
        const WhatsAppFab(),
      ],
    ),
    );
      },
    );
  }
}

// ─── Home visual system (brand palette) ──────────────────────────────────

class _HomeAmbientBackground extends StatelessWidget {
  const _HomeAmbientBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BrandPalette.bgDeep, BrandPalette.bgMid, BrandPalette.bgDeep],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
            Positioned(
              top: -60,
              right: -40,
              child: _GlowOrb(size: 220, color: BrandPalette.accent.withValues(alpha: 0.14)),
            ),
            Positioned(
              top: 180,
              left: -80,
              child: _GlowOrb(size: 180, color: BrandPalette.accentWarm.withValues(alpha: 0.1)),
            ),
            Positioned(
              bottom: 120,
              right: -30,
              child: _GlowOrb(size: 160, color: BrandPalette.accent.withValues(alpha: 0.08)),
            ),
        ],
      ),
    );
  }
}

class _HomeLoadingSection extends StatelessWidget {
  const _HomeLoadingSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 48),
      child: Column(
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: BrandPalette.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Inapakia channeli…',
            style: rajdhani(14, weight: FontWeight.w700).copyWith(
              color: BrandPalette.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.greeting,
    required this.avatarLetters,
    required this.searchOpen,
    required this.onSearchTap,
    required this.onProfileTap,
  });

  final String greeting;
  final String avatarLetters;
  final bool searchOpen;
  final VoidCallback onSearchTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 10, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '$greeting 👋',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: rajdhani(14, weight: FontWeight.w600).copyWith(
                color: BrandPalette.white.withValues(alpha: 0.65),
              ),
            ),
          ),
          _HomeIconButton(
            icon: searchOpen ? Ionicons.close_outline : Ionicons.search_outline,
            onTap: onSearchTap,
            filled: false,
          ),
          const SizedBox(width: 10),
          _HomeIconButton(
            label: avatarLetters,
            onTap: onProfileTap,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _HomeIconButton extends StatelessWidget {
  const _HomeIconButton({
    this.icon,
    this.label,
    required this.onTap,
    required this.filled,
  }) : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: filled
                ? BrandPalette.bgMid
                : BrandPalette.bgMid.withValues(alpha: 0.7),
            border: Border.all(
              color: filled
                  ? BrandPalette.accent.withValues(alpha: 0.35)
                  : BrandPalette.white.withValues(alpha: 0.1),
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: BrandPalette.accent.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: 20, color: BrandPalette.white.withValues(alpha: 0.85))
              : Text(
                  label!,
                  style: rajdhani(13, weight: FontWeight.w800).copyWith(color: BrandPalette.white),
                ),
        ),
      ),
    );
  }
}

class _HomeHeroCarousel extends StatelessWidget {
  const _HomeHeroCarousel({
    required this.controller,
    required this.slides,
    required this.activeIndex,
    required this.onPageChanged,
    required this.onDotTap,
  });

  final PageController controller;
  final List<CarouselSlide> slides;
  final int activeIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onDotTap;

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.sizeOf(context).width - 32;
    final cardHeight = (cardWidth * 9 / 16 + 200).clamp(440.0, 500.0);

    return Column(
      children: [
        SizedBox(
          height: cardHeight,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: BrandPalette.accent.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: PageView.builder(
                controller: controller,
                itemCount: slides.length,
                onPageChanged: onPageChanged,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, i) {
                  return _CarouselSlide(
                    item: slides[i],
                    isActive: i == activeIndex,
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(slides.length, (i) {
            final active = i == activeIndex;
            return GestureDetector(
              onTap: () => onDotTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 6,
                width: active ? 22 : 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: active ? BrandPalette.activeGradient : null,
                  color: active ? null : BrandPalette.white.withValues(alpha: 0.2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _HomeErrorBanner extends StatelessWidget {
  const _HomeErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: BrandPalette.bgMid.withValues(alpha: 0.95),
        border: Border.all(color: BrandPalette.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_tethering_error_rounded, color: BrandPalette.accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: rajdhani(12, weight: FontWeight.w600).copyWith(
                color: BrandPalette.white.withValues(alpha: 0.75),
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Jaribu', style: TextStyle(color: BrandPalette.accent)),
          ),
        ],
      ),
    );
  }
}

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({
    required this.item,
    this.isActive = true,
  });

  final CarouselSlide item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: BrandPalette.bgMid),
        Positioned.fill(
          child: SafeNetworkImage(
            imageUrl: item.img,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            placeholderColor: BrandPalette.bgMid,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 130,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  BrandPalette.bgDeep.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 14,
          left: 14,
          child: _BrandLiveBadge(
            label: item.badge.isNotEmpty ? item.badge : '🔥 Zinazovuma sasa',
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: inter(20, weight: FontWeight.w800).copyWith(
                  color: BrandPalette.white,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'LIVE • Supasoka',
                style: rajdhani(11, weight: FontWeight.w600).copyWith(
                  color: BrandPalette.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandLiveBadge extends StatelessWidget {
  const _BrandLiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BrandPalette.bgDeep.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BrandPalette.accentWarm.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: BrandPalette.accentWarm,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: rajdhani(10, weight: FontWeight.w700).copyWith(
              color: BrandPalette.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeChannelSectionHeader extends StatelessWidget {
  const _HomeChannelSectionHeader({
    required this.title,
    required this.count,
    required this.style,
  });

  final String title;
  final int count;
  final HomeSectionStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                style.primary.withValues(alpha: 0.22),
                style.secondary.withValues(alpha: 0.1),
              ],
            ),
            border: Border.all(color: style.primary.withValues(alpha: 0.35)),
          ),
          alignment: Alignment.center,
          child: Text(style.emoji, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => style.accentGradient.createShader(b),
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: rajdhani(15, weight: FontWeight.w800).copyWith(
                    color: BrandPalette.white,
                    letterSpacing: 0.8,
                    height: 1.05,
                  ),
                ),
              ),
              Text(
                '$count channel${count == 1 ? '' : 's'} · ${style.label}',
                style: rajdhani(11, weight: FontWeight.w600).copyWith(
                  color: BrandPalette.white.withValues(alpha: 0.42),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: style.primary.withValues(alpha: 0.4)),
            color: style.primary.withValues(alpha: 0.1),
          ),
          child: Text(
            '$count',
            style: rajdhani(11, weight: FontWeight.w800).copyWith(color: style.primary),
          ),
        ),
      ],
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, required this.style});

  final String title;
  final HomeSectionStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: inter(17, weight: FontWeight.w800).copyWith(color: BrandPalette.white),
        ),
        const Spacer(),
        Text(
          'Zote',
          style: rajdhani(12, weight: FontWeight.w700).copyWith(color: BrandPalette.accent),
        ),
      ],
    );
  }
}

class _ChannelRailSection extends StatelessWidget {
  const _ChannelRailSection({
    required this.title,
    required this.sectionStyle,
    required this.channels,
    required this.lockedFor,
    required this.onChannel,
    this.showPlayOverlay = false,
  });

  final String title;
  final HomeSectionStyle sectionStyle;
  final List<Channel> channels;
  final bool Function(Channel) lockedFor;
  final void Function(Channel) onChannel;
  final bool showPlayOverlay;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();
    const tileW = _kHomeRailTileWidth;
    const tileH = _kHomeRailTileHeight;

    return Padding(
      padding: const EdgeInsets.only(bottom: _kHomeSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, _kHomeSectionHeaderGap),
            child: _HomeSectionHeader(title: title, style: sectionStyle),
          ),
          SizedBox(
            height: tileH,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final ch = channels[i];
                return SizedBox(
                  width: tileW,
                  child: Stack(
                    children: [
                      ChannelCard(
                        channel: ch,
                        width: tileW,
                        posterHeight: _kHomeRailPosterHeight,
                        locked: lockedFor(ch),
                        onPress: () => onChannel(ch),
                      ),
                      if (showPlayOverlay)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: BrandPalette.bgDeep.withValues(alpha: 0.55),
                              border: Border.all(color: BrandPalette.white.withValues(alpha: 0.25)),
                            ),
                            child: const Icon(Ionicons.play, size: 16, color: BrandPalette.white),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelPosterRailSection extends StatelessWidget {
  const _ChannelPosterRailSection({
    required this.title,
    required this.sectionStyle,
    required this.channels,
    required this.lockedFor,
    required this.onChannel,
  });

  final String title;
  final HomeSectionStyle sectionStyle;
  final List<Channel> channels;
  final bool Function(Channel) lockedFor;
  final void Function(Channel) onChannel;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();
    const tileW = 118.0;
    const tileH = 178.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: _kHomeSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, _kHomeSectionHeaderGap),
            child: _HomeSectionHeader(title: title, style: sectionStyle),
          ),
          SizedBox(
            height: tileH,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final ch = channels[i];
                return ChannelPosterCard(
                  channel: ch,
                  width: tileW,
                  locked: lockedFor(ch),
                  onPress: () => onChannel(ch),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySectionShell extends StatelessWidget {
  const _CategorySectionShell({
    required this.style,
    required this.child,
  });

  final HomeSectionStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: BrandPalette.bgMid.withValues(alpha: 0.55),
        border: Border.all(color: BrandPalette.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: DecoratedBox(decoration: BoxDecoration(gradient: style.accentGradient)),
            ),
            Positioned(
              top: -30,
              right: -20,
              child: _GlowOrb(size: 100, color: style.primary.withValues(alpha: 0.12)),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChannelGridSection extends StatelessWidget {
  const _ChannelGridSection({
    required this.title,
    required this.sectionStyle,
    required this.channels,
    required this.lockedFor,
    required this.onChannel,
  });

  final String title;
  final HomeSectionStyle sectionStyle;
  final List<Channel> channels;
  final bool Function(Channel) lockedFor;
  final void Function(Channel) onChannel;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    final w = MediaQuery.sizeOf(context).width;
    const hPad = 14.0;
    const gap = 10.0;
    const shellMargin = 12.0;
    final cols = w >= 520 ? 3 : 2;
    final cellW = (w - shellMargin * 2 - hPad * 2 - gap * (cols - 1)) / cols;
    final tileH = channelGridCellHeight(cellW).clamp(88.0, double.infinity) + 2;

    return _CategorySectionShell(
      style: sectionStyle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(hPad, 14, hPad, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeChannelSectionHeader(title: title, count: channels.length, style: sectionStyle),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: tileH,
              ),
              itemCount: channels.length,
              itemBuilder: (context, i) {
                final ch = channels[i];
                return ChannelCard(
                  channel: ch,
                  locked: lockedFor(ch),
                  compactGrid: true,
                  onPress: () => onChannel(ch),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar({
    required this.focusNode,
    required this.query,
    required this.onChanged,
  });

  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: BrandPalette.bgMid.withValues(alpha: 0.9),
        border: Border.all(color: BrandPalette.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Ionicons.search_outline, size: 18, color: BrandPalette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              focusNode: focusNode,
              onChanged: onChanged,
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: BrandPalette.white),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Tafuta channel…',
                hintStyle: rajdhani(14, weight: FontWeight.w500).copyWith(
                  color: BrandPalette.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          if (query.isNotEmpty)
            GestureDetector(
              onTap: () => onChanged(''),
              child: Icon(
                Ionicons.close_circle,
                size: 18,
                color: BrandPalette.white.withValues(alpha: 0.45),
              ),
            ),
        ],
      ),
    );
  }
}
