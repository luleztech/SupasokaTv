import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:url_launcher/url_launcher.dart';

const double kTabBarBaseHeight = 62;

class WhatsAppFab extends StatefulWidget {
  const WhatsAppFab({super.key});

  @override
  State<WhatsAppFab> createState() => _WhatsAppFabState();
}

class _WhatsAppFabState extends State<WhatsAppFab> with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  late final AnimationController _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _floatY = Tween<double>(begin: 0, end: -9).animate(CurvedAnimation(parent: _bob, curve: Curves.easeInOut));

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
    final u = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ContentStore>();
    if (!store.hasValidCustomerCare) {
      return const SizedBox.shrink();
    }
    final digits = store.customerCareWhatsapp.replaceAll(RegExp(r'\D'), '');
    final bottom = MediaQuery.paddingOf(context).bottom + kTabBarBaseHeight + 18;

    return Positioned(
      right: 18,
      bottom: bottom,
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
            child: InkWell(
              onTap: () => _open(digits),
              child: Ink(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2bde73), Color(0xFF25d366), Color(0xFF128c7e)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                width: 56,
                height: 56,
                child: Icon(Ionicons.logo_whatsapp, color: Colors.white, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
