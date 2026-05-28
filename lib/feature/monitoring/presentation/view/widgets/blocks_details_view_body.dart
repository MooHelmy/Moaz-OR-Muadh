// ══════════════════════════════════════════════════════════════════════════════
//  blocks_details_view_body.dart  — v2.0.0
//
//  ✅ إزالة groupedData! unsafe → safe map access في كل مكان
//  ✅ memoization للبيانات المُحوَّلة — لا إعادة حساب بلا سبب
//  ✅ const constructors في كل widget ممكن
//  ✅ ListView.builder مع itemExtent لأداء أسرع
//  ✅ RepaintBoundary على كل بطاقة — يمنع re-paint الشجرة كلها
//  ✅ Colors.withValues بدل withOpacity المهمَل
//  ✅ flutter_screenutil لكل الأبعاد
//  ✅ _BlockCard مفصول كـ widget مستقل لتقليل rebuilds
// ══════════════════════════════════════════════════════════════════════════════

import 'package:Muadh/core/utils/notifications_services_old.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Immutable data model — بدل Map<String,dynamic> الغير آمن
// ──────────────────────────────────────────────────────────────────────────────

final class BlockedItem {
  const BlockedItem({
    required this.name,
    required this.timestamp,
    required this.count,
    required this.isUrl,
  });

  final String name;
  final int timestamp;
  final int count;
  final bool isUrl;

  /// Safe factory من raw map — لا force unwrap
  static BlockedItem? tryFromMap(Map<String, dynamic> map) {
    final name = map['name'];
    final ts = map['timestamp'];
    final cnt = map['count'];
    final isUrl = map['isUrl'];

    if (name is! String || ts is! int || cnt is! int || isUrl is! bool) {
      return null;
    }
    return BlockedItem(name: name, timestamp: ts, count: cnt, isUrl: isUrl);
  }

  @override
  bool operator ==(Object other) =>
      other is BlockedItem &&
      name == other.name &&
      timestamp == other.timestamp &&
      count == other.count &&
      isUrl == other.isUrl;

  @override
  int get hashCode => Object.hash(name, timestamp, count, isUrl);
}

// ──────────────────────────────────────────────────────────────────────────────
// Widget
// ──────────────────────────────────────────────────────────────────────────────

class BlocksDetailsViewBody extends StatefulWidget {
  const BlocksDetailsViewBody({super.key});

  @override
  State<BlocksDetailsViewBody> createState() => BlocksDetailsViewBodyState();
}

class BlocksDetailsViewBodyState extends State<BlocksDetailsViewBody> {
  List<BlockedItem> _items = const [];
  bool _isLoading = true;
  bool _loadScheduled = false; // throttle للـ _loadLogs

  final _notificationService = AppNotificationService();
  // ✅ memoization للـ timeFormat — لا يُنشأ من جديد كل build
  static final _timeFormatter = intl.DateFormat('hh:mm a');
  // ✅ cache لـ formatted times — لا إعادة format لنفس الـ timestamp
  final Map<int, String> _timeCache = {};

  @override
  void initState() {
    super.initState();
    _loadLogs();

    AppNotificationService.onBlockDetected = (word) {
      if (mounted) _scheduleLoad(); // throttle بدل استدعاء مباشر
    };
  }

  @override
  void dispose() {
    AppNotificationService.onBlockDetected = null;
    super.dispose();
  }

  /// Throttle: يمنع تحميل متزامن متعدد
  void _scheduleLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    Future.delayed(const Duration(milliseconds: 300), () {
      _loadScheduled = false;
      if (mounted) _loadLogs();
    });
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawLogs = prefs.getString('shield_logs') ?? '';

    if (rawLogs.isEmpty) {
      if (mounted)
        setState(() {
          _items = const [];
          _isLoading = false;
        });
      return;
    }

    // ✅ Isolate للـ parsing الثقيل — لا jank في الـ UI thread
    final parsed = await compute(_parseLogsInIsolate, rawLogs);

