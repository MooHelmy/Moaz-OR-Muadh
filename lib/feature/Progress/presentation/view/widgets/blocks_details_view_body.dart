import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:medi_guard/core/utils/notifications_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BlocksDetailsViewBody extends StatefulWidget {
  const BlocksDetailsViewBody({super.key});

  @override
  State<BlocksDetailsViewBody> createState() => BlocksDetailsViewBodyState();
}

class BlocksDetailsViewBodyState extends State<BlocksDetailsViewBody> {
  List<Map<String, dynamic>> blockedItems = [];
  bool isLoading = true;
  int maxCount = 0;
  final NotificationService notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadLogs();

    // ربط الشاشة بخدمة الإشعارات لتحديث البيانات فور الحجب
    NotificationService.onBlockDetected = (word) {
      if (mounted) {
        _loadLogs();
      }
    };
  }

  @override
  void dispose() {
    NotificationService.onBlockDetected = null;
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
        debugPrint("Error parsing log entry: $e");
      }
    }

    setState(() {
      blockedItems = groupedData.values.toList();
      blockedItems.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
      isLoading = false;
    });
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
        maxCount = int.parse(item['count'].toString());
        if (maxCount >= 100) {
          notificationService.showInstantNotification(
            id: DateTime.now().microsecondsSinceEpoch % 1000000,
            title:
                "هذه الكلمة تم حجبها اكثر من ${item['count']} مرة ${notificationService.strikethrough(item['name'])}  🛡️",
            body: "اتقى الله هذا يكفى لا تستخدمها 😭 ولاتبحث عنها مرة اخرى",
          );
        }

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
