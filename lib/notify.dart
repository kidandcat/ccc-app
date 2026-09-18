import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _listenId = 1;

bool shouldNotify({
  required String kind,
  required String machineId,
  required int botId,
  ({String machine, int bot})? watching,
  bool foreground = true,
  bool general = false,
}) {
  // Worker transcripts are a log, not a ping. General replies, send_file, and
  // ask_owner match what Telegram would notify.
  if (kind == 'post' && !general) return false;
  if (kind != 'post' && kind != 'file' && kind != 'question') return false;
  if (foreground &&
      watching != null &&
      watching.machine == machineId &&
      watching.bot == botId) {
    return false;
  }
  return true;
}

int notificationId(String machineId, int botId) =>
    100 + Object.hash(machineId, botId).abs() % 90000;

class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static void Function(String payload)? onTap;

  static Future<void> init({void Function(String payload)? onTap}) async {
    Notify.onTap = onTap;
    const android = AndroidInitializationSettings('ic_stat_ccc');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) Notify.onTap?.call(p);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final p = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && p != null && p.isNotEmpty) {
      Notify.onTap?.call(p);
    }
  }

  static Future<void> message({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      final android = AndroidNotificationDetails(
        'ccc.messages',
        'Messages',
        channelDescription: 'New messages from your CCC sessions',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
        icon: 'ic_stat_ccc',
      );
      const darwin = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android, iOS: darwin),
        payload: payload,
      );
    } catch (_) {}
  }

  static Future<void> startListening({required int machines}) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await android.requestNotificationsPermission();
    const details = AndroidNotificationDetails(
      'ccc.listen',
      'Connection',
      channelDescription: 'Keeps CCC connected so new messages can notify you',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showWhen: false,
      icon: 'ic_stat_ccc',
    );
    final n = machines == 1 ? '1 machine' : '$machines machines';
    await android.startForegroundService(
      id: _listenId,
      title: 'CCC is listening',
      body: n,
      notificationDetails: details,
      foregroundServiceTypes: {
        AndroidServiceForegroundType.foregroundServiceTypeDataSync,
      },
    );
  }

  static Future<void> stopListening() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.stopForegroundService();
    } catch (_) {}
  }
}

({String machine, int bot})? parseNotifyPayload(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    final m = j['machine'] as String?;
    final b = (j['bot_id'] as num?)?.toInt();
    if (m == null || m.isEmpty || b == null) return null;
    return (machine: m, bot: b);
  } catch (_) {
    return null;
  }
}
