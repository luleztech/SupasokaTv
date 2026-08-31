import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/force_update_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supatv/widgets/tv_channel_sidebar.dart';
import 'package:supatv/widgets/tv_embedded_player.dart';
import 'package:supatv/widgets/tv_premium_gate.dart';
import 'package:supatv/widgets/tv_user_panel.dart';

/// Channels left; player right; D-pad: ↑↓ channels, → user/expand, ← back to list.
class TvShellScreen extends StatefulWidget {
  const TvShellScreen({super.key, required this.contentStore});

  final ContentStore contentStore;

  @override
  State<TvShellScreen> createState() => _TvShellScreenState();
}

class _TvShellScreenState extends State<TvShellScreen> {
  static const _sidebarWidth = 320.0;

  int? _selectedChannelId;
  bool _fullscreen = false;
  bool _showUserPanel = false;
  bool _showPremiumGate = false;
  Channel? _blockedChannel;
  Timer? _metaPoll;

  final FocusNode _shellFocus = FocusNode(debugLabel: 'tv-shell');
  final FocusNode _userBtnFocus = FocusNode(debugLabel: 'tv-user-btn');
  final FocusNode _expandBtnFocus = FocusNode(debugLabel: 'tv-expand-btn');
  final FocusNode _backBtnFocus = FocusNode(debugLabel: 'tv-back-btn');
  final FocusScopeNode _sidebarScope = FocusScopeNode(debugLabel: 'tv-sidebar');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pickInitialChannel();
      _startMetaPoll();
      _sidebarScope.requestFocus();
    });
  }

  void _startMetaPoll() {
    _metaPoll?.cancel();
    _metaPoll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || _showPremiumGate || _showUserPanel) return;
      unawaited(widget.contentStore.pollConfigMeta());
      unawaited(SubscriptionStore.syncPremiumFromBackend());
    });
  }

  void _pickInitialChannel() {
    final store = widget.contentStore;
    final channels = store.channels;
    if (channels.isEmpty) return;

    Channel? pick;
    for (final c in channels) {
      if (c.free) {
        pick = c;
        break;
      }
    }
    pick ??= channels.first;
    if (_selectedChannelId == null) {
      setState(() => _selectedChannelId = pick!.id);
    }
  }

  bool _canPlay(Channel channel) {
    if (channel.free) return true;
    return SubscriptionStore.isPremiumActiveLocal();
  }

  Future<void> _onChannelSelected(Channel channel) async {
    if (!_canPlay(channel)) {
      setState(() {
        _blockedChannel = channel;
        _showPremiumGate = true;
        _showUserPanel = false;
      });
      return;
    }
    if (_selectedChannelId == channel.id) return;
    setState(() {
      _showPremiumGate = false;
      _blockedChannel = null;
      _selectedChannelId = channel.id;
    });
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_fullscreen) {
        _backBtnFocus.requestFocus();
      } else {
        _sidebarScope.requestFocus();
      }
    });
  }

  void _openUserPanel() {
    setState(() {
      _showUserPanel = true;
      _showPremiumGate = false;
    });
  }

  void _focusPlayerControls() {
    if (_fullscreen) {
      _backBtnFocus.requestFocus();
      return;
    }
    if (_expandBtnFocus.canRequestFocus) {
      _expandBtnFocus.requestFocus();
    } else {
      _userBtnFocus.requestFocus();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_showUserPanel) {
        setState(() => _showUserPanel = false);
        _sidebarScope.requestFocus();
        return KeyEventResult.handled;
      }
      if (_showPremiumGate) {
        setState(() => _showPremiumGate = false);
        _sidebarScope.requestFocus();
        return KeyEventResult.handled;
      }
      if (_fullscreen) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_showUserPanel || _showPremiumGate) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.mediaPlayPause) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    // From channel list, Right jumps to player controls / user icon.
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaTrackNext) {
      if (_sidebarScope.hasFocus || _sidebarScope.hasPrimaryFocus) {
        _focusPlayerControls();
        return KeyEventResult.handled;
      }
    }

    // From player controls, Left returns to channel list.
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (_userBtnFocus.hasFocus || _expandBtnFocus.hasFocus || _backBtnFocus.hasFocus) {
        _sidebarScope.requestFocus();
        return KeyEventResult.handled;
      }
    }

    // Channel up/down when not in sidebar (quick zap).
    if (!_sidebarScope.hasFocus &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.channelUp ||
            key == LogicalKeyboardKey.channelDown ||
            key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.pageDown)) {
      final down = key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.channelDown ||
          key == LogicalKeyboardKey.pageDown;
      _zapChannel(down: down);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _zapChannel({required bool down}) {
    final channels = widget.contentStore.channels;
    if (channels.isEmpty) return;
    final idx = channels.indexWhere((c) => c.id == _selectedChannelId);
    final current = idx < 0 ? 0 : idx;
    final next = (current + (down ? 1 : -1) + channels.length) % channels.length;
    unawaited(_onChannelSelected(channels[next]));
  }

  @override
  void dispose() {
    _metaPoll?.cancel();
    _shellFocus.dispose();
    _userBtnFocus.dispose();
    _expandBtnFocus.dispose();
    _backBtnFocus.dispose();
    _sidebarScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ContentStore>();

    if (store.updateRequired) {
      final update = store.appUpdateStatus;
      return ForceUpdateScreen(
        currentVersion: update.currentVersion,
        currentBuild: update.currentBuild,
        minVersion: update.minVersion,
        latestVersion: update.latestVersion,
        minBuild: update.minBuild,
        latestBuild: update.latestBuild,
        playStoreUrl: update.playStoreUrl,
        onRecheck: () => store.checkUpdateFromServer(),
      );
    }

    final channels = store.channels;
    final selected = _selectedChannelId != null ? store.channelById(_selectedChannelId!) : null;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      child: Focus(
        focusNode: _shellFocus,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
          backgroundColor: BrandPalette.bgDeep,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Single player instance — survives fullscreen toggle without restart.
              if (selected != null)
                Positioned(
                  left: _fullscreen ? 0 : _sidebarWidth,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: TvEmbeddedPlayer(
                    key: ValueKey<int>(selected.id),
                    channel: selected,
                    fullscreen: _fullscreen,
                    expandFocusNode: _expandBtnFocus,
                    onToggleFullscreen: _toggleFullscreen,
                    onPremiumRequired: () {
                      setState(() {
                        _blockedChannel = selected;
                        _showPremiumGate = true;
                      });
                    },
                  ),
                )
              else
                const Center(
                  child: Text(
                    'Hakuna vituo vya kutazama bado.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),

              if (!_fullscreen)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _sidebarWidth,
                  child: FocusScope(
                    node: _sidebarScope,
                    child: TvChannelSidebar(
                      channels: channels,
                      selectedId: _selectedChannelId,
                      loading: !store.ready,
                      error: store.loadError,
                      onRefresh: () => store.refresh(),
                      onSelected: _onChannelSelected,
                      onMoveToPlayer: _focusPlayerControls,
                    ),
                  ),
                ),

              if (!_fullscreen && selected != null)
                Positioned(
                  left: _sidebarWidth + 16,
                  top: 12,
                  right: 72,
                  child: IgnorePointer(
                    child: Text(
                      selected.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: BrandPalette.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.85),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (!_fullscreen)
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: _TvFocusCircleButton(
                      focusNode: _userBtnFocus,
                      tooltip: 'Akaunti & ubora',
                      icon: Icons.person_rounded,
                      onPressed: _openUserPanel,
                      onLeft: () => _sidebarScope.requestFocus(),
                      onDown: () {
                        if (_expandBtnFocus.canRequestFocus) {
                          _expandBtnFocus.requestFocus();
                        }
                      },
                    ),
                  ),
                ),

              if (_fullscreen)
                Positioned(
                  top: 12,
                  left: 12,
                  child: SafeArea(
                    child: _TvFocusPillButton(
                      focusNode: _backBtnFocus,
                      tooltip: 'Rudi',
                      icon: Icons.arrow_back_rounded,
                      label: 'Rudi',
                      onPressed: _toggleFullscreen,
                    ),
                  ),
                ),

              if (_showUserPanel)
                TvUserPanel(
                  onClose: () {
                    setState(() => _showUserPanel = false);
                    _sidebarScope.requestFocus();
                  },
                  onOpenPremium: () => setState(() {
                    _showUserPanel = false;
                    _blockedChannel = null;
                    _showPremiumGate = true;
                  }),
                ),

              if (_showPremiumGate)
                TvPremiumGate(
                  channel: _blockedChannel,
                  onClose: () {
                    setState(() => _showPremiumGate = false);
                    _sidebarScope.requestFocus();
                  },
                  onPaymentSuccess: () async {
                    if (!mounted) return;
                    final ch = _blockedChannel;
                    setState(() {
                      _showPremiumGate = false;
                      _blockedChannel = null;
                      if (ch != null) _selectedChannelId = ch.id;
                    });
                    _sidebarScope.requestFocus();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvFocusCircleButton extends StatefulWidget {
  const _TvFocusCircleButton({
    required this.focusNode,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.onLeft,
    this.onDown,
  });

  final FocusNode focusNode;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLeft;
  final VoidCallback? onDown;

  @override
  State<_TvFocusCircleButton> createState() => _TvFocusCircleButtonState();
}

class _TvFocusCircleButtonState extends State<_TvFocusCircleButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.space) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onLeft?.call();
          return widget.onLeft != null ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          widget.onDown?.call();
          return widget.onDown != null ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: _focused ? BrandPalette.accent : Colors.black54,
        shape: const CircleBorder(),
        elevation: _focused ? 8 : 0,
        child: IconButton(
          tooltip: widget.tooltip,
          onPressed: widget.onPressed,
          icon: Icon(widget.icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _TvFocusPillButton extends StatefulWidget {
  const _TvFocusPillButton({
    required this.focusNode,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_TvFocusPillButton> createState() => _TvFocusPillButtonState();
}

class _TvFocusPillButtonState extends State<_TvFocusPillButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.space) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: _focused ? BrandPalette.accent : Colors.black54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(99),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
