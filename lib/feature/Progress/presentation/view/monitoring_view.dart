// ignore_for_file: deprecated_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MonitoringView extends StatelessWidget {
  const MonitoringView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      body: ValueListenableBuilder(
        valueListenable: Hive.box('deleted_log').listenable(),
        builder: (context, Box deletedBox, _) {
          return ValueListenableBuilder(
            valueListenable: Hive.box('scan_stats').listenable(),
            builder: (context, Box statsBox, _) {
              return _MonitoringBody(
                deletedBox: deletedBox,
                statsBox: statsBox,
              );
            },
          );
        },
      ),
    );
  }
}

class _MonitoringBody extends StatelessWidget {
  final Box deletedBox;
  final Box statsBox;

  const _MonitoringBody({required this.deletedBox, required this.statsBox});

  Map<String, dynamic> _getTotalStats() {
    final raw = statsBox.get('total_stats') as Map?;
    return {
      'scanned': raw?['scanned'] as int? ?? 0,
      'blocked': raw?['blocked'] as int? ?? 0,
    };
  }

  List<Map<String, dynamic>> _getFolderStats() {
    final folders = <Map<String, dynamic>>[];
    for (final key in statsBox.keys) {
      if (key.toString().startsWith('folder_')) {
        final data = statsBox.get(key) as Map?;
        if (data != null) {
          folders.add({
            'name': data['folder'] ?? 'أخرى',
            'total': data['total'] as int? ?? 0,
            'blocked': data['blocked'] as int? ?? 0,
            'safe': data['safe'] as int? ?? 0,
            'images': data['images'] as int? ?? 0,
            'videos': data['videos'] as int? ?? 0,
            'lastScan': data['lastScan'] as int? ?? 0,
          });
        }
      }
    }
    folders.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    return folders;
  }

  String _timeAgo(int ms) {
    if (ms == 0) return 'لم يُفحص بعد';
    final diff =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return 'منذ ${diff.inDays} يوم';
  }

