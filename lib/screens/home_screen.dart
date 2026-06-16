import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/player/channel_playback.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/unlock_all_promo.dart';
import 'package:supasoka/widgets/cat_pill.dart';
import 'package:supasoka/widgets/channel_card.dart';
import 'package:supasoka/widgets/premium_ui.dart';
import 'package:supasoka/widgets/pro_shimmer.dart';
import 'package:supasoka/widgets/safe_network_image.dart';
import 'package:supasoka/widgets/whatsapp_fab.dart';

/// Home horizontal channel cards: reduced exactly 20px wide and 30px tall from the 212px layout.
const double _kOriginalRailTileWidth = 212;
const double _kRailTileWidth = _kOriginalRailTileWidth - 20;
const double _kRailHeightReduction = 30;
const double _kRailListBottomPadding = 4;
double get _kRailPosterHeightDelta =>
    (channelHomeRailCellHeight(_kOriginalRailTileWidth) -
            _kRailHeightReduction -
            _kRailListBottomPadding) -
        (_kRailTileWidth * 4 / 3);

double get _kRailHeight =>
    channelHomeRailCellHeight(_kOriginalRailTileWidth) - _kRailHeightReduction;

/// Free channels rail — 50px narrower and 40px shorter than standard home rails.
const double _kFreeRailWidthReduction = 50;
const double _kFreeRailHeightReduction = 40;
double get _kFreeRailTileWidth => _kRailTileWidth - _kFreeRailWidthReduction;
double get _kFreeRailHeight => _kRailHeight - _kFreeRailHeightReduction;
double get _kFreeRailPosterHeightDelta =>
    (_kFreeRailHeight - _kRailListBottomPadding) - (_kFreeRailTileWidth * 4 / 3);

/// Mpira channels rail — 70px wider and 30px taller than standard home rails.
const double _kMpiraRailWidthIncrease = 70;
const double _kMpiraRailHeightReduction = -30;
double get _kMpiraRailTileWidth => _kRailTileWidth + _kMpiraRailWidthIncrease;
double get _kMpiraRailHeight => _kRailHeight - _kMpiraRailHeightReduction;
double get _kMpiraRailPosterHeightDelta =>
    (_kMpiraRailHeight - _kRailListBottomPadding) - (_kMpiraRailTileWidth * 4 / 3);

String _catEmoji(String cat) {
  switch (cat) {
    case 'football':
    case 'mpira':
    case 'sports':
      return '⚽';
    case 'movies':
    case 'tamthilia':
      return '🎬';
    case 'news':
    case 'habari':
      return '🌏';
    case 'entertainment':
      return '🎵';
    default:
      return '📺';
  }
}

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

