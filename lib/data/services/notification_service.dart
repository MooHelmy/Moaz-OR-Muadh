import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ScanNotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  int _notifId = 0;

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // ✅ Fix: كانت في arguments بتتبعت بشكل غلط بسبب formatting
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
  }

  Future<void> showDeletedNotification(String filePath) async {
    final fileName = filePath.split('/').last;

    // ✅ Fix: الـ 4 arguments محتاجين يتبعتوا صح بدون فراغات زايدة
    await _plugin.show(
      _notifId++,
      'Medi Guard — تم الحذف التلقائي',
      'تم حذف "$fileName" لأنه محتوى غير لائق',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medi_guard_alerts',
          'تنبيهات المحتوى',
          channelDescription: 'إشعارات عن المحتوى المحذوف تلقائياً',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFE53935),
        ),
      ),
    );
  }
}
