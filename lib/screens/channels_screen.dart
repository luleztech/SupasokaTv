import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payment_screen.dart';
import 'package:supasoka/screens/player_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';
import 'package:supasoka/widgets/channel_card.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  /// `all` | `free` | `premium` | category key (e.g. `football`, `mpira`).
  String _filterKey = 'all';
  String _query = '';
  bool _searchOpen = false;
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  List<String> _filterKeys(List<Channel> channels) {
    final cats = channels.map((c) => c.cat).toSet().toList()..sort();
    return ['all', 'free', 'premium', ...cats];
  }

  String _filterLabel(String key) {
    switch (key) {
      case 'all':
        return 'All';
      case 'free':
        return 'Free';
      case 'premium':
        return 'Premium';
      default:
        return categoryPillLabel(key);
    }
  }

  List<Channel> _filtered(List<Channel> channels, String filterKey) {
    var list = List<Channel>.from(channels);
    switch (filterKey) {
      case 'all':
        break;
      case 'free':
        list = list.where((c) => c.free).toList();
        break;
      case 'premium':
        list = list.where((c) => !c.free).toList();
        break;
      default:
        list = list.where((c) => c.cat == filterKey).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(q) || c.cat.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  void _openChannel(BuildContext context, int channelId) {
    final store = context.read<ContentStore>();
    final ch = store.channelById(channelId);
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
    final keys = _filterKeys(channels);
    final fk = keys.contains(_filterKey) ? _filterKey : 'all';
    final w = MediaQuery.sizeOf(context).width;
    final cellW = (w - 32 - 14) / 2;
    final list = _filtered(channels, fk);

    return ColoredBox(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            title: 'Channels',
            subtitle: 'ALL STREAMS',
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
          AnimatedCrossFade(
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
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: keys.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final opt = keys[i];
                final active = fk == opt;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _filterKey = opt),
                    borderRadius: BorderRadius.circular(99),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: active ? LinearGradient(colors: [t.accent, t.accent2]) : null,
                        color: active ? null : t.card,
                        border: active ? null : Border.all(color: t.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      child: Center(
                        child: Text(
                          _filterLabel(opt),
                          style: rajdhani(13, weight: FontWeight.w600).copyWith(color: active ? Colors.black : t.text2),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_query.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text.rich(
                TextSpan(
                  style: rajdhani(12).copyWith(color: t.text2),
                  children: [
                    TextSpan(text: '${list.length} result${list.length == 1 ? '' : 's'} for '),
                    TextSpan(text: '"$_query"', style: TextStyle(color: t.accent)),
                  ],
                ),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Ionicons.search_outline, size: 40, color: t.border),
                        const SizedBox(height: 12),
                        Text('No channels found', style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text2)),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: cellW / kChannelCardGridHeight,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final ch = list[i];
                      return ChannelCard(channel: ch, onPress: () => _openChannel(context, ch.id));
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
