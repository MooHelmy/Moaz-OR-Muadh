import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ScanNotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  // ✅ ID ثابت للـ summary notification عشان يتحدث بدل ما ينشئ جديد
  static const int _summaryId = 9000;
  static const String _groupKey = 'muadh_deletions';
  int _deleteCount = 0;

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
    );
  }

  /// يظهر إشعار بس لما فيه حذف فعلي
  /// بيعمل grouping عشان مش يملأ شريط الإشعارات
  Future<void> showDeletedNotification(String filePath) async {
    final fileName = filePath.split('/').last;
    _deleteCount++;

    // ─── إشعار فردي للملف المحذوف ──────────────────────────────
    await _plugin.show(
      _deleteCount % 8999, // ✅ FIX: cap الـ ID عشان ما يتجاوزش الـ _summaryId=9000
      '🛡️ معاذ — تم الحذف',
      'تم حذف "$fileName"',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'muadh_deletions',
          'ملفات محذوفة',
          channelDescription: 'إشعار عند حذف محتوى غير لائق',
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFFE53935),
          // ✅ grouping: كل إشعارات الحذف في مجموعة واحدة
          groupKey: _groupKey,
          // ✅ صوت وإضاءة بس للإشعار الفعلي
          playSound: true,
          enableLights: true,
          ledColor: const Color(0xFFE53935),
          ledOnMs: 500,
          ledOffMs: 500,
          // ✅ بيختفي تلقائياً بعد 10 ثواني من الشريط
          timeoutAfter: 10000,
          autoCancel: true,
        ),
      ),
    );

    // ─── summary notification (لو في أكتر من حذف) ───────────────
    if (_deleteCount > 1) {
      await _plugin.show(
        _summaryId,
        '🛡️ معاذ',
        'تم حذف $_deleteCount ملف غير لائق',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'muadh_deletions',
            'ملفات محذوفة',
            channelDescription: 'إشعار عند حذف محتوى غير لائق',
            importance: Importance.high,
            priority: Priority.high,
            color: const Color(0xFFE53935),
            groupKey: _groupKey,
            setAsGroupSummary: true,
            autoCancel: true,
          ),
        ),
      );
    }
  }

  /// إعادة ضبط العداد (مثلاً لما يفتح التطبيق)
  void resetCount() {
    _deleteCount = 0;
  }
}