int _homeCategoryRank(CategoryItem cat) {
  final rank = _kHomeCategoryOrder.indexOf(cat.key);
  return rank == -1 ? 1000 : rank;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _cat = 'all';
  final _carousel = PageController();
  int _carouselIndex = 0;
  Timer? _carouselTimer;

  static const _carouselAutoInterval = Duration(seconds: 4);
  static const _carouselAnimDuration = Duration(milliseconds: 700);

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
    if (catKey == 'all') return channels;
    return channels.where((c) => c.cat == catKey).toList();
  }

  @override
  void initState() {
    super.initState();
    _restartCarouselAutoPlay();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carousel.dispose();
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
    final t = context.watch<ThemeController>().colors;
    final store = context.watch<ContentStore>();
    final channels = store.channels;
    final carouselSlides = store.carouselSlides;
    final cats = buildCategoryPills(channels);
    final catKeys = cats.map((c) => c.key).toSet();
    final fk = catKeys.contains(_cat) ? _cat : 'all';
    final filtered = _filteredChannels(channels, fk);

    return ValueListenableBuilder<DateTime?>(
      valueListenable: SubscriptionStore.premiumUntilNotifier,
      builder: (context, value, child) {
        final isPremium = SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;

        final browseSlivers = <Widget>[];

        if (!store.ready && channels.isEmpty) {
          browseSlivers.add(
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 16 / 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => const ShimmerBox(radius: 16),
                  childCount: 6,
                ),
              ),
            ),
          );
        } else if (filtered.isEmpty) {
          browseSlivers.add(
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Ionicons.tv_outline, size: 40, color: t.border),
                    const SizedBox(height: 12),
                    Text('No channels found', style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text2)),
                  ],
                ),
              ),
            ),
          );
        } else if (fk != 'all') {
          browseSlivers.add(
            SliverToBoxAdapter(
              child: _ChannelRail(
                title: '⚡ STREAMS',
                tileWidth: _kRailTileWidth,
                railHeight: _kRailHeight,
                channels: filtered,
                lockedFor: (ch) => !ch.free && !isPremium,
                onChannel: (ch) => _openChannel(context, ch.id),
              ),
            ),
          );
        } else {
          final freeTop = channels.where((ch) => ch.free).take(12).toList();
          if (freeTop.isNotEmpty) {
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRail(
                  title: 'Chaneli za bure',
                  tileWidth: _kFreeRailTileWidth,
                  railHeight: _kFreeRailHeight,
                  railPosterHeightDelta: _kFreeRailPosterHeightDelta,
                  channels: freeTop,
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
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: UnlockAllPromoCard(
                    onPressed: () => context.read<AppNav>().setTab(3),
                  ),
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
            final isMpira = section.title == 'Mpira';
            final isHabari = section.title == 'habari';
            final isTamthilia = section.title == 'tamthilia';
            if (isHabari) {
              browseSlivers.add(
                SliverToBoxAdapter(
                  child: _ChannelGridSection(
                    title: section.title,
                    channels: list,
                    lockedFor: (ch) => !ch.free && !isPremium,
                    onChannel: (ch) => _openChannel(context, ch.id),
                  ),
                ),
              );
            } else {
              browseSlivers.add(
                SliverToBoxAdapter(
                  child: _ChannelRail(
                    title: section.title,
                    tileWidth: isMpira
                        ? _kMpiraRailTileWidth
                        : (isTamthilia ? _kFreeRailTileWidth : _kRailTileWidth),
                    railHeight: isMpira
                        ? _kMpiraRailHeight
                        : (isTamthilia ? _kFreeRailHeight : _kRailHeight),
                    railPosterHeightDelta: isMpira
                        ? _kMpiraRailPosterHeightDelta
                        : (isTamthilia ? _kFreeRailPosterHeightDelta : null),
                    channels: list,
                    lockedFor: (ch) => !ch.free && !isPremium,
                    onChannel: (ch) => _openChannel(context, ch.id),
                  ),
                ),
              );
            }
          }
          final remainingCats = cats
              .where((cat) => cat.key != 'all' && !renderedKeys.contains(cat.key))
              .toList()
            ..sort((a, b) {
              final byRank = _homeCategoryRank(a).compareTo(_homeCategoryRank(b));
              if (byRank != 0) return byRank;
              return a.label.compareTo(b.label);
            });
          for (final cat in remainingCats) {
            final list = channels.where((ch) => ch.cat == cat.key).toList();
            if (list.isEmpty) continue;
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRail(
                  title: _homeCategoryTitle(cat.key),
                  tileWidth: _kRailTileWidth,
                  railHeight: _kRailHeight,
                  channels: list,
                  lockedFor: (ch) => !ch.free && !isPremium,
                  onChannel: (ch) => _openChannel(context, ch.id),
                ),
              ),
            );
          }
        }

        return Stack(
      children: [
        _HomeAmbientBackground(colors: t),
        RefreshIndicator(
          color: t.accent,
          backgroundColor: t.card,
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
                child: SizedBox(height: MediaQuery.paddingOf(context).top + 8),
              ),
              if (carouselSlides.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _HomeCategoryBlock(
                    cats: cats,
                    activeKey: fk,
                    onSelect: (key) => setState(() => _cat = key),
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
    );
      },
    );
  }
}

// ─── Home-only visual system (logic unchanged elsewhere) ───────────────────

class _HomeAmbientBackground extends StatelessWidget {
  const _HomeAmbientBackground({required this.colors});

  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: PremiumAmbientBackground(),
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
    final t = context.watch<ThemeController>().colors;

