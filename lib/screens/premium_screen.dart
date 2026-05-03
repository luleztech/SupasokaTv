import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';
import 'package:supasoka/widgets/app_header.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> with SingleTickerProviderStateMixin {
  String? _pkg;
  String _phone = '';
  bool _confirm = false;
  late final AnimationController _crown = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _crown.dispose();
    super.dispose();
  }

  void _activate(BuildContext context) {
    if (_pkg == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a package first!')));
      return;
    }
    if (_phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your phone number!')));
      return;
    }
    setState(() => _confirm = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final packages = context.watch<ContentStore>().premiumPackages;

    return Stack(
      children: [
        ColoredBox(
          color: t.bg1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 20, 12),
                child: Row(
                  children: [
                    BackBtn(onPress: () => Navigator.of(context).pop()),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (b) => LinearGradient(colors: [t.accent, t.accent2]).createShader(b),
                          child: Text('Premium', style: orbitron(20, weight: FontWeight.w900).copyWith(color: Colors.white)),
                        ),
                        Text('UNLOCK ALL', style: orbitron(10).copyWith(color: t.text2, letterSpacing: 4)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _crown, curve: Curves.easeInOut)),
                      child: const Center(child: Text('👑', style: TextStyle(fontSize: 52))),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text('Go Premium', style: orbitron(22, weight: FontWeight.w900).copyWith(color: const Color(0xFFffd700))),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text(
                        'Unlock all channels, HD quality,\nand no interruptions',
                        textAlign: TextAlign.center,
                        style: rajdhani(14).copyWith(color: t.text2, height: 1.5),
                      ),
                    ),
                    if (packages.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Hakuna vifurushi vilivyopangwa. Jaribu tena baadaye.',
                          textAlign: TextAlign.center,
                          style: rajdhani(13).copyWith(color: t.text2),
                        ),
                      )
                    else
                      ...packages.map(
                        (pkg) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Material(
                            color: t.card,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: _pkg == pkg.id ? t.accent : pkg.popular ? const Color(0xFFffd700) : t.border,
                                width: _pkg == pkg.id || pkg.popular ? 2 : 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => setState(() => _pkg = pkg.id),
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (pkg.popular)
                                      Align(
                                        alignment: Alignment.topRight,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(color: const Color(0xFFffd700), borderRadius: BorderRadius.circular(99)),
                                          child: Text('⭐ BEST VALUE', style: orbitron(8).copyWith(color: Colors.black, letterSpacing: 1)),
                                        ),
                                      ),
                                    Text(pkg.name, style: orbitron(15).copyWith(color: t.text)),
                                    const SizedBox(height: 4),
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: pkg.price, style: orbitron(26, weight: FontWeight.w900).copyWith(color: t.accent)),
                                          TextSpan(text: pkg.period, style: rajdhani(14).copyWith(color: t.text2)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: pkg.features
                                          .map(
                                            (f) => Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.05),
                                                borderRadius: BorderRadius.circular(99),
                                              ),
                                              child: Text('✓ $f', style: rajdhani(11).copyWith(color: t.text2)),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📱 Phone Number (M-PESA)', style: rajdhani(12, weight: FontWeight.w600).copyWith(color: t.text2, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          TextField(
                            spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                            onChanged: (v) => setState(() => _phone = v),
                            keyboardType: TextInputType.phone,
                            style: rajdhani(16, weight: FontWeight.w600).copyWith(color: t.text),
                            decoration: InputDecoration(
                              hintText: 'e.g. 0712 345 678',
                              filled: true,
                              fillColor: t.card,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _activate(context),
                              borderRadius: BorderRadius.circular(99),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  gradient: LinearGradient(colors: [t.accent, t.accent2]),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text('⚡ Activate Subscription', style: orbitron(14).copyWith(color: Colors.white, letterSpacing: 1)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_confirm)
          GestureDetector(
            onTap: () => setState(() => _confirm = false),
            child: ModalBarrier(color: Colors.black.withValues(alpha: 0.85)),
          ),
        if (_confirm)
          Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: t.bg2, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.border)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [t.accent, t.accent2]),
                        boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.5), blurRadius: 30)],
                      ),
                      alignment: Alignment.center,
                      child: const Text('✓', style: TextStyle(fontSize: 40, color: Colors.white)),
                    ),
                    const SizedBox(height: 20),
                    Text('Subscription Activated!', style: orbitron(18).copyWith(color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(
                      'Your premium package is now active.\nEnjoy unlimited streaming!',
                      textAlign: TextAlign.center,
                      style: rajdhani(14).copyWith(color: t.text2, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _confirm = false);
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: t.border),
                        backgroundColor: t.card,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                      ),
                      child: Text('Continue Watching', style: orbitron(12).copyWith(color: t.text)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

}
