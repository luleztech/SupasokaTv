import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/data/pay_plan.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/tanzania_phone.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/zeno_pay_service.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

const _mpesa = Color(0xFF00c853);

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

  Future<void> _runZenoCheckout(BuildContext context) async {
    final plans = context.read<ContentStore>().malipoPayPlans;
    final plan = _selectedPlan(plans);
    if (plan == null) return;

    final normalized = TanzaniaPhone.normalize(_phone);
    if (normalized == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nambari si sahihi kwa Tanzania. Tumia 0XXXXXXXXX au +255…',
            style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
          ),
          backgroundColor: const Color(0xFFc62828),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final amount = ZenoPayService.parseAmountTzs(plan.amount);
    if (amount == null || amount < 1) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kiasi cha TZS hakipatikani kwenye mpango. Hakikisha sehemu ya bei ina nambari (mfano 5000).',
            style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
          ),
          backgroundColor: const Color(0xFFc62828),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();

    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final tt = dialogContext.read<ThemeController>().colors;
        return PopScope(
          canPop: false,
          child: Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: Center(
              child: Material(
                color: tt.card,
                borderRadius: BorderRadius.circular(16),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          color: tt.accent,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Ombi la malipo limetumwa.',
                        style: rajdhani(16, weight: FontWeight.w700).copyWith(color: tt.text),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Angalia simu yako kwa ujumbe wa USSD na kamilisha malipo.',
                        style: rajdhani(14, weight: FontWeight.w500).copyWith(color: tt.text2, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    final orderId = ZenoPayService.newOrderId();
    try {
      final created = await ZenoPayService.createOrder(
        requestedOrderId: orderId,
        buyerPhoneLocal0xx: normalized,
        amountTzs: amount,
        buyerName: 'Mteja Supasoka',
        metadata: {
          'plan_id': plan.id,
          'plan_label': plan.label,
        },
      );

      if (!context.mounted) return;

      if (!created.isSuccess) {
        if (context.mounted) rootNav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created.errorMessage ?? 'Malipo hayajatumika',
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFc62828),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final pollId = created.pollOrderId!;
      final outcome = await ZenoPayService.waitForCompleted(
        pollId,
        cancelled: () => !context.mounted,
      );

      if (!context.mounted) return;
      rootNav.pop();

      if (outcome.isCompleted) {
        await SubscriptionStore.activatePlan(plan.id);
        await UserIdentity.savePhoneNumber(normalized);
        await UserIdentity.registerWithBackend(phone: normalized);
        if (!context.mounted) return;
        SubscriptionStore.refreshNotifierFromPrefs();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Malipo yamekamilika! Furaha ya Premium.',
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
            ),
            backgroundColor: _mpesa,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final msg = switch (outcome.kind) {
        ZenoPollKind.failed => 'Malipo hayajakamilika (${outcome.detail ?? ''}).',
        ZenoPollKind.timeout => 'Muda umeisha bila kuthibitisha. Kama ulishalipa, subiri au wasiliana na msaada.',
        ZenoPollKind.cancelled => 'Malipo yamesitishwa.',
        ZenoPollKind.error => outcome.detail ?? 'Hitilafu isiyojulikana.',
        _ => 'Malipo hayajathibitishwa.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
          ),
          backgroundColor: const Color(0xFFc62828),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (context.mounted) rootNav.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hitilafu: $e',
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFc62828),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final plans = context.watch<ContentStore>().malipoPayPlans;
    final selectedPlan = _selectedPlan(plans);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final phoneOk = TanzaniaPhone.isValid(_phone);

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.85, -0.65),
          radius: 1.35,
          colors: [
            t.accent.withValues(alpha: 0.14),
            t.bg1,
          ],
          stops: const [0.0, 0.55],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FunguaHero(t: t, topPad: MediaQuery.paddingOf(context).top),
          Expanded(
            child: RefreshIndicator(
              color: t.accent,
              onRefresh: () => context.read<ContentStore>().refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18, 4, 18, bottom + 36),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            colors: [
                              Color.lerp(t.border, t.accent, 0.35)!,
                              Color.lerp(t.border, t.accent2, 0.28)!,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: t.glow.withValues(alpha: 0.15),
                              blurRadius: 8,
                              spreadRadius: -1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Chagua kifurushi',
                          style: orbitron(14, weight: FontWeight.w900).copyWith(color: t.text, letterSpacing: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (plans.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'Hakuna mipango ya malipo kwa sasa.',
                          textAlign: TextAlign.center,
                          style: rajdhani(14, weight: FontWeight.w600).copyWith(color: t.text2),
                        ),
                      ),
                    )
                  else
                    ...plans.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PremiumPlanTicket(
                          plan: p,
                          selected: _planId == p.id,
                          theme: t,
                          onTap: () => setState(() {
                            _planId = _planId == p.id ? null : p.id;
                            if (_planId == null) _phone = '';
                          }),
                        ),
                      ),
                    ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: _planId == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.07),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        blurRadius: 28,
                                        offset: const Offset(0, 14),
                                      ),
                                      BoxShadow(
                                        color: t.glow.withValues(alpha: 0.07),
                                        blurRadius: 36,
                                        spreadRadius: -10,
                                      ),
                                    ],
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.09),
                                        Colors.white.withValues(alpha: 0.02),
                                        t.card.withValues(alpha: 0.35),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Ionicons.phone_portrait_outline, size: 18, color: t.accent),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Malipo kwa simu — Tanzania',
                                              style: orbitron(12, weight: FontWeight.w800).copyWith(color: t.text),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Nambari ya mlipaji (074…, 065…, +255)',
                                        style: rajdhani(12, weight: FontWeight.w500).copyWith(color: t.text2, height: 1.35),
                                      ),
                                      const SizedBox(height: 14),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.38),
                                              blurRadius: 18,
                                              offset: const Offset(0, 6),
                                            ),
                                            if (_phoneFocused)
                                              BoxShadow(
                                                color: t.glow.withValues(alpha: 0.32),
                                                blurRadius: 20,
                                                spreadRadius: -4,
                                              ),
                                            if (phoneOk && !_phoneFocused)
                                              BoxShadow(
                                                color: _mpesa.withValues(alpha: 0.2),
                                                blurRadius: 16,
                                                spreadRadius: -3,
                                              ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: Container(
                                            height: 54,
                                            decoration: BoxDecoration(
                                              color: t.bg1.withValues(alpha: 0.92),
                                              border: Border.all(
                                                color: t.border.withValues(
                                                  alpha: _phoneFocused
                                                      ? 0.85
                                                      : phoneOk
                                                          ? 0.7
                                                          : 0.48,
                                                ),
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                                  child: Row(
                                                    children: [
                                                      const Text('🇹🇿', style: TextStyle(fontSize: 18)),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '+255',
                                                        style: rajdhani(13, weight: FontWeight.w700).copyWith(color: t.text2),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(width: 1, height: 24, color: t.border.withValues(alpha: 0.55)),
                                                Expanded(
                                                  child: TextField(
                                                    spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                                                    onChanged: (v) => setState(() => _phone = v),
                                                    onTap: () => setState(() => _phoneFocused = true),
                                                    onEditingComplete: () => setState(() => _phoneFocused = false),
                                                    keyboardType: TextInputType.phone,
                                                    inputFormatters: [LengthLimitingTextInputFormatter(20)],
                                                    style: rajdhani(17, weight: FontWeight.w700).copyWith(
                                                      color: t.text,
                                                      letterSpacing: 1.1,
                                                    ),
                                                    decoration: InputDecoration(
                                                      border: InputBorder.none,
                                                      hintText: '07XX XXX XXX',
                                                      hintStyle: TextStyle(color: t.text2.withValues(alpha: 0.38)),
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                                    ),
                                                  ),
                                                ),
                                                if (_phone.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 10),
                                                    child: Icon(
                                                      phoneOk ? Ionicons.checkmark_circle : Ionicons.alert_circle_outline,
                                                      color: phoneOk ? _mpesa : t.text2.withValues(alpha: 0.9),
                                                      size: 22,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (selectedPlan != null) ...[
                                        const SizedBox(height: 18),
                                        Builder(
                                          builder: (context) {
                                            final plan = selectedPlan;
                                            return Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(color: t.border.withValues(alpha: 0.55)),
                                                gradient: LinearGradient(
                                                  colors: [
                                                    t.card.withValues(alpha: 0.65),
                                                    t.bg2.withValues(alpha: 0.5),
                                                  ],
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: _SummaryTile(label: 'Kifurushi', value: plan.label, t: t),
                                                  ),
                                                  Container(
                                                    width: 1,
                                                    height: 40,
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
                                                      value: plan.amount,
                                                      t: t,
                                                      highlight: true,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: phoneOk && _planId != null
                        ? Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.42),
                                        blurRadius: 26,
                                        offset: const Offset(0, 14),
                                      ),
                                      BoxShadow(
                                        color: _mpesa.withValues(alpha: 0.28),
                                        blurRadius: 22,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _runZenoCheckout(context),
                                        child: Ink(
                                          height: 56,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [
                                                t.accent,
                                                const Color(0xFF00c853),
                                                const Color(0xFF00e676),
                                              ],
                                              stops: const [0.0, 0.42, 1.0],
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Ionicons.flash_outline, color: Colors.white.withValues(alpha: 0.95), size: 20),
                                              const SizedBox(width: 10),
                                              Text(
                                                'FUNGUA SASA',
                                                style: orbitron(14, weight: FontWeight.w900).copyWith(
                                                  color: Colors.white,
                                                  letterSpacing: 3,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Container(
                                                padding: const EdgeInsets.all(7),
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
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
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

class _FunguaHero extends StatelessWidget {
  const _FunguaHero({required this.t, required this.topPad});

  final AppThemeColors t;
  final double topPad;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.accent.withValues(alpha: 0.14),
            t.bg1,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: t.glow.withValues(alpha: 0.06),
            blurRadius: 40,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topPad + 10, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.black.withValues(alpha: 0.38),
                          border: Border.all(color: t.border.withValues(alpha: 0.72), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: t.glow.withValues(alpha: 0.14),
                              blurRadius: 12,
                              spreadRadius: -3,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Ionicons.infinite, size: 13, color: t.accent),
                            const SizedBox(width: 6),
                            Text(
                              'PREMIUM TZ',
                              style: orbitron(9, weight: FontWeight.w900).copyWith(color: t.accent, letterSpacing: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      ShaderMask(
                        shaderCallback: (b) => LinearGradient(colors: [t.accent, t.accent2]).createShader(b),
                        child: Text(
                          'Fungua Channel Zote',
                          style: orbitron(30, weight: FontWeight.w900).copyWith(
                            color: Colors.white,
                            height: 1.05,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Fungua channel zote kwa malipo ya bei nafuu zaidi, anza kwa kuchagua kifurushi unachoweza kukimudu.',
                        style: rajdhani(15, weight: FontWeight.w500).copyWith(color: t.text2, height: 1.45),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [t.accent, t.accent2]),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8)),
                      BoxShadow(color: t.glow.withValues(alpha: 0.28), blurRadius: 22, spreadRadius: -4),
                    ],
                  ),
                  child: Icon(Ionicons.key, color: Colors.white, size: 26),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeroChip(icon: Ionicons.tv_outline, label: 'Channels zote', t: t),
                _HeroChip(icon: Ionicons.sparkles_outline, label: 'HD & LIVE', t: t),
                _HeroChip(icon: Ionicons.shield_checkmark_outline, label: 'Malipo salama', t: t),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label, required this.t});

  final IconData icon;
  final String label;
  final AppThemeColors t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border.withValues(alpha: 0.48)),
        color: Colors.black.withValues(alpha: 0.28),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.accent),
          const SizedBox(width: 6),
          Text(label, style: rajdhani(11, weight: FontWeight.w700).copyWith(color: t.text)),
        ],
      ),
    );
  }
}

class _PremiumPlanTicket extends StatelessWidget {
  const _PremiumPlanTicket({
    required this.plan,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final PayPlan plan;
  final bool selected;
  final AppThemeColors theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Colors.white.withValues(alpha: 0.26) : t.border.withValues(alpha: 0.65),
                  width: 1,
                ),
                gradient: selected
                    ? LinearGradient(
                        colors: [plan.accent1, plan.accent2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          t.card,
                          t.bg2.withValues(alpha: 0.55),
                        ],
                      ),
                boxShadow: [
                  if (selected) ...[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: plan.accent1.withValues(alpha: 0.22),
                      blurRadius: 28,
                      spreadRadius: -8,
                    ),
                  ] else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(18, plan.popular ? 26 : 16, 18, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.label,
                          style: orbitron(15, weight: FontWeight.w900).copyWith(
                            color: selected ? Colors.white : t.text,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          plan.period,
                          style: rajdhani(12, weight: FontWeight.w600).copyWith(
                            color: selected ? Colors.white.withValues(alpha: 0.9) : t.text2,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Ionicons.infinite_outline,
                              size: 13,
                              color: selected ? Colors.white.withValues(alpha: 0.85) : t.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Channels zote',
                              style: rajdhani(11, weight: FontWeight.w700).copyWith(
                                color: selected ? Colors.white.withValues(alpha: 0.88) : t.accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ShaderMask(
                          shaderCallback: (b) => LinearGradient(
                            colors: selected ? [Colors.white, const Color(0xFFfefce8)] : [plan.accent1, plan.accent2],
                          ).createShader(b),
                          child: Text(
                            plan.priceLines,
                            textAlign: TextAlign.right,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: orbitron(13, weight: FontWeight.w900).copyWith(
                              color: Colors.white,
                              height: 1.12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          plan.amount,
                          style: orbitron(11, weight: FontWeight.w800).copyWith(
                            color: selected ? Colors.white.withValues(alpha: 0.88) : t.accent,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (plan.popular)
          Positioned(
            top: -9,
            left: 22,
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
                  BoxShadow(color: const Color(0xFFFF9800).withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4)),
                ],
                border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Ionicons.star, size: 11, color: Colors.black.withValues(alpha: 0.72)),
                  const SizedBox(width: 5),
                  Text(
                    plan.badge.isNotEmpty ? plan.badge : 'BORA',
                    style: orbitron(8, weight: FontWeight.w900).copyWith(color: const Color(0xFF1a0a00), letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ),
        if (selected)
          Positioned(
            top: plan.popular ? 16 : 12,
            right: 14,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 8)],
              ),
              child: Icon(Ionicons.checkmark, size: 15, color: plan.accent1),
            ),
          ),
      ],
    );
  }
}
