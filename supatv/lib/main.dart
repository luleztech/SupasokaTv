import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/subscription_store.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/theme/app_theme.dart';
import 'package:supasoka/theme/brand_palette.dart';
import 'package:supatv/bootstrap/desktop_plugins.dart';
import 'package:supatv/models/tv_playback_settings.dart';
import 'package:supatv/screens/splash_screen.dart';
import 'package:supatv/screens/tv_shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await registerDesktopDartPlugins();
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await UserIdentity.resetIdentityIfFreshInstall();
  await SubscriptionStore.refreshNotifierFromPrefs();
  final themeController = await ThemeController.load();

  final contentStore = ContentStore();
  final playbackSettings = TvPlaybackSettings();
  runApp(SupaTvApp(
    contentStore: contentStore,
    themeController: themeController,
    playbackSettings: playbackSettings,
  ));
  unawaited(_bootstrapIdentity());
}

Future<void> _bootstrapIdentity() async {
  try {
    final savedPhone = await UserIdentity.getSavedPhoneNumber();
    final reg = await UserIdentity.registerWithBackend(phone: savedPhone);
    if (reg.premiumUntilMs != null &&
        reg.premiumUntilMs! > DateTime.now().millisecondsSinceEpoch) {
      await SubscriptionStore.setPremiumUntilMs(reg.premiumUntilMs!);
    } else {
      await SubscriptionStore.syncPremiumFromBackend(force: true);
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('SupaTV identity bootstrap failed: $e\n$st');
    }
  }
}

class SupaTvApp extends StatelessWidget {
  const SupaTvApp({
    super.key,
    required this.contentStore,
    required this.themeController,
    required this.playbackSettings,
  });

  final ContentStore contentStore;
  final ThemeController themeController;
  final TvPlaybackSettings playbackSettings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: contentStore),
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: playbackSettings),
      ],
      child: MaterialApp(
        title: 'SupaTV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: BrandPalette.bgDeep,
          colorScheme: ColorScheme.dark(
            primary: BrandPalette.accent,
            surface: BrandPalette.bgDeep,
          ),
        ),
        home: _RootGate(contentStore: contentStore),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate({required this.contentStore});

  final ContentStore contentStore;

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _booted = false;

  @override
  Widget build(BuildContext context) {
    if (!_booted) {
      return SplashScreen(
        onReady: () {
          if (mounted) setState(() => _booted = true);
        },
      );
    }
    return TvShellScreen(contentStore: widget.contentStore);
  }
}