  IconData _folderIcon(String name) {
    switch (name) {
      case 'واتساب':
        return Icons.chat_bubble_rounded;
      case 'تيليجرام':
        return Icons.send_rounded;
      case 'التنزيلات':
        return Icons.download_for_offline_rounded;
      case 'الكاميرا':
        return Icons.camera_alt_rounded;
      case 'إنستجرام':
        return Icons.camera_rounded;
      case 'تيك توك':
        return Icons.music_video_rounded;
      case 'فيسبوك':
        return Icons.facebook_rounded;
      case 'سناب شات':
        return Icons.crop_rounded;
      case 'الصور':
        return Icons.photo_library_rounded;
      case 'الفيديوهات':
        return Icons.video_library_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  Color _folderColor(String name) {
    switch (name) {
      case 'واتساب':
        return const Color(0xFF25D366);
      case 'تيليجرام':
        return const Color(0xFF2AABEE);
      case 'التنزيلات':
        return const Color(0xFF6C63FF);
      case 'الكاميرا':
        return const Color(0xFFFF6B6B);
      case 'إنستجرام':
        return const Color(0xFFE1306C);
      case 'تيك توك':
        return const Color(0xFF69C9D0);
      case 'فيسبوك':
        return const Color(0xFF1877F2);
      case 'سناب شات':
        return const Color(0xFFFFFC00);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalStats = _getTotalStats();
    final folderStats = _getFolderStats();
    final deletedEntries = deletedBox.values.toList().reversed.toList();
    final totalScanned = totalStats['scanned'] as int;
    final totalBlocked = totalStats['blocked'] as int;
    final safePercent = totalScanned > 0
        ? ((totalScanned - totalBlocked) / totalScanned * 100).round()
        : 100;
    final blockedPercent =
        totalScanned > 0 ? (totalBlocked / totalScanned * 100).round() : 0;

    return CustomScrollView(
      slivers: [
        // ── AppBar ───────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 0,
          backgroundColor: const Color(0xFF0A0F1E),
          floating: true,
          snap: true,
          title: const Text(
            'مركز الرقابة',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: true,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF88).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: const Color(0xFF00FF88).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00FF88),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'نشط',
                    style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── بطاقة الدرع الرئيسية ────────────────────
                _ShieldSummaryCard(
                  totalScanned: totalScanned,
                  totalBlocked: totalBlocked,
                  safePercent: safePercent,
                  blockedPercent: blockedPercent,
                  deletedCount: deletedEntries.length,
                ),

                const SizedBox(height: 20),

                // ── إحصائيات سريعة ──────────────────────────
                _QuickStatsRow(
                  totalScanned: totalScanned,
                  totalBlocked: totalBlocked,
                  foldersCount: folderStats.length,
                  deletedCount: deletedEntries.length,
                ),

                const SizedBox(height: 24),

                // ── Chart دائري للنسب ────────────────────────
                if (totalScanned > 0) ...[
                  _SectionHeader(
                      title: 'نسبة الأمان', icon: Icons.donut_large_rounded),
                  const SizedBox(height: 12),
                  _PieChartCard(
                    safeCount: totalScanned - totalBlocked,
                    blockedCount: totalBlocked,
                    total: totalScanned,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── إحصائيات الفولدرات ───────────────────────
                if (folderStats.isNotEmpty) ...[
                  _SectionHeader(
                      title: 'الفولدرات المفحوصة',
                      icon: Icons.folder_special_rounded),
                  const SizedBox(height: 12),
                  ...folderStats.map((f) => _FolderStatCard(
                        name: f['name'] as String,
                        total: f['total'] as int,
                        blocked: f['blocked'] as int,
                        safe: f['safe'] as int,
                        images: f['images'] as int,
                        videos: f['videos'] as int,
                        lastScan: _timeAgo(f['lastScan'] as int),
                        icon: _folderIcon(f['name'] as String),
                        color: _folderColor(f['name'] as String),
                      )),
                  const SizedBox(height: 24),
                ],

                // ── سجل الحذف الأخير ────────────────────────
                _SectionHeader(
                    title: 'آخر الملفات المحذوفة',
                    icon: Icons.delete_sweep_rounded),
                const SizedBox(height: 12),

                if (deletedEntries.isEmpty)
                  _EmptyDeletedState()
                else
                  ...deletedEntries.take(10).map((e) {
                    final entry = e as Map;
                    return _DeleteLogCard(
                      fileName: entry['fileName'] ?? 'ملف',
                      source: entry['source'] ?? 'أخرى',
                      timeMs: entry['deletedAt'] as int? ?? 0,
                      timeAgo: _timeAgo(entry['deletedAt'] as int? ?? 0),
                    );
                  }),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00FF88), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─── بطاقة الدرع الرئيسية ──────────────────────────────────────
class _ShieldSummaryCard extends StatelessWidget {
  final int totalScanned;
  final int totalBlocked;
  final int safePercent;
  final int blockedPercent;
  final int deletedCount;

  const _ShieldSummaryCard({
    required this.totalScanned,
    required this.totalBlocked,
    required this.safePercent,
    required this.blockedPercent,
    required this.deletedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2137), Color(0xFF0A1628)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF00FF88).withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FF88).withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          // Shield Icon + عنوان
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FF88), Color(0xFF00C96A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF88).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Color(0xFF0A1628), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الدرع الذكي',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalScanned == 0
                          ? 'لم يبدأ الفحص بعد'
                          : 'فحص $totalScanned ملف حتى الآن',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Progress Bar الرئيسي
          _AnimatedProgressBar(
            safePercent: safePercent,
            blockedPercent: blockedPercent,
          ),

          const SizedBox(height: 20),

          // النسب
          Row(
            children: [
              Expanded(
                child: _PercentBadge(
                  label: 'آمن',
                  percent: safePercent,
                  color: const Color(0xFF00FF88),
                  count: totalScanned - totalBlocked,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white12),
              Expanded(
                child: _PercentBadge(
                  label: 'محجوب',
                  percent: blockedPercent,
                  color: const Color(0xFFFF4757),
                  count: totalBlocked,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white12),
              Expanded(
                child: _PercentBadge(
                  label: 'محذوف',
                  percent: null,
                  color: const Color(0xFFFF6B35),
                  count: deletedCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  final int safePercent;
  final int blockedPercent;

  const _AnimatedProgressBar(
      {required this.safePercent, required this.blockedPercent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'مستوى الأمان',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            Text(
              '$safePercent%',
              style: const TextStyle(
                color: Color(0xFF00FF88),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Container(
                height: 10,
                width: double.infinity,
                color: Colors.white.withOpacity(0.08),
              ),
              FractionallySizedBox(
                widthFactor: safePercent / 100,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FF88), Color(0xFF00C96A)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF88).withOpacity(0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PercentBadge extends StatelessWidget {
  final String label;
  final int? percent;
  final Color color;
  final int count;

  const _PercentBadge({
    required this.label,
    required this.percent,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          percent != null ? '$percent%' : '$count',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ─── Quick Stats Row ──────────────────────────────────────────
class _QuickStatsRow extends StatelessWidget {
  final int totalScanned;
  final int totalBlocked;
  final int foldersCount;
  final int deletedCount;

  const _QuickStatsRow({
    required this.totalScanned,
    required this.totalBlocked,
    required this.foldersCount,
    required this.deletedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: _MiniStatCard(
          value: '$totalScanned',
          label: 'ملف فُحص',
          icon: Icons.search_rounded,
          color: const Color(0xFF6C63FF),
        )),
        const SizedBox(width: 10),
        Expanded(
            child: _MiniStatCard(
          value: '$foldersCount',
          label: 'فولدر',
          icon: Icons.folder_rounded,
          color: const Color(0xFF2AABEE),
        )),
        const SizedBox(width: 10),
        Expanded(
            child: _MiniStatCard(
          value: '$deletedCount',
          label: 'محذوف',
          icon: Icons.delete_forever_rounded,
          color: const Color(0xFFFF4757),
        )),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _MiniStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pie Chart Card ────────────────────────────────────────────
class _PieChartCard extends StatelessWidget {
  final int safeCount;
  final int blockedCount;
  final int total;

  const _PieChartCard({
    required this.safeCount,
    required this.blockedCount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final safeRatio = total > 0 ? safeCount / total : 1.0;
    final blockedRatio = total > 0 ? blockedCount / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          // Donut Chart
          SizedBox(
            width: 100,
            height: 100,
            child: CustomPaint(
              painter: _DonutChartPainter(
                safeRatio: safeRatio,
                blockedRatio: blockedRatio,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(safeRatio * 100).round()}%',
                      style: const TextStyle(
                        color: Color(0xFF00FF88),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'آمن',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 24),

          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LegendItem(
                  color: const Color(0xFF00FF88),
                  label: 'ملفات آمنة',
                  count: safeCount,
                  total: total,
                ),
                const SizedBox(height: 12),
                _LegendItem(
                  color: const Color(0xFFFF4757),
                  label: 'ملفات محجوبة',
                  count: blockedCount,
                  total: total,
                ),
                const SizedBox(height: 16),
                // Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: (safeRatio * 100).round(),
                        child: Container(
                          height: 6,
                          color: const Color(0xFF00FF88),
                        ),
                      ),
                      Expanded(
                        flex: (blockedRatio * 100).round().clamp(0, 100),
                        child: Container(
                          height: 6,
                          color: const Color(0xFFFF4757),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  final int total;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ),
        Text(
          '$count ($pct%)',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double safeRatio;
  final double blockedRatio;

  _DonutChartPainter({required this.safeRatio, required this.blockedRatio});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 14.0;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final safePaint = Paint()
      ..color = const Color(0xFF00FF88)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final blockedPaint = Paint()
      ..color = const Color(0xFFFF4757)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background
    canvas.drawCircle(center, radius, bgPaint);

    // Safe arc
    final safeAngle = safeRatio * 2 * math.pi;
    canvas.drawArc(rect, -math.pi / 2, safeAngle, false, safePaint);

    // Blocked arc
    final blockedAngle = blockedRatio * 2 * math.pi;
    canvas.drawArc(
        rect, -math.pi / 2 + safeAngle, blockedAngle, false, blockedPaint);
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.safeRatio != safeRatio ||
      oldDelegate.blockedRatio != blockedRatio;
}

// ─── Folder Stat Card ──────────────────────────────────────────
class _FolderStatCard extends StatelessWidget {
  final String name;
  final int total;
  final int blocked;
  final int safe;
  final int images;
  final int videos;
  final String lastScan;
  final IconData icon;
  final Color color;

  const _FolderStatCard({
    required this.name,
    required this.total,
    required this.blocked,
    required this.safe,
    required this.images,
    required this.videos,
    required this.lastScan,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final safePercent = total > 0 ? (safe / total * 100).round() : 100;
    final blockedPercent = total > 0 ? (blocked / total * 100).round() : 0;
    final safeRatio = total > 0 ? safe / total : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'آخر فحص: $lastScan',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Total count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$total ملف',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Progress Bar للفولدر
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  flex: (safeRatio * 100).round().clamp(1, 100),
                  child: Container(
                    height: 8,
                    color: const Color(0xFF00FF88),
                  ),
                ),
                Expanded(
                  flex: ((1 - safeRatio) * 100).round().clamp(0, 99),
                  child: Container(
                    height: 8,
                    color: const Color(0xFFFF4757),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Stats Row
          Row(
            children: [
              _FolderStat(
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF00FF88),
                label: 'آمن',
                value: '$safe ($safePercent%)',
              ),
              const SizedBox(width: 12),
              _FolderStat(
                icon: Icons.block_rounded,
                color: const Color(0xFFFF4757),
                label: 'محجوب',
                value: '$blocked ($blockedPercent%)',
              ),
              const Spacer(),
              _FolderStat(
                icon: Icons.image_rounded,
                color: Colors.white38,
                label: 'صور',
                value: '$images',
              ),
              const SizedBox(width: 10),
              _FolderStat(
                icon: Icons.videocam_rounded,
                color: Colors.white38,
                label: 'فيديو',
                value: '$videos',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _FolderStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Delete Log Card ──────────────────────────────────────────
class _DeleteLogCard extends StatelessWidget {
  final String fileName;
  final String source;
  final int timeMs;
  final String timeAgo;

  const _DeleteLogCard({
    required this.fileName,
    required this.source,
    required this.timeMs,
    required this.timeAgo,
  });

  IconData _sourceIcon() {
    switch (source) {
      case 'واتساب':
        return Icons.chat_bubble_rounded;
      case 'تيليجرام':
        return Icons.send_rounded;
      case 'التنزيلات':
        return Icons.download_for_offline_rounded;
      case 'الكاميرا':
        return Icons.camera_alt_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF4757).withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4757).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(_sourceIcon(), color: const Color(0xFFFF4757), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  source,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.delete_sweep_rounded,
                  color: Color(0xFFFF4757), size: 16),
              const SizedBox(height: 2),
              Text(
                timeAgo,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ───────────────────────────────────────────────
class _EmptyDeletedState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00FF88).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 40,
              color: Color(0xFF00FF88),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'جهازك نظيف تماماً',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'لم يتم حذف أي محتوى حتى الآن',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
