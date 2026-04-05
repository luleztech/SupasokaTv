import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/pay_plan.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

const _mpesa = Color(0xFF00c853);

bool _validPhone(String p) {
  final s = p.replaceAll(RegExp(r'\s'), '');
  return RegExp(r'^(07|06|01)\d{8}$').hasMatch(s);
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String? _planId;
  String _phone = '';
  bool _phoneFocused = false;

  PayPlan? _selectedPlan(List<PayPlan> plans) {
    if (_planId == null) return null;
    for (final p in plans) {
      if (p.id == _planId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final plans = context.watch<ContentStore>().malipoPayPlans;
    final selectedPlan = _selectedPlan(plans);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final w = MediaQuery.sizeOf(context).width;
    final cardGap = 10.0;
    final cardW = (w - 32 - cardGap * 2) / 3;
    final phoneOk = _validPhone(_phone);

    return ColoredBox(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaymentHeader(t: t, top: MediaQuery.paddingOf(context).top),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Text(
                  'Chagua kifurushi',
                  style: rajdhani(13, weight: FontWeight.w700).copyWith(color: t.text2, letterSpacing: 0.8),
                ),
                const SizedBox(height: 12),
                if (plans.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Hakuna mipango ya malipo. Wasiliana na msaada.',
                      style: rajdhani(13).copyWith(color: t.text2),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < plans.length; i++)
                        Padding(
                          padding: EdgeInsets.only(right: i < plans.length - 1 ? cardGap : 0),
                          child: _PlanCard(
                            plan: plans[i],
                            width: cardW,
                            selected: _planId == plans[i].id,
                            theme: t,
                            onTap: () => setState(() {
                              _planId = _planId == plans[i].id ? null : plans[i].id;
                              if (_planId == null) _phone = '';
                            }),
                          ),
                        ),
                    ],
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: _planId == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Malipo kwa M-Pesa',
                                style: rajdhani(13, weight: FontWeight.w700).copyWith(color: t.text2, letterSpacing: 0.6),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Ionicons.phone_portrait_outline, size: 16, color: _mpesa),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Nambari iliyosajiliwa kwenye M-Pesa',
                                      style: rajdhani(12, weight: FontWeight.w500).copyWith(color: t.text),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: t.card,
                                      border: Border.all(
                                        color: _phoneFocused
                                            ? _mpesa
                                            : phoneOk
                                                ? _mpesa.withValues(alpha: 0.85)
                                                : t.border,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          child: Row(
                                            children: [
                                              const Text('🇹🇿', style: TextStyle(fontSize: 20)),
                                              const SizedBox(width: 8),
                                              Text(
                                                '+255',
                                                style: rajdhani(14, weight: FontWeight.w700).copyWith(color: t.text2),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(width: 1, height: 26, color: t.border.withValues(alpha: 0.6)),
                                        Expanded(
                                          child: TextField(
                                            onChanged: (v) => setState(() => _phone = v),
                                            onTap: () => setState(() => _phoneFocused = true),
                                            onEditingComplete: () => setState(() => _phoneFocused = false),
                                            keyboardType: TextInputType.phone,
                                            inputFormatters: [LengthLimitingTextInputFormatter(12)],
                                            style: rajdhani(18, weight: FontWeight.w700).copyWith(
                                              color: t.text,
                                              letterSpacing: 1.2,
                                            ),
                                            decoration: InputDecoration(
                                              border: InputBorder.none,
                                              hintText: '07XX XXX XXX',
                                              hintStyle: TextStyle(color: t.text2.withValues(alpha: 0.4)),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                            ),
                                          ),
                                        ),
                                        if (_phone.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 12),
                                            child: Icon(
                                              phoneOk ? Ionicons.checkmark_circle : Ionicons.alert_circle_outline,
                                              color: phoneOk ? _mpesa : const Color(0xFFff8a65),
                                              size: 22,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (selectedPlan != null) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        t.card,
                                        t.bg2.withValues(alpha: 0.9),
                                      ],
                                    ),
                                    border: Border.all(color: t.border.withValues(alpha: 0.8)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _SummaryTile(
                                          label: 'Kifurushi',
                                          value: selectedPlan!.label,
                                          t: t,
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 44,
                                        margin: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              t.border,
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: _SummaryTile(
                                          label: 'Kiasi',
                                          value: selectedPlan!.amount,
                                          t: t,
                                          highlight: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: phoneOk && _planId != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _mpesa.withValues(alpha: 0.45),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        HapticFeedback.mediumImpact();
                                        FocusScope.of(context).unfocus();
                                        final planId = _planId!;
                                        await SubscriptionStore.activatePlan(planId);
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Malipo yamehifadhiwa. Furaha ya Premium!',
                                              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
                                            ),
                                            backgroundColor: _mpesa,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                      child: Ink(
                                        height: 58,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [Color(0xFF00c853), Color(0xFF00e676)],
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Ionicons.lock_closed_outline, color: Colors.white.withValues(alpha: 0.95), size: 18),
                                            const SizedBox(width: 10),
                                            Text(
                                              'LIPIA SASA',
                                              style: orbitron(15, weight: FontWeight.w900).copyWith(
                                                color: Colors.white,
                                                letterSpacing: 4,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.22),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Ionicons.arrow_forward, color: Colors.white, size: 16),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Malipo salama · M-Pesa',
                                textAlign: TextAlign.center,
                                style: rajdhani(11).copyWith(color: t.text2.withValues(alpha: 0.85), letterSpacing: 0.4),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.t,
    this.highlight = false,
  });

  final String label;
  final String value;
  final AppThemeColors t;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: rajdhani(10, weight: FontWeight.w600).copyWith(
            color: t.text2,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: (highlight ? orbitron(14, weight: FontWeight.w900) : orbitron(13, weight: FontWeight.w800)).copyWith(
            color: highlight ? t.accent : t.text,
            letterSpacing: highlight ? 0.3 : 0,
          ),
        ),
      ],
    );
  }
}

class _PaymentHeader extends StatelessWidget {
  const _PaymentHeader({required this.t, required this.top});

  final AppThemeColors t;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            t.bg2.withValues(alpha: 0.5),
            t.bg1,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, top + 12, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (b) => LinearGradient(colors: [t.accent, t.accent2]).createShader(b),
                        child: Text('Malipo', style: orbitron(24, weight: FontWeight.w900).copyWith(color: Colors.white, height: 1.1)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chagua kifurushi na ulipe kwa urahisi',
                        style: rajdhani(13, weight: FontWeight.w500).copyWith(color: t.text2, height: 1.35),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: [t.accent.withValues(alpha: 0.2), t.accent2.withValues(alpha: 0.12)]),
                    border: Border.all(color: t.accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Ionicons.shield_checkmark, size: 14, color: t.accent),
                      const SizedBox(width: 6),
                      Text('SALAMA', style: orbitron(9, weight: FontWeight.w800).copyWith(color: t.accent, letterSpacing: 1.2)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Divider(height: 1, thickness: 1, color: t.border.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.width,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final PayPlan plan;
  final double width;
  final bool selected;
  final AppThemeColors theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: selected
                      ? LinearGradient(
                          colors: [
                            plan.accent1,
                            plan.accent2,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: selected ? null : t.card,
                  border: Border.all(
                    color: selected ? Colors.white.withValues(alpha: 0.35) : t.border,
                    width: selected ? 1.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: plan.accent1.withValues(alpha: 0.45),
                            blurRadius: 20,
                            spreadRadius: 0,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                padding: EdgeInsets.fromLTRB(10, plan.popular ? 22 : 14, 10, 14),
                child: Column(
                  children: [
                    Text(
                      plan.label,
                      style: orbitron(12, weight: FontWeight.w800).copyWith(
                        color: selected ? Colors.white : t.text,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    ShaderMask(
                      shaderCallback: (b) => LinearGradient(
                        colors: selected ? [Colors.white, const Color(0xFFf5f5ff)] : [plan.accent1, plan.accent2],
                      ).createShader(b),
                      child: Text(
                        plan.priceLines,
                        textAlign: TextAlign.center,
                        style: orbitron(14, weight: FontWeight.w900).copyWith(
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.period,
                      style: rajdhani(10, weight: FontWeight.w600).copyWith(
                        color: selected ? Colors.white.withValues(alpha: 0.88) : t.text2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            selected ? Colors.white30 : t.border.withValues(alpha: 0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Ionicons.infinite_outline,
                          size: 11,
                          color: selected ? Colors.white70 : t.accent.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Channels zote',
                            style: rajdhani(9, weight: FontWeight.w700).copyWith(
                              color: selected ? Colors.white.withValues(alpha: 0.92) : t.accent,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (plan.popular)
            Positioned(
              top: -10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF9E40)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.55),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Ionicons.star, size: 11, color: Colors.black.withValues(alpha: 0.75)),
                    const SizedBox(width: 5),
                    Text(
                      plan.badge.isNotEmpty ? plan.badge : 'BORA',
                      style: orbitron(8, weight: FontWeight.w900).copyWith(
                        color: const Color(0xFF1a0a00),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (selected)
            Positioned(
              top: plan.popular ? 18 : 10,
              right: 8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Icon(Ionicons.checkmark, size: 14, color: plan.accent1),
              ),
            ),
        ],
      ),
    );
  }
}
