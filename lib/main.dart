import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/main_shell.dart';
import 'package:supasoka/screens/loader_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/theme/app_theme.dart';

/// Hides the Material scrollbar thumb (Common on web/desktop; keeps scrolling unchanged).
class _NoScrollbarScrollBehavior extends MaterialScrollBehavior {
  const _NoScrollbarScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  final themeController = await ThemeController.load();
  await SubscriptionStore.refreshNotifierFromPrefs();
  await SubscriptionStore.syncPremiumFromBackend(); // Sync premium on app start
  final contentStore = ContentStore();
  runApp(SupasokaApp(themeController: themeController, contentStore: contentStore));
}

class SupasokaApp extends StatelessWidget {
  const SupasokaApp({super.key, required this.themeController, required this.contentStore});

  final ThemeController themeController;
  final ContentStore contentStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: contentStore),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, tc, _) {
          final bg = tc.colors.bg1;
          final baseTheme = ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: bg,
            colorScheme: ColorScheme.dark(primary: tc.colors.accent, surface: bg),
          );
          return MaterialApp(
            title: 'Supasoka',
            debugShowCheckedModeBanner: false,
            scrollBehavior: const _NoScrollbarScrollBehavior(),
            theme: baseTheme.copyWith(
              textTheme: baseTheme.textTheme.apply(
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
              primaryTextTheme: baseTheme.primaryTextTheme.apply(
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
            builder: (context, child) {
              return DefaultTextStyle.merge(
                style: const TextStyle(
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                  decorationThickness: 0,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const _RootNavigator(),
          );
        },
      ),
    );
  }
}

class _RootNavigator extends StatefulWidget {
  const _RootNavigator();

  @override
  State<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<_RootNavigator> with WidgetsBindingObserver {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loaded && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ContentStore>().refresh();
        unawaited(UserIdentity.registerWithBackend());
        unawaited(SubscriptionStore.syncPremiumFromBackend());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return LoaderScreen(
        onDone: () => setState(() => _loaded = true),
      );
    }
    return const MainShell();
  }
}
