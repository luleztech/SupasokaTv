import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supasoka/config/big_screen_payment_pricing.dart';
import 'package:supasoka/data/pay_plan.dart';

void main() {
  test('maps common mobile tiers to SupaTV prices', () {
    const week = PayPlan(
      id: 'weekly',
      label: 'Wiki 1',
      priceLines: 'TSh. 2,000',
      amount: '2000',
      period: 'Siku 7',
      popular: true,
      accent1: Color(0xFF0ea5e9),
      accent2: Color(0xFF6366f1),
    );
    const month = PayPlan(
      id: 'monthly',
      label: 'Mwezi 1',
      priceLines: 'TSh. 5,000',
      amount: '5000',
      period: 'Mwezi Mmoja',
      popular: false,
      accent1: Color(0xFF0ea5e9),
      accent2: Color(0xFF6366f1),
    );
    const quarter = PayPlan(
      id: 'quarterly',
      label: 'Miezi 3',
      priceLines: 'TSh. 10,000',
      amount: '10000',
      period: 'Miezi 3',
      popular: false,
      accent1: Color(0xFF0ea5e9),
      accent2: Color(0xFF6366f1),
    );

    expect(BigScreenPaymentPricing.apply(week).amount, '3000');
    expect(BigScreenPaymentPricing.apply(month).amount, '6000');
    expect(BigScreenPaymentPricing.apply(quarter).amount, '12000');
  });
}