    // ✅ Safe conversion من Map إلى BlockedItem
    final items = parsed
        .map(BlockedItem.tryFromMap)
        .whereType<BlockedItem>()
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // flush time cache عند تحديث البيانات
    _timeCache.clear();

    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _checkAndShowNotifications(items);
    }
  }

  Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shield_logs');
    _timeCache.clear();

    if (mounted) {
      setState(() => _items = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'غفر الله ذنبك وطهر قلبك وحصن فرجك 🤲',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp),
          ),
          backgroundColor: const Color(0xFF064E3B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.r),
          ),
          margin: EdgeInsets.all(20.r),
        ),
      );
    }
  }

  String _formatTime(int timestamp) {
    // ✅ memoized format — لا إعادة حساب لنفس الـ timestamp
    return _timeCache.putIfAbsent(
      timestamp,
      () =>
          _timeFormatter.format(DateTime.fromMillisecondsSinceEpoch(timestamp)),
    );
  }

  void _checkAndShowNotifications(List<BlockedItem> items) {
    for (final item in items) {
      if (item.count >= 100) {
        _notificationService.showInstantNotification(
          id: item.name.hashCode.abs(),
          title: 'هذه الكلمة تم حجبها اكثر من ${item.count} مرة '
              '${_notificationService.strikethrough(item.name)} 🛡️',
          body: 'اتقى الله هذا يكفى لا تستخدمها 😭 ولاتبحث عنها مرة اخرى',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: EdgeInsets.all(20.r),
      // ✅ itemExtent ثابت → Flutter يتخطى layout لكل item غير مرئي
      itemExtent: 100.h,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        // ✅ RepaintBoundary — يمنع إعادة رسم بطاقات أخرى عند تغيير بطاقة واحدة
        return RepaintBoundary(
          child: _BlockCard(
            item: item,
            formattedTime: _formatTime(item.timestamp),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// _EmptyState — const widget مستقل لا يتأثر بـ rebuild الـ parent
// ──────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'لا توجد سجلات حجب حتى الآن',
        style: TextStyle(
          fontSize: 15.sp,
          color: Colors.grey[500],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// _BlockCard — widget مستقل → يُعاد بناؤه فقط عند تغيُّر item
// ──────────────────────────────────────────────────────────────────────────────

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.item, required this.formattedTime});

  final BlockedItem item;
  final String formattedTime;

  @override
  Widget build(BuildContext context) {
    final accentColor = item.isUrl ? Colors.redAccent : Colors.orangeAccent;
    final iconColor = item.isUrl ? Colors.red[700] : Colors.orange[700];
    final bgColor = item.isUrl ? Colors.red : Colors.orange;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: Stack(
          children: [
            // ✅ الشريط الجانبي الملوَّن
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 6.w,
              child: ColoredBox(color: accentColor),
            ),
            Padding(
              padding: EdgeInsets.all(16.r),
              child: Row(
                children: [
                  // ✅ الأيقونة
                  CircleAvatar(
                    radius: 25.r,
                    backgroundColor: bgColor.withValues(alpha: 0.1),
                    child: Icon(
                      item.isUrl
                          ? Icons.public_off_rounded
                          : Icons.text_snippet_rounded,
                      color: iconColor,
                      size: 24.sp,
                    ),
                  ),
                  SizedBox(width: 15.w),
                  // ✅ اسم + وقت
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 4.h),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14.sp,
                              color: Colors.grey[400],
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              formattedTime,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12.sp,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ✅ عداد المحاولات
                  _CountBadge(count: item.count),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// _CountBadge — const-safe sub-widget
// ──────────────────────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        '$count محاولة',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11.sp,
          color: const Color(0xFF374151),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Isolate parser — top-level function (required for compute)
// ──────────────────────────────────────────────────────────────────────────────

List<Map<String, dynamic>> _parseLogsInIsolate(String rawLogs) {
  final grouped = <String, Map<String, dynamic>>{};

  for (final entry in rawLogs.split(';')) {
    if (entry.isEmpty) continue;
    final parts = entry.split('|');
    if (parts.length < 3) continue;

    try {
      final name = parts[0];
      final timestamp = int.tryParse(parts[1]) ?? 0;
      final isUrl = parts[2] == 'true';

      // ✅ Safe map access — لا force unwrap
      final existing = grouped[name];
      if (existing != null) {
        existing['count'] = (existing['count'] as int) + 1;
        if (timestamp > (existing['timestamp'] as int)) {
          existing['timestamp'] = timestamp;
        }
      } else {
        grouped[name] = {
          'name': name,
          'timestamp': timestamp,
          'count': 1,
          'isUrl': isUrl,
        };
      }
    } catch (e) {
      // parseLogsInIsolate error
    }
  }

  return grouped.values.toList();
}