    return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(color: t.accent.withValues(alpha: 0.18), blurRadius: 36, spreadRadius: -10, offset: const Offset(0, 16)),
              BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 28, offset: const Offset(0, 14)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 440,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: controller,
                    itemCount: slides.length,
                    onPageChanged: onPageChanged,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, i) {
                      return _CarouselSlide(item: slides[i], colors: t, isActive: i == activeIndex);
                    },
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 120,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.88)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: List.generate(slides.length, (i) {
                              final active = i == activeIndex;
                              return GestureDetector(
                                onTap: () => onDotTap(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  margin: const EdgeInsets.only(right: 6),
                                  height: 5,
                                  width: active ? 24 : 6,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(active ? 99 : 99),
                                    color: active ? t.accent : Colors.white.withValues(alpha: 0.25),
                                    boxShadow: active
                                        ? [BoxShadow(color: t.accent.withValues(alpha: 0.55), blurRadius: 10)]
                                        : null,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            '${activeIndex + 1}/${slides.length}',
                            style: rajdhani(11, weight: FontWeight.w700).copyWith(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _HomeCategoryBlock extends StatelessWidget {
  const _HomeCategoryBlock({
    required this.cats,
    required this.activeKey,
    required this.onSelect,
  });

  final List<CategoryItem> cats;
  final String activeKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: t.accent.withValues(alpha: 0.12),
                  border: Border.all(color: t.accent.withValues(alpha: 0.25)),
                ),
                child: Icon(Ionicons.grid_outline, size: 14, color: t.accent),
              ),
              const SizedBox(width: 10),
              Text(
                'Makundi',
                style: rajdhani(13, weight: FontWeight.w800).copyWith(
                  color: t.text,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                'Chuja maudhui',
                style: rajdhani(11, weight: FontWeight.w600).copyWith(color: t.text2),
              ),
            ],
          ),
        ),
        CatPillStrip(
          children: [
            for (final cat in cats)
              CatPill(
                label: cat.label,
                icon: cat.icon,
                categoryKey: cat.key,
                active: activeKey == cat.key,
                onPress: () => onSelect(cat.key),
              ),
          ],
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
    final t = context.watch<ThemeController>().colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [t.accent.withValues(alpha: 0.14), t.card.withValues(alpha: 0.9)],
        ),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering_error_rounded, color: t.accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: rajdhani(12, weight: FontWeight.w600).copyWith(color: t.text2)),
          ),
          TextButton(onPressed: onRetry, child: Text('Jaribu', style: TextStyle(color: t.accent))),
        ],
      ),
    );
  }
}

String _sectionEmojiForTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('mpira') || lower.contains('sport')) return _catEmoji('mpira');
  if (lower.contains('tamthilia') || lower.contains('movie')) return _catEmoji('tamthilia');
  if (lower.contains('habari') || lower.contains('news')) return _catEmoji('habari');
  if (lower.contains('bure') || lower.contains('free')) return '🆓';
  if (lower.contains('search')) return '🔎';
  return '📺';
}

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({
    required this.item,
    required this.colors,
    this.isActive = true,
  });

  final CarouselSlide item;
  final AppThemeColors colors;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.card),
        SafeNetworkImage(
          imageUrl: item.img,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          placeholderColor: colors.card,
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
          Positioned(
            top: 14,
            left: 14,
            child: PremiumLiveBadge(label: item.badge.isNotEmpty ? item.badge : 'LIVE'),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                'MAUDHUI',
                style: orbitron(7, weight: FontWeight.w800).copyWith(color: colors.premium, letterSpacing: 1),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: inter(22, weight: FontWeight.w900).copyWith(
                    color: Colors.white,
                    height: 1.1,
                    letterSpacing: -0.5,
                    shadows: const [Shadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, 4))],
                  ),
                ),
                const SizedBox(height: 12),
                const PremiumWatchChip(),
              ],
            ),
          ),
        ],
    );
  }
}

