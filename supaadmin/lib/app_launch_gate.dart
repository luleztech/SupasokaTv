import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'admin_shell.dart';
import 'screens/login_screen.dart';
import 'store/admin_store.dart';
import 'widgets/admin_shimmer.dart';
import 'widgets/admin_splash_screen.dart';

/// Animated splash, then shimmer if storage is slow, then [AdminShell].
class AppLaunchGate extends StatefulWidget {
  const AppLaunchGate({super.key});

  @override
  State<AppLaunchGate> createState() => _AppLaunchGateState();
}

class _AppLaunchGateState extends State<AppLaunchGate> {
  bool _splashAnimationDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminStore>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AdminStore>();

    Widget child;
    if (!_splashAnimationDone) {
      child = AdminSplashScreen(
        onFinished: () => setState(() => _splashAnimationDone = true),
      );
    } else if (!store.isLoaded) {
      child = const AdminShimmerLoadingPage();
    } else if (!store.hasAdminSession) {
      child = const LoginScreen();
    } else {
      child = const AdminShell();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey<String>(
          !_splashAnimationDone
              ? 'splash'
              : !store.isLoaded
                  ? 'shimmer'
                  : !store.hasAdminSession
                      ? 'login'
                      : 'app',
        ),
        child: child,
      ),
    );
  }
}
