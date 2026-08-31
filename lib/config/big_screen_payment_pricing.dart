import 'package:supasoka/data/pay_plan.dart';

/// SupaTV / desktop checkout prices (mobile plans stay on server defaults).
abstract final class BigScreenPaymentPricing {
  static const weekTzs = 3000;
  static const monthTzs = 6000;
  static const quarterTzs = 12000;

  static const _mobileToBigScreen = <int, int>{
    2000: weekTzs,
    5000: monthTzs,
    10000: quarterTzs,
    12000: quarterTzs,
  };

  static PayPlan apply(PayPlan plan) {
    final mobileAmount = _digits(plan.amount);
    final override = (mobileAmount != null ? _mobileToBigScreen[mobileAmount] : null) ??
        _amountFromCopy(plan);
    if (override == null || override == mobileAmount) return plan;

    return PayPlan(
      id: plan.id,
      label: plan.label,
      priceLines: _rewritePriceLines(plan.priceLines, override),
      amount: override.toString(),
      period: plan.period,
      popular: plan.popular,
      accent1: plan.accent1,
      accent2: plan.accent2,
      badge: plan.badge,
    );
  }

  static List<PayPlan> applyAll(Iterable<PayPlan> plans) =>
      plans.map(apply).toList(growable: false);

  static int? _digits(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }

  static int? _amountFromCopy(PayPlan plan) {
    final hay = '${plan.id} ${plan.period} ${plan.label}'.toLowerCase();
    if (hay.contains('miezi 3') || hay.contains('3 miezi') || hay.contains('quarter')) {
      return quarterTzs;
    }
    if (hay.contains('wiki') || hay.contains('siku 7') || hay.contains('7 siku') || hay.contains('week')) {
      return weekTzs;
    }
    if (hay.contains('mwezi') || hay.contains('month')) return monthTzs;
    return null;
  }

  static String _rewritePriceLines(String original, int amount) {
    final formatted = 'TSh. ${_comma(amount)}';
    if (original.trim().isEmpty) return formatted;
    final replaced = original.replaceAllMapped(
      RegExp(r'TSh\.?\s*[\d,]+'),
      (_) => formatted,
    );
    return replaced == original ? formatted : replaced;
  }

  static String _comma(int value) {
    final s = value.toString();
    if (s.length <= 3) return s;
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