class _HomeChannelSectionHeader extends StatelessWidget {
  const _HomeChannelSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final emoji = _sectionEmojiForTitle(title);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.accent.withValues(alpha: 0.22), t.card.withValues(alpha: 0.85)],
            ),
            border: Border.all(color: t.border.withValues(alpha: 0.45)),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: rajdhani(14, weight: FontWeight.w800).copyWith(
                  color: t.text,
                  letterSpacing: 0.9,
                  height: 1.05,
                ),
              ),
              Text(
                '$count channel${count == 1 ? '' : 's'}',
                style: rajdhani(11, weight: FontWeight.w600).copyWith(color: t.text2),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(colors: [t.accent.withValues(alpha: 0.2), t.card.withValues(alpha: 0.6)]),
            border: Border.all(color: t.accent.withValues(alpha: 0.35)),
          ),
          child: Text(
            '$count',
            style: rajdhani(11, weight: FontWeight.w800).copyWith(color: t.accent),
          ),
        ),
      ],
    );
  }
}

class _ChannelGridSection extends StatelessWidget {
  const _ChannelGridSection({
    required this.title,
    required this.channels,
    required this.lockedFor,
    required this.onChannel,
  });

  final String title;
  final List<Channel> channels;
  final bool Function(Channel) lockedFor;
  final void Function(Channel) onChannel;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    final w = MediaQuery.sizeOf(context).width;
    const hPad = 18.0;
    const gap = 10.0;
    final cellW = (w - hPad * 2 - gap) / 2;
    // Must match [ChannelCard] `compactGrid` poster height — do not scale down or overflow stripes appear.
    final tileH = channelGridCellHeight(cellW).clamp(56.0, double.infinity);

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(hPad, 4, hPad, 12),
            child: _HomeChannelSectionHeader(title: title, count: channels.length),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: hPad),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
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
          ),
        ],
      ),
    );
  }
}

class _ChannelRail extends StatefulWidget {
  _ChannelRail({
    required this.title,
    required this.tileWidth,
    required this.railHeight,
    required this.channels,
    required this.lockedFor,
    required this.onChannel,
    this.railPosterHeightDelta,
  });

  final String title;
  final double tileWidth;
  final double railHeight;
  final double? railPosterHeightDelta;
  final List<Channel> channels;
  final bool Function(Channel) lockedFor;
  final void Function(Channel) onChannel;

  @override
  State<_ChannelRail> createState() => _ChannelRailState();
}

class _ChannelRailState extends State<_ChannelRail> {
  static bool _scrollHintPlayed = false;

  final ScrollController _scrollController = ScrollController();
  bool _showScrollHint = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playScrollHintOnce());
  }

  Future<void> _playScrollHintOnce() async {
    if (_scrollHintPlayed || widget.channels.length < 2) return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || !_scrollController.hasClients) return;
    final maxOffset = _scrollController.position.maxScrollExtent;
    if (maxOffset < 24) return;

    _scrollHintPlayed = true;
    setState(() => _showScrollHint = true);

    final peekOffset = maxOffset.clamp(0.0, 56.0);
    await _scrollController.animateTo(
      peekOffset,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (mounted) setState(() => _showScrollHint = false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    if (widget.channels.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: _HomeChannelSectionHeader(title: widget.title, count: widget.channels.length),
          ),
          SizedBox(
            height: widget.railHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, _kRailListBottomPadding),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: widget.channels.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final ch = widget.channels[i];
                    return ChannelCard(
                      width: widget.tileWidth,
                      railPosterHeightDelta: widget.railPosterHeightDelta ?? _kRailPosterHeightDelta,
                      channel: ch,
                      locked: widget.lockedFor(ch),
                      onPress: () => widget.onChannel(ch),
                    );
                  },
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 22,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [t.bg1.withValues(alpha: 0.92), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 36,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [t.bg1.withValues(alpha: 0.95), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 12,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showScrollHint ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [
                              t.accent.withValues(alpha: 0.92),
                              t.accent2.withValues(alpha: 0.86),
                            ],
                          ),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.38),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.26),
                              blurRadius: 24,
                              spreadRadius: -6,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.swipe_left_rounded, size: 18, color: Colors.black),
                              const SizedBox(width: 7),
                              Text(
                                'Vuta kulia kuona channel zaidi',
                                style: rajdhani(12.5, weight: FontWeight.w900).copyWith(
                                  color: Colors.black,
                                  letterSpacing: 0.2,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
