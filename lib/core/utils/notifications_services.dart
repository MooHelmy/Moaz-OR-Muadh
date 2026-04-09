import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel('com.maadh.shield/vpn');

  // متغير ثابت لتحديث الشاشات المفتوحة (مثل شاشة السجلات)
  static Function(String)? onBlockDetected;

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(
          'ic_launcher',
        ); // استخدام الاسم مباشرة بدون @mipmap

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    // 4. Register Callback (لما المستخدم يدوس على الإشعار)
    await _notificationsPlugin.initialize(
      settings:
          initializationSettings, // تم إزالة 'settings:' لأنها ليست معلمة مسماة
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // بدء الاستماع للكلمات المحظورة فوراً
    _setupMethodChannel();
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onBlockedContent") {
        final String word = call.arguments;
        await showInstantNotification(
          id: DateTime.now().microsecondsSinceEpoch % 1000000,
          title: "تم الحجب بنجاح 🛡️",
          body: "حاول أحدهم الوصول إلى: $word وتم منعه.",
        );

        // لو المستخدم فاتح صفحة السجلات، نخليه يحدث البيانات تلقائياً
        onBlockDetected?.call(word);
      }
    });
  }

  void _onNotificationTapped(NotificationResponse response) {}

  // تحديد الـ Channel (Senior Approach: تعريفه كـ ثابت لسهولة التعديل)
  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        'shield_channel_id', // ID فريد
        'Shield Notifications', // اسم القناة اللي بيظهر للمستخدم في الإعدادات
        channelDescription: 'Notifications for protection and security alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        icon: 'ic_launcher',
      );

  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
  );

  // إرسال إشعار فوري
  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _notificationDetails,
      payload: payload,
    );
  }
}
