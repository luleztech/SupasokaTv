import 'package:flutter/material.dart';

/// M-Pesa plan row (from API `malipoPlans`).
class PayPlan {
  const PayPlan({
    required this.id,
    required this.label,
    required this.priceLines,
    required this.amount,
    required this.period,
    required this.popular,
    required this.accent1,
    required this.accent2,
    this.badge = '',
  });

  final String id;
  final String label;
  final String priceLines;
  final String amount;
  final String period;
  final bool popular;
  final Color accent1;
  final Color accent2;
  /// Short label on ribbon when [popular] (from admin).
  final String badge;
}
