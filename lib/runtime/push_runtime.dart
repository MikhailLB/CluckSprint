import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'device_agent.dart';
import 'vault.dart';

// ============================================================
//  PushRuntime — Firebase Messaging + local fallback
// ============================================================
//  Cold-start tap (app killed): RM is delivered via
//  `getInitialMessage()` at boot. We stash the URL into the
//  vault and the boot stage will pop it on the next launch.
//
//  Warm tap (app backgrounded): RM arrives via
//  `onMessageOpenedApp`. Routed live through `onPayloadUrl`.
//
//  Foreground: we render the notification ourselves with
//  flutter_local_notifications (Android only — iOS shows its
//  own banners by design).
// ============================================================

@pragma('vm:entry-point')
Future<void> _bgEntryPoint(RemoteMessage _) async {
  // System owns background presentation; nothing to do here.
}

const String pushChannelId = 'cs_alerts_v1';
const String pushChannelName = 'CluckSprint Alerts';

class PushRuntime {
  PushRuntime(this._vault);

  final Vault _vault;
  final FlutterLocalNotificationsPlugin _localBus =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _fcm;
  String? _token;
  bool _booted = false;

  /// Live URL push (warm). Pure callback — ContentScreen subscribes
  /// to forward the URL into the running WebView controller.
  void Function(String url)? onPayloadUrl;

  /// Token rotation signal — used by the splash to re-POST.
  void Function(String token)? onTokenRotated;

  String? get token => _token;

  Future<void> boot() async {
    if (_booted) return;
    try {
      await Firebase.initializeApp();
      _fcm = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_bgEntryPoint);

      await _bootLocalChannel();

      _token = await _fcm!.getToken();

      _fcm!.onTokenRefresh.listen((next) {
        _token = next;
        onTokenRotated?.call(next);
      });

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      final initial = await _fcm!.getInitialMessage();
      if (initial != null) {
        _handleColdTap(initial);
      }

      _booted = true;
    } catch (_) {
      // No Firebase → push disabled but the app keeps running.
    }
  }

  Future<void> _bootLocalChannel() async {
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localBus.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload);
          if (data is Map<String, dynamic>) {
            final url = data['url'] as String?;
            if (url != null && url.isNotEmpty) {
              onPayloadUrl?.call(url);
            }
          }
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final android = _localBus
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          pushChannelId,
          pushChannelName,
          description: 'Operational alerts from CluckSprint',
          importance: Importance.high,
        ),
      );
    }
  }

  /// Show the system permission dialog (Android 13+ / iOS).
  /// If the OS denies, remember it so the promo screen stops
  /// pestering the user every 3 days.
  Future<bool> askPermission() async {
    if (_fcm == null) return false;
    final settings = await _fcm!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    await _vault.setPushGranted(granted);
    if (!granted &&
        settings.authorizationStatus == AuthorizationStatus.denied) {
      await _vault.markPushOsBlocked();
    }
    return granted;
  }

  void _handleForeground(RemoteMessage message) async {
    if (!Platform.isAndroid) return;
    final note = message.notification;
    if (note == null) return;

    AndroidNotificationDetails? android;
    final bigUrl = note.android?.imageUrl;

    if (bigUrl != null && bigUrl.isNotEmpty) {
      final pic = await _fetchImageBytes(bigUrl);
      if (pic != null) {
        android = AndroidNotificationDetails(
          pushChannelId,
          pushChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(pic),
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    android ??= const AndroidNotificationDetails(
      pushChannelId,
      pushChannelName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    final payload =
        message.data.isNotEmpty ? jsonEncode(message.data) : null;

    await _localBus.show(
      note.hashCode,
      note.title,
      note.body,
      NotificationDetails(android: android),
      payload: payload,
    );
  }

  void _handleColdTap(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      // Persist — boot stage will pop it.
      _vault.stashPushUrl(url);
    }
  }

  void _handleWarmTap(RemoteMessage message) {
    final url = message.data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      onPayloadUrl?.call(url);
    }
  }

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final r = await DeviceAgent.instance
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) return r.bodyBytes;
    } catch (_) {}
    return null;
  }
}
