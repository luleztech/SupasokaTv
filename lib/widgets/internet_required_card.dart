import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import '../theme/app_typography.dart';

/// Accent matches cold-start splash (`LoaderScreen`).
const _kInternetAccent = Color(0xFFFF4F4F);

/// Shared card for offline — splash loader dialog and in-app full-screen gate.
class InternetRequiredCard extends StatelessWidget {
  const InternetRequiredCard({
    super.key,
    required this.onRetry,
    this.busy = false,
  });

  final VoidCallback onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kInternetAccent.withValues(alpha: 0.22)),
        color: const Color(0xFF101018),
        boxShadow: [
          BoxShadow(
            color: _kInternetAccent.withValues(alpha: 0.12),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _kInternetAccent.withValues(alpha: 0.35),
                  _kInternetAccent.withValues(alpha: 0.12),
                ],
              ),
            ),
            child: const Icon(
              Ionicons.cloud_offline_outline,
              size: 34,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Hakuna muunganiko wa internet',
            textAlign: TextAlign.center,
            style: orbitron(
              18,
              weight: FontWeight.w800,
            ).copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'Washa data ya simu au Wi‑Fi kisha ujaribu tena. Huwezi kutazama maudhui bila mtandao.',
            textAlign: TextAlign.center,
            style: rajdhani(14).copyWith(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: busy ? null : onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: _kInternetAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: busy
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black.withValues(alpha: 0.85),
                    ),
                  )
                : Text(
                    'Jaribu tena',
                    style: rajdhani(15, weight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}
