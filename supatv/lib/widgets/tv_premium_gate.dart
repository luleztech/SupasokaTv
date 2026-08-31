import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supasoka/data/app_data.dart';
import 'package:supasoka/screens/payments_screen_custom.dart';
import 'package:supasoka/theme/brand_palette.dart';

/// TV/desktop premium checkout — same payment API, wide two-column layout.
class TvPremiumGate extends StatelessWidget {
  const TvPremiumGate({
    super.key,
    required this.channel,
    required this.onClose,
    this.onPaymentSuccess,
  });

  final Channel? channel;
  final VoidCallback onClose;
  final Future<void> Function()? onPaymentSuccess;

  @override
  Widget build(BuildContext context) {
    final ch = channel;

    return Material(
      color: BrandPalette.bgDeep,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack)) {
            onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: PaymentsScreen(
          desktopLayout: true,
          autoPlayGuide: true,
          audioAssetPackage: 'supatv',
          onClose: onClose,
          contextTitle: ch?.name,
          onPaymentSuccess: onPaymentSuccess,
        ),
      ),
    );
  }
}
