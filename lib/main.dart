import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:supasoka/main_shell.dart';
import 'package:supasoka/screens/force_update_screen.dart';
import 'package:supasoka/screens/loader_screen.dart';
import 'package:supasoka/services/content_store.dart';
import 'package:supasoka/services/push_notification_service.dart';
import 'package:supasoka/services/user_identity.dart';
import 'package:supasoka/services/premium_recovery.dart';
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
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  // Keep only fast local reads before first frame — Firebase + network sync runs after [runApp].
  final themeController = await ThemeController.load();
  await SubscriptionStore.refreshNotifierFromPrefs();
  final contentStore = ContentStore();
  runApp(SupasokaApp(themeController: themeController, contentStore: contentStore));
  unawaited(_initializeDeferredServices());
}

/// Push, premium sync, and topics — must not block cold start / splash first paint.
Future<void> _initializeDeferredServices() async {
  try {
    await PushNotificationService.initialize();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('Deferred FCM init failed: $e\n$st');
    }
  }
  try {
    await PremiumRecovery.recoverPendingPaymentIfAny();
    await SubscriptionStore.syncPremiumFromBackend();
    final isPremium =
        SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;
    await PushNotificationService.syncAudienceTopics(isPremium: isPremium);
    final publicId = await UserIdentity.getOrCreatePublicId();
    await PushNotificationService.syncDirectUserTopic(publicId);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('Deferred subscription/topics sync failed: $e\n$st');
    }
  }
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
  bool _notifPromptChecked = false;
  Timer? _premiumSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _premiumSyncTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || !_loaded) return;
      unawaited(_syncPremiumAndTopics());
    });
  }

  @override
  void dispose() {
    _premiumSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loaded && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(() async {
          await context.read<ContentStore>().checkUpdateFromServer();
          if (!mounted) return;
          await context.read<ContentStore>().refresh();
        }());
        unawaited(
          UserIdentity.registerWithBackend().then((_) async {
            final pid = await UserIdentity.getOrCreatePublicId();
            return PushNotificationService.syncDirectUserTopic(pid);
          }),
        );
        unawaited(_syncPremiumAndTopics());
      });
    }
  }

  Future<void> _syncPremiumAndTopics() async {
    await SubscriptionStore.syncPremiumFromBackend();
    final isPremium = SubscriptionStore.isPremiumActiveLocal();
    await PushNotificationService.syncAudienceTopics(isPremium: isPremium);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return LoaderScreen(
        onDone: () => setState(() => _loaded = true),
      );
    }

    final store = context.watch<ContentStore>();
    if (store.updateRequired) {
      final update = store.appUpdateStatus;
      return ForceUpdateScreen(
        currentVersion: update.currentVersion,
        currentBuild: update.currentBuild,
        minVersion: update.minVersion,
        latestVersion: update.latestVersion,
        minBuild: update.minBuild,
        latestBuild: update.latestBuild,
        playStoreUrl: update.playStoreUrl,
        onRecheck: () => store.checkUpdateFromServer(),
      );
    }

    if (!_notifPromptChecked) {
      _notifPromptChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskNotificationPermission());
    }
    return const MainShell();
  }

  Future<void> _maybeAskNotificationPermission() async {
    if (!mounted) return;
    final shouldAsk = await PushNotificationService.shouldShowPermissionPrompt();
    if (!mounted || !shouldAsk) return;

    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 390),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E172A), Color(0xFF0A1120)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Usikose taarifa muhimu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Washa notifications upate taarifa za mechi za moja kwa moja, updates za channel, na ujumbe muhimu wa akaunti.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  height: 1.45,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Text('Sasa hivi hapana'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
                      child: const Text('Washa'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (granted == true) {
      await PushNotificationService.requestPermissionFromPrompt();
      final isPremium =
          SubscriptionStore.premiumUntilNotifier.value?.isAfter(DateTime.now()) ?? false;
      await PushNotificationService.syncAudienceTopics(isPremium: isPremium);
    } else {
      await PushNotificationService.markPermissionPromptSeen();
    }
  }
}
