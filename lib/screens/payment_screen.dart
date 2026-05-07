import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/config/api_config.dart';
import 'package:supasoka/data/pay_plan.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/tanzania_phone.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/zeno_pay_service.dart';
import 'package:supasoka/screens/payments_screen_custom.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/app_typography.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key});

  @override
  Widget build(BuildContext context) => const PaymentsScreen();
}

class _PaymentScreenLegacy extends StatefulWidget {
  const _PaymentScreenLegacy({super.key});

  @override
  State<_PaymentScreenLegacy> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<_PaymentScreenLegacy> {
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

    final t = context.read<ThemeController>().colors;

    final normalized = TanzaniaPhone.normalize(_phone);
    if (normalized == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nambari si sahihi kwa Tanzania. Tumia 0XXXXXXXXX au +255…',
            style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
          ),
          backgroundColor: t.red,
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
            'Kiasi cha TZS hakipatikani kwenye mpango. Bei lazima iwe nambari kamili ya TZS (mfano 5000).',
            style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
          ),
          backgroundColor: t.red,
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
            color: Colors.black.withValues(alpha: 0.65),
            child: Center(
              child: _NeoDialogShell(
                accent: tt.accent,
                card: tt.card,
                border: tt.border,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        color: tt.accent,
                        strokeWidth: 2.5,
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
                      'Inatuma ombi la malipo katika simu yako, hakikisha malipo kwa kuweka namba yako ya siri',
                      style: rajdhani(14, weight: FontWeight.w500).copyWith(color: tt.text2, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    final orderId = ZenoPayService.newOrderId();
    try {
      final publicId = await UserIdentity.getOrCreatePublicId();
      // Ensure the user exists on backend before we attempt premium activation.
      await UserIdentity.registerWithBackend(phone: normalized);

      final created = await ZenoPayService.createOrder(
        requestedOrderId: orderId,
        buyerPhoneLocal0xx: normalized,
        amountTzs: amount,
        buyerName: 'Mteja Supasoka',
        metadata: {
          'plan_id': plan.id,
          'plan_label': plan.label,
          'public_id': publicId,
          'buyer_phone': normalized,
        },
      );

      if (!context.mounted) return;

      final tSnack = context.read<ThemeController>().colors;

      if (!created.isSuccess) {
        if (context.mounted) rootNav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created.errorMessage ?? 'Malipo hayajatumika',
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
            ),
            backgroundColor: tSnack.red,
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
        // Server-side premium activation (so SupaAdmin sees real premium users).
        try {
          await _confirmPremiumOnBackend(
            orderId: pollId,
            publicId: publicId,
            planId: plan.id,
            phone: normalized,
          );
          await SubscriptionStore.syncPremiumFromBackend();
        } catch (_) {
          // Keep local premium active even if backend verification is temporarily down.
        }
        if (!context.mounted) return;
        SubscriptionStore.refreshNotifierFromPrefs();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Malipo yamekamilika! Furaha ya Premium.',
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
            ),
            backgroundColor: Color.lerp(tSnack.accent, Colors.black, 0.35)!,
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
          backgroundColor: tSnack.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (context.mounted) rootNav.pop();
      if (context.mounted) {
        final tt = context.read<ThemeController>().colors;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hitilafu: $e',
              style: rajdhani(14, weight: FontWeight.w600).copyWith(color: Colors.white),
            ),
            backgroundColor: tt.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmPremiumOnBackend({
    required String orderId,
    required String publicId,
    required String planId,
    required String phone,
  }) async {
    final base = apiConfigUrl.trim();
    if (base.isEmpty) return;
    final origin = base.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$origin/api/v1/public/confirm-zeno-premium');
    await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
      body: jsonEncode({
        'orderId': orderId,
        'publicId': publicId,
        'planId': planId,
        'phone': phone,
      }),
    ).timeout(const Duration(seconds: 25));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<ThemeController>().colors;
    final plans = context.watch<ContentStore>().malipoPayPlans;
    final selectedPlan = _selectedPlan(plans);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final phoneOk = TanzaniaPhone.isValid(_phone);

    final accentGlow = t.accent.withValues(alpha: 0.14);
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      color: t.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RefreshIndicator(
              color: t.accent,
              onRefresh: () => context.read<ContentStore>().refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, bottom + 28),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Text(
                    'Nambari ya simu',
                    style: orbitron(13, weight: FontWeight.w800).copyWith(
                      color: t.text2,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    phoneOk
                        ? 'Nambari imethibitishwa — chagua kifurushi hapo chini.'
                        : 'Weka nambari unayolipia nayo kwanza (mitandao yote ya TZ).',
                    style: rajdhani(13, weight: FontWeight.w500).copyWith(color: t.text2.withValues(alpha: 0.85), height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  _PhoneField(
                    t: t,
                    phone: _phone,
                    phoneOk: phoneOk,
                    phoneFocused: _phoneFocused,
                    onChanged: (v) => setState(() {
                      _phone = v;
                      if (!TanzaniaPhone.isValid(v)) _planId = null;
                    }),
                    onTap: () => setState(() => _phoneFocused = true),
                    onEditingComplete: () => setState(() => _phoneFocused = false),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: phoneOk
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 26),
                              Text(
                                'Chagua kifurushi',
                                style: orbitron(13, weight: FontWeight.w800).copyWith(
                                  color: t.text2,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Chagua bei unayoweza — utaona kitufe cha malipo baada ya kuchagua.',
                                style: rajdhani(13, weight: FontWeight.w500).copyWith(color: t.text2.withValues(alpha: 0.82), height: 1.35),
                              ),
                              const SizedBox(height: 12),
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
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _PremiumPlanCard(
                                      plan: p,
                                      selected: _planId == p.id,
                                      t: t,
                                      onTap: () => setState(() {
                                        _planId = _planId == p.id ? null : p.id;
                                      }),
                                    ),
                                  ),
                                ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                child: selectedPlan == null
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: t.border.withValues(alpha: 0.55)),
                                            color: t.bg2.withValues(alpha: 0.42),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.35),
                                                blurRadius: 16,
                                                offset: const Offset(0, 8),
                                              ),
                                              BoxShadow(
                                                color: accentGlow,
                                                blurRadius: 20,
                                                spreadRadius: -12,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _SummaryTile(
                                                  label: 'Kifurushi',
                                                  value: selectedPlan.label.isNotEmpty ? selectedPlan.label : selectedPlan.period,
                                                  t: t,
                                                ),
                                              ),
                                              Container(
                                                width: 1,
                                                height: 40,
                                                margin: const EdgeInsets.symmetric(horizontal: 12),
                                                color: t.border.withValues(alpha: 0.45),
                                              ),
                                              Expanded(
                                                child: _SummaryTile(
                                                  label: 'Kiasi',
                                                  value: selectedPlan.amount,
                                                  t: t,
                                                  highlight: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                child: _planId != null
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 22),
                                        child: _NeoPrimaryButton(
                                          accent: t.accent,
                                          text: t.text,
                                          onTap: () => _runZenoCheckout(context),
                                          label: 'FUNGUA ZOTE SASA',
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
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

class _NeoDialogShell extends StatelessWidget {
  const _NeoDialogShell({
    required this.accent,
    required this.card,
    required this.border,
    required this.child,
  });

  final Color accent;
  final Color card;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: card,
          border: Border.all(color: border.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 32, offset: const Offset(0, 16)),
            BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 40, spreadRadius: -8),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.t,
    required this.phone,
    required this.phoneOk,
    required this.phoneFocused,
    required this.onChanged,
    required this.onTap,
    required this.onEditingComplete,
  });

  final AppThemeColors t;
  final String phone;
  final bool phoneOk;
  final bool phoneFocused;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;
  final VoidCallback onEditingComplete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          if (phoneFocused)
            BoxShadow(
              color: t.accent.withValues(alpha: 0.22),
              blurRadius: 18,
              spreadRadius: -2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: t.bg1,
            border: Border.all(
              color: t.accent.withValues(
                alpha: phoneFocused ? 0.55 : (phoneOk ? 0.28 : 0.12),
              ),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Text('🇹🇿', style: TextStyle(fontSize: 17)),
                    const SizedBox(width: 8),
                    Text(
                      '+255',
                      style: rajdhani(13, weight: FontWeight.w700).copyWith(color: t.text2),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 22, color: t.border.withValues(alpha: 0.5)),
              Expanded(
                child: TextField(
                  spellCheckConfiguration: SpellCheckConfiguration.disabled(),
                  onChanged: onChanged,
                  onTap: onTap,
                  onEditingComplete: onEditingComplete,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  style: rajdhani(17, weight: FontWeight.w700).copyWith(
                    color: t.text,
                    letterSpacing: 1.05,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '07XX XXX XXX',
                    hintStyle: TextStyle(color: t.text2.withValues(alpha: 0.35)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              if (phone.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    phoneOk ? Ionicons.checkmark_circle : Ionicons.alert_circle_outline,
                    color: phoneOk ? t.accent : t.text2.withValues(alpha: 0.85),
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeoPrimaryButton extends StatelessWidget {
  const _NeoPrimaryButton({
    required this.accent,
    required this.text,
    required this.onTap,
    required this.label,
  });

  final Color accent;
  final Color text;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final top = Color.lerp(accent, Colors.white, 0.18)!;
    final bottom = Color.lerp(accent, Colors.black, 0.22)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, bottom],
            ),
            border: Border.all(color: Color.lerp(accent, Colors.white, 0.25)!, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Ionicons.flash_outline, color: text.withValues(alpha: 0.95), size: 19),
              const SizedBox(width: 10),
              Text(
                label,
                style: orbitron(13, weight: FontWeight.w900).copyWith(
                  color: text,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(width: 10),
              Icon(Ionicons.arrow_forward, color: text.withValues(alpha: 0.9), size: 18),
            ],
          ),
        ),
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
            letterSpacing: 1.35,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: (highlight ? orbitron(14, weight: FontWeight.w900) : orbitron(13, weight: FontWeight.w800)).copyWith(
            color: highlight ? t.accent : t.text,
            letterSpacing: highlight ? 0.25 : 0,
          ),
        ),
      ],
    );
  }
}

class _PremiumPlanCard extends StatelessWidget {
  const _PremiumPlanCard({
    required this.plan,
    required this.selected,
    required this.t,
    required this.onTap,
  });

  final PayPlan plan;
  final bool selected;
  final AppThemeColors t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lift = selected ? 10.0 : 6.0;
    final topC = Color.lerp(t.card, Colors.white, selected ? 0.05 : 0.025)!;
    final botC = Color.lerp(t.bg2, Colors.black, selected ? 0.25 : 0.15)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [topC, botC],
                ),
                border: Border.all(
                  color: selected ? t.accent.withValues(alpha: 0.55) : t.border.withValues(alpha: 0.65),
                  width: selected ? 1.35 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: lift + 14,
                    offset: Offset(0, lift),
                  ),
                  BoxShadow(
                    color: selected ? t.accent.withValues(alpha: 0.18) : Colors.transparent,
                    blurRadius: 20,
                    spreadRadius: -4,
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(16, plan.badge.isNotEmpty || plan.popular ? 24 : 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.label.isNotEmpty ? plan.label : plan.period,
                          style: orbitron(14, weight: FontWeight.w900).copyWith(
                            color: t.text,
                            letterSpacing: 0.15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          plan.period,
                          style: rajdhani(12, weight: FontWeight.w600).copyWith(
                            color: t.text2,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Ionicons.infinite_outline, size: 13, color: t.accent.withValues(alpha: 0.9)),
                            const SizedBox(width: 6),
                            Text(
                              'Channels zote',
                              style: rajdhani(11, weight: FontWeight.w700).copyWith(color: t.text2),
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
                        Text(
                          plan.priceLines,
                          textAlign: TextAlign.right,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: orbitron(12, weight: FontWeight.w900).copyWith(
                            color: t.accent.withValues(alpha: selected ? 1 : 0.92),
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          plan.amount,
                          style: orbitron(11, weight: FontWeight.w800).copyWith(
                            color: t.text.withValues(alpha: 0.9),
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
        if (plan.badge.isNotEmpty || plan.popular)
          Positioned(
            top: -8,
            left: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(t.accent, Colors.white, 0.15)!,
                    Color.lerp(t.accent, Colors.black, 0.12)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Color.lerp(t.accent, Colors.white, 0.35)!),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 5)),
                  BoxShadow(color: t.accent.withValues(alpha: 0.2), blurRadius: 14),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    plan.popular ? Ionicons.star : Ionicons.pricetag_outline,
                    size: 11,
                    color: t.text.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    plan.badge.isNotEmpty ? plan.badge : 'BORA',
                    style: orbitron(8, weight: FontWeight.w900).copyWith(
                      color: t.text.withValues(alpha: 0.95),
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (selected)
          Positioned(
            top: plan.badge.isNotEmpty || plan.popular ? 14 : 10,
            right: 12,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.bg1,
                border: Border.all(color: t.accent.withValues(alpha: 0.7)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(Ionicons.checkmark, size: 15, color: t.accent),
            ),
          ),
      ],
    );
  }
}
