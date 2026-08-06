import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/screens/payments_screen_custom.dart';
import 'package:supasoka/theme/app_theme.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({
    super.key,
    /// When true (bottom-nav tab), only autoplay the guide while Fungua is selected.
    this.playGuideWhenTabActive = false,
  });

  final bool playGuideWhenTabActive;

  @override
  Widget build(BuildContext context) {
    final autoPlayGuide = playGuideWhenTabActive
        ? context.watch<AppNav>().currentTab == AppTab.unlock
        : true;
    return PaymentsScreen(autoPlayGuide: autoPlayGuide);
  }
}
