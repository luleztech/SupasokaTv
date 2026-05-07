import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _androidChannelId = 'supasoka_high_importance';
const _androidChannelName = 'Supasoka Notifications';
const _androidChannelDescription = 'Match alerts and app updates';

final _localNotifications = FlutterLocalNotificationsPlugin();
const _prefsNotifPrompted = 'supasoka_notif_prompted_v1';
const _prefsDirectTopic = 'supasoka_direct_user_topic_v1';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static Future<void> initialize() async {
    if (kIsWeb) return;

    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: _androidChannelDescription,
      importance: Importance.high,
    );
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await messaging.getToken();
    if (kDebugMode) {
      debugPrint('FCM token: $token');
    }

    // Optional global topic.
    await messaging.subscribeToTopic('all_users');

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_logOpenedNotification);

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      _logOpenedNotification(initial);
    }
  }

  static Future<bool> shouldShowPermissionPrompt() async {
    if (kIsWeb) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final alreadyAllowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    // Keep asking (via in-app dialog) until OS notification permission is granted.
    // Some users skip once, then never get asked again with the old one-shot flag.
    if (alreadyAllowed) return false;
    return true;
  }

  static Future<bool> requestPermissionFromPrompt() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsNotifPrompted, true);
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (allowed) {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (kDebugMode) debugPrint('FCM token (after prompt): $token');
      await messaging.subscribeToTopic('all_users');
    }
    return allowed;
  }

  static Future<void> markPermissionPromptSeen() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsNotifPrompted, true);
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    const android = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: android);

    await _localNotifications.show(
      message.hashCode,
      n.title ?? 'Supasoka',
      n.body ?? '',
      details,
      payload: jsonEncode(message.data),
    );
  }

  static void _logOpenedNotification(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('Notification opened: ${message.data}');
    }
  }

  static Future<void> syncAudienceTopics({required bool isPremium}) async {
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;
    if (isPremium) {
      await messaging.subscribeToTopic('premium_users');
      await messaging.unsubscribeFromTopic('free_users');
    } else {
      await messaging.subscribeToTopic('free_users');
      await messaging.unsubscribeFromTopic('premium_users');
    }
  }

  static Future<void> syncDirectUserTopic(String publicId) async {
    if (kIsWeb) return;
    final raw = publicId.trim();
    if (raw.isEmpty) return;
    final topic = 'user_${raw.replaceAll(RegExp(r'[^a-zA-Z0-9\\-_.~%]'), '_')}';
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_prefsDirectTopic);
    final messaging = FirebaseMessaging.instance;
    if (old != null && old.isNotEmpty && old != topic) {
      try {
        await messaging.unsubscribeFromTopic(old);
      } catch (_) {}
    }
    await messaging.subscribeToTopic(topic);
    await prefs.setString(_prefsDirectTopic, topic);
  }
}
