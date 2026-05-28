import 'package:Muadh/core/utils/shared_preferences_service.dart';
import 'package:flutter/material.dart';

class CustomRankCard extends StatefulWidget {
  const CustomRankCard({super.key});

  @override
  State<CustomRankCard> createState() => _CustomRankCardState();
}

List<String> ranks = [
  "مُبتدئ النور",
  "مُحارب الفطرة",
  "حارس العفة",
  "فارس الطهارة",
  "مغوار الصمود",
  "سيد الإرادة",
  "عميد الثبات",
  "قائد النصر",
  "حكيم الصفاء",
  "مَلِكُ النقاء"
];

class _CustomRankCardState extends State<CustomRankCard> {
  int rankIndex = 0;
  String rankName = ranks[0];

  @override
  void initState() {
    super.initState();
    _loadRankIndex();
  }

  Future<void> _loadRankIndex() async {
    final usageDuration = await SharePreferencesService.getUsageDuration();
    final loadedDays = usageDuration["days"] ?? 0;
    int newIndex;

    if (loadedDays < 5) {
      newIndex = 0;
    } else if (5 <= loadedDays && loadedDays < 14) {
      newIndex = 1;
    } else if (14 <= loadedDays && loadedDays < 30) {
      newIndex = 2;
    } else if (30 <= loadedDays && loadedDays < 60) {
      newIndex = 3;
    } else if (60 <= loadedDays && loadedDays < 90) {
      newIndex = 4;
    } else if (90 <= loadedDays && loadedDays < 180) {
      newIndex = 5;
    } else if (180 <= loadedDays && loadedDays < 365) {
      newIndex = 6;
    } else if (365 <= loadedDays && loadedDays < 730) {
      newIndex = 7; // سنة
    } else if (730 <= loadedDays && loadedDays < 1095) {
      newIndex = 8; // سنتين
    } else {
      newIndex = 9; // ✅ FIX: المرتبة الأعلى — 3 سنوات+، كانت مستحيلة الوصول
    }

    if (!mounted) return;

    setState(() {
      rankIndex = newIndex;
      rankName = ranks[newIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF10B981)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: const Color(0xFF10B981).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildTrophyIcon(),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "رتبتك الحالية",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                rankName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                "أنت في حماية الله",
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrophyIcon() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.emoji_events_rounded,
        color: Colors.amber,
        size: 42,
      ),
    );
  }
}
