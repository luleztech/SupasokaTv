import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:url_launcher/url_launcher.dart';

/// Visual gap from the bottom of the hosting viewport to the FAB (tab screens sit *above*
/// [Scaffold.bottomNavigationBar], so do not add tab-bar height here — that pushed the icon mid-screen).
const double kWhatsAppFabGapAboveBottom = 20;

class WhatsAppFab extends StatefulWidget {
  const WhatsAppFab({super.key, this.gapAboveBottom = kWhatsAppFabGapAboveBottom});

  /// Distance from the FAB’s bottom edge to the bottom of the parent [Stack] / viewport.
  final double gapAboveBottom;

  @override
  State<WhatsAppFab> createState() => _WhatsAppFabState();
}

class _WhatsAppFabState extends State<WhatsAppFab> with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  late final AnimationController _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _floatY = Tween<double>(begin: 0, end: -5).animate(CurvedAnimation(parent: _bob, curve: Curves.easeInOut));

  static const double _fabSize = 56;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _entry.forward();
    });
  }

  @override
  void dispose() {
    _bob.dispose();
    _entry.dispose();
    super.dispose();
  }

  Future<void> _open(String digits) async {
    final whatsappUri = Uri.parse('whatsapp://send?phone=$digits');
    final webUri = Uri.parse('https://wa.me/$digits');

    try {
      final ok = await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}

    try {
      final ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp. Please ensure it is installed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ContentStore>();
    if (!store.hasValidCustomerCare) {
      return const SizedBox.shrink();
    }
    final digits = store.customerCareWhatsapp.replaceAll(RegExp(r'\D'), '');
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottom = widget.gapAboveBottom + safeBottom;

    // Fixed hit target: ScaleTransition can shrink the child to zero hit area during the entry
    // animation — wrap with an opaque GestureDetector so taps always register.
    return Positioned(
      right: 18,
      bottom: bottom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(digits),
        child: SizedBox(
          width: _fabSize,
          height: _fabSize,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _entry, curve: Curves.elasticOut),
            child: AnimatedBuilder(
              animation: _floatY,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _floatY.value),
                child: child,
              ),
              child: Material(
                elevation: 16,
                shadowColor: const Color(0xFF25d366),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2bde73), Color(0xFF25d366), Color(0xFF128c7e)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  width: _fabSize,
                  height: _fabSize,
                  child: const Icon(Ionicons.logo_whatsapp, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
