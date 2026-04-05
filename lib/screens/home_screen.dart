import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/player_screen.dart';
import 'package:supasoka/screens/settings_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';
import 'package:supasoka/widgets/cat_pill.dart';
import 'package:supasoka/widgets/channel_card.dart';
import 'package:supasoka/widgets/section_title.dart';
import 'package:supasoka/widgets/whatsapp_fab.dart';

IconData _badgeIcon(String name) {
  switch (name) {
    case 'radio-outline':
      return Ionicons.radio_outline;
    case 'film-outline':
      return Ionicons.film_outline;
    case 'trophy-outline':
      return Ionicons.trophy_outline;
    case 'musical-notes-outline':
      return Ionicons.musical_notes_outline;
    default:
      return Ionicons.radio_outline;
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

  List<Channel> _filteredChannels(List<Channel> channels, String catKey) {
    var list = catKey == 'all' ? channels : channels.where((c) => c.cat == catKey).toList();
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((c) {
      if (c.name.toLowerCase().contains(q)) return true;
      if (c.cat.toLowerCase().contains(q)) return true;
      final label = kCatLabel[c.cat] ?? c.cat;
      if (label.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final slides = context.read<ContentStore>().carouselSlides;
      if (slides.isEmpty) return;
      final next = (_carouselIndex + 1) % slides.length;
      setState(() => _carouselIndex = next);
      _carousel.animateToPage(next, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
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
    if (ch != null && !ch.free) {
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
    final w = MediaQuery.sizeOf(context).width;
    final cellW = (w - 32 - 14) / 2;
    final filtered = _filteredChannels(channels, fk);

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
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off_outlined, color: t.accent, size: 20),
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
                  subtitle: 'LIVE TV & MOVIES',
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
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _searchOpen ? t.accent : t.border, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Ionicons.search_outline, size: 16, color: t.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              focusNode: _searchFocus,
                              onChanged: (v) => setState(() => _query = v),
                              style: rajdhani(15, weight: FontWeight.w600).copyWith(color: t.text),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: 'Search channels...',
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
              SliverToBoxAdapter(
                child: carouselSlides.isEmpty
                    ? const SizedBox.shrink()
                    : SizedBox(
                        height: 220,
                        child: PageView.builder(
                          controller: _carousel,
                          itemCount: carouselSlides.length,
                          onPageChanged: (i) => setState(() => _carouselIndex = i),
                          itemBuilder: (context, i) {
                            final item = carouselSlides[i];
                            return _CarouselSlide(
                              item: item,
                              width: w,
                              onWatch: () => _openChannel(context, item.channelId),
                            );
                          },
                        ),
                      ),
              ),
              SliverToBoxAdapter(
                child: carouselSlides.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12, right: 20),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(carouselSlides.length, (i) {
                              final active = i == _carouselIndex;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _carouselIndex = i);
                                  _carousel.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.only(left: 5),
                                  width: active ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: active ? t.accent : Colors.white.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
              ),
              SliverToBoxAdapter(child: SectionTitle(main: 'BROWSE', accent: 'CATEGORIES')),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: cats.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
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
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(child: SectionTitle(main: 'FEATURED', accent: 'CHANNELS')),
              if (_query.trim().isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
              if (filtered.isEmpty)
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
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: cellW / kChannelCardGridHeight,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final ch = filtered[i];
                        return ChannelCard(channel: ch, onPress: () => _openChannel(context, ch.id));
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
            ],
            ),
          ),
        ),
        const WhatsAppFab(),
      ],
    );
  }
}

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({required this.item, required this.width, required this.onWatch});

  final CarouselSlide item;
  final double width;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    return SizedBox(
      width: width,
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(imageUrl: item.img, fit: BoxFit.cover),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_badgeIcon(item.badgeIcon), size: 9, color: Colors.black),
                      const SizedBox(width: 5),
                      Text(
                        item.badge,
                        style: orbitron(9, weight: FontWeight.w700).copyWith(color: Colors.black, letterSpacing: 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: orbitron(22, weight: FontWeight.w700).copyWith(color: Colors.white, height: 1.25),
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onWatch,
                    borderRadius: BorderRadius.circular(99),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: LinearGradient(colors: [t.accent, t.accent2]),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      child: Text(
                        '▶ Watch Now',
                        style: orbitron(11, weight: FontWeight.w700).copyWith(color: Colors.white, letterSpacing: 1),
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
