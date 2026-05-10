import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MonitoringView extends StatelessWidget {
  const MonitoringView({super.key});

  String _timeAgo(int ms) {
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  IconData _sourceIcon(String source) {
    switch (source) {
      case 'واتساب':    return Icons.chat_rounded;
      case 'تيليجرام':  return Icons.send_rounded;
      case 'التنزيلات': return Icons.download_rounded;
      case 'الكاميرا':  return Icons.camera_alt_rounded;
      case 'إنستجرام':  return Icons.camera_rounded;
      case 'تيك توك':   return Icons.music_note_rounded;
      case 'فيسبوك':    return Icons.facebook_rounded;
      default:           return Icons.folder_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'سجل الحماية',
          style: TextStyle(
            color: Color(0xFF064E3B),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: ValueListenableBuilder(
        // ✅ بيتحدث تلقائياً لما يتحذف ملف جديد
        valueListenable: Hive.box('deleted_log').listenable(),
        builder: (context, Box box, _) {
          if (box.isEmpty) {
            return _buildEmptyState();
          }

          // ✅ اجيب الـ entries من الأحدث للأقدم
          final entries = box.values.toList().reversed.toList();

          return Column(
            children: [
              // ── إجمالي المحذوفات ─────────────────────────
              _buildSummaryCard(entries.length),
              const SizedBox(height: 4),

              // ── القائمة ───────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final entry = entries[i] as Map;
                    final fileName = entry['fileName'] ?? 'ملف';
                    final source   = entry['source']   ?? 'أخرى';
                    final time     = entry['deletedAt'] as int? ??
                        DateTime.now().millisecondsSinceEpoch;

                    return _buildLogCard(
                      fileName: fileName,
                      source: source,
                      timeAgo: _timeAgo(time),
                      icon: _sourceIcon(source),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF065F46)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF064E3B).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.shield_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count ملف محذوف',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'الدرع الذكي يحمي جهازك',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard({
    required String fileName,
    required String source,
    required String timeAgo,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة المصدر
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFE53935), size: 22),
          ),
          const SizedBox(width: 14),

          // اسم الملف والمصدر
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  source,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),

          // الوقت + أيقونة الحذف
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.delete_sweep_rounded,
                  color: Color(0xFFE53935), size: 18),
              const SizedBox(height: 4),
              Text(
                timeAgo,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 64,
              color: Color(0xFF064E3B),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'جهازك نظيف تماماً',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'لم يتم حذف أي محتوى حتى الآن',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}
