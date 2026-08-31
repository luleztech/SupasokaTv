import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supasoka/util/image_url.dart';

class TvChannelSidebar extends StatefulWidget {
  const TvChannelSidebar({
    super.key,
    required this.channels,
    required this.selectedId,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onSelected,
    this.onMoveToPlayer,
  });

  final List<Channel> channels;
  final int? selectedId;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<Channel> onSelected;
  /// Called when remote Right is pressed on a channel tile.
  final VoidCallback? onMoveToPlayer;

  @override
  State<TvChannelSidebar> createState() => _TvChannelSidebarState();
}

class _TvChannelSidebarState extends State<TvChannelSidebar> {
  final _scroll = ScrollController();
  final Map<int, FocusNode> _tileFocus = {};

  FocusNode _nodeFor(int channelId) =>
      _tileFocus.putIfAbsent(channelId, () => FocusNode(debugLabel: 'ch-$channelId'));

  @override
  void didUpdateWidget(covariant TvChannelSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveIds = widget.channels.map((c) => c.id).toSet();
    final stale = _tileFocus.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in stale) {
      _tileFocus.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final n in _tileFocus.values) {
      n.dispose();
    }
    _tileFocus.clear();
    _scroll.dispose();
    super.dispose();
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    const approxTile = 78.0;
    final target = (index * approxTile) - 80;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: BrandPalette.bgMid,
        border: Border(right: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Vituo',
                    style: TextStyle(
                      color: BrandPalette.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => widget.onRefresh(),
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  ),
              ],
            ),
          ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                widget.error!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            )
          else if (!widget.loading && widget.channels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Hakuna vituo kutoka seva. Bonyeza refresh au sasisha app.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),
          Expanded(
            child: widget.channels.isEmpty
                ? Center(
                    child: Text(
                      widget.loading ? 'Inapakia…' : 'Hakuna vituo.',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: widget.channels.length,
                    itemBuilder: (context, index) {
                      final ch = widget.channels[index];
                      final node = _nodeFor(ch.id);
                      return _ChannelTile(
                        focusNode: node,
                        autofocus: (index == 0 && widget.selectedId == null) ||
                            ch.id == widget.selectedId,
                        channel: ch,
                        selected: ch.id == widget.selectedId,
                        locked: !ch.free && !SubscriptionStore.isPremiumActiveLocal(),
                        onTap: () => widget.onSelected(ch),
                        onFocused: () => _ensureVisible(index),
                        onMoveRight: widget.onMoveToPlayer,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.focusNode,
    required this.autofocus,
    required this.channel,
    required this.selected,
    required this.locked,
    required this.onTap,
    required this.onFocused,
    this.onMoveRight,
  });

  final FocusNode focusNode;
  final bool autofocus;
  final Channel channel;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback onFocused;
  final VoidCallback? onMoveRight;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final img = sanitizeImageUrl(widget.channel.img);
    final highlight = widget.selected || _focused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (v) {
          setState(() => _focused = v);
          if (v) widget.onFocused();
        },
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onMoveRight?.call();
            return widget.onMoveRight != null ? KeyEventResult.handled : KeyEventResult.ignored;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: highlight ? BrandPalette.accent.withValues(alpha: 0.18) : Colors.transparent,
                border: Border.all(
                  color: highlight ? BrandPalette.accent : Colors.white12,
                  width: highlight ? 2.5 : 1,
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: BrandPalette.accent.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: img.isEmpty
                        ? Container(
                            width: 56,
                            height: 56,
                            color: BrandPalette.bgDeep,
                            alignment: Alignment.center,
                            child: const Icon(Icons.live_tv_rounded, color: Colors.white38),
                          )
                        : CachedNetworkImage(
                            imageUrl: img,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            memCacheWidth: 112,
                            memCacheHeight: 112,
                            errorWidget: (context, url, error) => Container(
                              width: 56,
                              height: 56,
                              color: BrandPalette.bgDeep,
                              child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: BrandPalette.white,
                            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (widget.channel.free)
                              const _Badge(label: 'BURE', color: BrandPalette.accent)
                            else if (widget.locked)
                              const _Badge(label: 'PREMIUM', color: BrandPalette.accentWarm)
                            else
                              const _Badge(label: 'WAZO', color: Color(0xFF34D399)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.locked)
                    const Icon(Icons.lock_rounded, color: BrandPalette.accentWarm, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
