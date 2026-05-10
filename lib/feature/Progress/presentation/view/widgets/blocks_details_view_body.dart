import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:medi_guard/core/utils/notifications_services_old.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BlocksDetailsViewBody extends StatefulWidget {
  const BlocksDetailsViewBody({super.key});

  @override
  State<BlocksDetailsViewBody> createState() => BlocksDetailsViewBodyState();
}

class BlocksDetailsViewBodyState extends State<BlocksDetailsViewBody> {
  List<Map<String, dynamic>> blockedItems = [];
  bool isLoading = true;
  final AppNotificationService notificationService = AppNotificationService();

  @override
  void initState() {
    super.initState();
    _loadLogs();

    // ربط الشاشة بخدمة الإشعارات لتحديث البيانات فور الحجب
    AppNotificationService.onBlockDetected = (word) {
      if (mounted) {
        _loadLogs();
      }
    };
  }

  @override
  void dispose() {
    AppNotificationService.onBlockDetected = null;
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    // The key here is "shield_logs"
    final String rawLogs = prefs.getString('shield_logs') ?? "";

    if (rawLogs.isEmpty) {
      setState(() => isLoading = false);
      return;
    }

    // نقل عملية تحليل السجلات إلى Isolate منفصل لمنع تباطؤ واجهة المستخدم
    final List<Map<String, dynamic>> parsedItems =
        await compute(_parseLogsInIsolate, rawLogs);

    setState(() {
      blockedItems = parsedItems;
      blockedItems.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
      isLoading = false;
    });

    // التحقق من الإشعارات وعرضها بعد تحميل السجلات وفرزها
    _checkAndShowNotifications(blockedItems);
  }

  // دالة مسح السجل وإظهار الرسالة
  Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shield_logs');

    setState(() {
      blockedItems = [];
    });

    if (!mounted) return;

    // إظهار الرسالة الجميلة
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "غفر الله ذنبك وطهر قلبك وحصن فرجك 🤲 ",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        backgroundColor: const Color(0xFF064E3B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  String _formatTime(int timestamp) {
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return intl.DateFormat('hh:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (blockedItems.isEmpty) {
      return const Center(child: Text("لا توجد سجلات حجب حتى الآن"));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: blockedItems.length,
      itemBuilder: (context, index) {
        final item = blockedItems[index];
        return _buildProfessionalBlockCard(item);
      },
    );
  }

  Widget _buildProfessionalBlockCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: Container(
                color: item['isUrl'] ? Colors.redAccent : Colors.orangeAccent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor:
                        (item['isUrl'] ? Colors.red : Colors.orange)
                            // ignore: deprecated_member_use
                            .withOpacity(0.1),
                    child: Icon(
                      item['isUrl']
                          ? Icons.public_off_rounded
                          : Icons.text_snippet_rounded,
                      color:
                          item['isUrl'] ? Colors.red[700] : Colors.orange[700],
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1F2937),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatTime(item['timestamp']),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${item['count']} محاولة",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// دالة علوية (Top-level function) لـ Isolate لتحليل السجلات
// يجب أن تكون هذه الدالة ثابتة (static) أو دالة علوية لاستخدامها مع compute.
List<Map<String, dynamic>> _parseLogsInIsolate(String rawLogs) {
  Map<String, Map<String, dynamic>> groupedData = {};
  List<String> entries = rawLogs.split(';');

  for (var entry in entries) {
    if (entry.isEmpty) continue;
    List<String> parts = entry.split('|');
    if (parts.length < 3) continue;

    try {
      String name = parts[0];
      int timestamp = int.tryParse(parts[1]) ?? 0;
      bool isUrl = parts[2] == 'true';

      if (groupedData.containsKey(name)) {
        groupedData[name]!['count'] += 1;
        if (timestamp > groupedData[name]!['timestamp']) {
          groupedData[name]!['timestamp'] = timestamp;
        }
      } else {
        groupedData[name] = {
          "name": name,
          "timestamp": timestamp,
          "count": 1,
          "isUrl": isUrl,
        };
      }
    } catch (e) {
      // في Isolate، قد لا تكون debugPrint مرئية مباشرة في جميع السياقات.
      // استخدام print للتسجيل الأساسي.
      print("Error parsing log entry in isolate: $e");
    }
  }
  return groupedData.values.toList();
}

// دالة للتحقق من الإشعارات وعرضها، يتم استدعاؤها بعد تحميل السجلات
extension on BlocksDetailsViewBodyState {
  void _checkAndShowNotifications(List<Map<String, dynamic>> items) {
    // يجب أن يتتبع هذا المنطق الإشعارات التي تم عرضها بالفعل
    // لتجنب عرضها بشكل متكرر في كل مرة يتم فيها تحميل السجلات.
    // للتبسيط، هذا المثال ينقل المنطق فقط.
    for (var item in items) {
      int count = item['count'];
      if (count >= 100) {
        final int notificationId =
            item['name'].hashCode.abs(); // معرف فريد لكل عنصر
        notificationService.showInstantNotification(
          id: notificationId,
          title:
              "هذه الكلمة تم حجبها اكثر من ${item['count']} مرة ${notificationService.strikethrough(item['name'])}  🛡️",
          body: "اتقى الله هذا يكفى لا تستخدمها 😭 ولاتبحث عنها مرة اخرى",
        );
      }
    }
  }
}
