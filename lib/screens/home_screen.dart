import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/player_screen.dart';
import 'package:supasoka/screens/settings_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';
import 'package:supasoka/widgets/cat_pill.dart';
import 'package:supasoka/widgets/channel_card.dart';
import 'package:supasoka/widgets/safe_network_image.dart';
import 'package:supasoka/widgets/whatsapp_fab.dart';

/// Wider horizontal channel cards on Home (was 168).
const double _kRailTileWidth = 248;

double get _kRailHeight => channelRailCellHeight(_kRailTileWidth);

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _cat = 'all';
  String _query = '';
  bool _searchOpen = false;
  final _searchFocus = FocusNode();
  final _carousel = PageController();
  int _carouselIndex = 0;
  Timer? _carouselTimer;

  bool _channelMatchesSearch(Channel c, String needle) {
    if (needle.isEmpty) return true;
    final label = kCatLabel[c.cat] ?? c.cat;
    final haystack = '${c.name} $label ${c.cat} ${c.viewers}'.toLowerCase();
    final tokens = needle.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return true;
    for (final token in tokens) {
      if (!haystack.contains(token)) return false;
    }
    return true;
  }

  /// Category pills apply only when the search box is empty; typing searches all channels.
  List<Channel> _filteredChannels(List<Channel> channels, String catKey) {
    final needle = _query.trim().toLowerCase();
    if (needle.isNotEmpty) {
      return channels.where((c) => _channelMatchesSearch(c, needle)).toList();
    }
    if (catKey == 'all') return channels;
    return channels.where((c) => c.cat == catKey).toList();
  }

  @override
  void initState() {
    super.initState();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final slides = context.read<ContentStore>().carouselSlides;
      if (slides.isEmpty) return;
      final next = (_carouselIndex + 1) % slides.length;
      setState(() => _carouselIndex = next);
      _carousel.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
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
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(channelId: channelId)));
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
      builder: (context, _, __) {
        final isPremium = SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;

        final browseSlivers = <Widget>[];

        if (_query.trim().isNotEmpty) {
          if (filtered.isEmpty) {
            browseSlivers.add(
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Ionicons.search_outline, size: 40, color: t.border),
                      const SizedBox(height: 12),
                      Text('No channels found', style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text2)),
                    ],
                  ),
                ),
              ),
            );
          } else {
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRail(
                  title: '🔎 SEARCH RESULTS',
                  tileWidth: _kRailTileWidth,
                  railHeight: _kRailHeight,
                  channels: filtered,
                  lockedFor: (ch) => !ch.free && !isPremium,
                  onChannel: (ch) => _openChannel(context, ch.id),
                ),
              ),
            );
          }
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
          final liveNow = channels.take(8).toList();
          if (liveNow.isNotEmpty) {
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRail(
                  title: '⚡ LIVE NOW ON SUPASOKA',
                  tileWidth: _kRailTileWidth,
                  railHeight: _kRailHeight,
                  channels: liveNow,
                  lockedFor: (ch) => !ch.free && !isPremium,
                  onChannel: (ch) => _openChannel(context, ch.id),
                ),
              ),
            );
          }
          for (final cat in cats) {
            if (cat.key == 'all') continue;
            final list = channels.where((ch) => ch.cat == cat.key).toList();
            if (list.isEmpty) continue;
            browseSlivers.add(
              SliverToBoxAdapter(
                child: _ChannelRail(
                  title: '${_catEmoji(cat.key)} ${cat.label}',
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
        ColoredBox(
          color: t.bg1,
          child: RefreshIndicator(
            color: t.accent,
            onRefresh: () => context.read<ContentStore>().refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (store.loadError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Material(
                        color: t.card,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: t.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.wifi_tethering_error_rounded, color: t.accent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  store.loadError!,
                                  style: rajdhani(12, weight: FontWeight.w600).copyWith(color: t.text2),
                                ),
                              ),
                              TextButton(
                                onPressed: () => store.refresh(),
                                child: Text('Retry', style: TextStyle(color: t.accent)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: AppHeader(
                    title: 'Supasoka',
                    subtitle: 'Mpira na Tamthilia',
                    onSettings: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                    onSearch: () {
                      setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) {
                          _query = '';
                          _searchFocus.unfocus();
                        } else {
                          Future.microtask(_searchFocus.requestFocus);
                        }
                      });
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xCC18181b),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: _searchOpen ? t.accent : t.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Ionicons.search_outline, size: 16, color: const Color(0xFFa1a1aa)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                                focusNode: _searchFocus,
                                onChanged: (v) => setState(() => _query = v),
                                style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Tafuta channel…',
                                  hintStyle: TextStyle(color: t.text2.withValues(alpha: 0.53)),
                                ),
                              ),
                            ),
                            if (_query.isNotEmpty)
                              IconButton(
                                onPressed: () => setState(() => _query = ''),
                                icon: Icon(Ionicons.close_circle, size: 18, color: t.text2),
                              ),
                          ],
                        ),
                      ),
                    ),
                    crossFadeState: _searchOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 220),
                  ),
                ),
                if (carouselSlides.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 420,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PageView.builder(
                                controller: _carousel,
                                itemCount: carouselSlides.length,
                                onPageChanged: (i) => setState(() => _carouselIndex = i),
                                itemBuilder: (context, i) {
                                  return _CarouselSlide(item: carouselSlides[i], colors: t);
                                },
                              ),
                              Positioned(
                                left: 18,
                                bottom: 18,
                                child: Row(
                                  children: List.generate(carouselSlides.length, (i) {
                                    final active = i == _carouselIndex;
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() => _carouselIndex = i);
                                        _carousel.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        margin: const EdgeInsets.only(right: 6),
                                        height: 2,
                                        width: active ? 32 : 14,
                                        decoration: BoxDecoration(
                                          color: active ? t.accent : const Color(0xFF52525b),
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 22),
                    child: SizedBox(
                      height: 44,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: cats.length,
                        separatorBuilder: (context, _) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          final cat = cats[i];
                          return CatPill(
                            label: cat.label,
                            icon: cat.icon,
                            active: fk == cat.key,
                            onPress: () => setState(() => _cat = cat.key),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (_query.trim().isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: Text.rich(
                        TextSpan(
                          style: rajdhani(12).copyWith(color: t.text2),
                          children: [
                            TextSpan(text: '${filtered.length} result${filtered.length == 1 ? '' : 's'} for '),
                            TextSpan(text: '"$_query"', style: TextStyle(color: t.accent)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ...browseSlivers,
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
        const WhatsAppFab(),
      ],
    );
      },
    );
  }
}

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({required this.item, required this.colors});

  final CarouselSlide item;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SafeNetworkImage(imageUrl: item.img, fit: BoxFit.cover, placeholderColor: colors.card),
        Positioned(
          left: 20,
          right: 24,
          bottom: 36,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: colors.red, borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.badge.toUpperCase(),
                          style: orbitron(8, weight: FontWeight.w900).copyWith(color: Colors.white, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: inter(18, weight: FontWeight.w900).copyWith(
                  color: Colors.white,
                  height: 1.15,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -0.5,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelRail extends StatelessWidget {
  const _ChannelRail({
    required this.title,
    required this.tileWidth,
    required this.railHeight,
    required this.channels,
    required this.lockedFor,
    required this.onChannel,
  });

  final String title;
  final double tileWidth;
  final double railHeight;
  final List<Channel> channels;
  final bool Function(Channel) lockedFor;
  final void Function(Channel) onChannel;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    if (channels.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 3),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 22,
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: rajdhani(17, weight: FontWeight.w800).copyWith(
                      color: const Color(0xFFa1a1aa),
                      letterSpacing: 1.15,
                      height: 1.12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: railHeight,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final ch = channels[i];
                return ChannelCard(
                  width: tileWidth,
                  channel: ch,
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
