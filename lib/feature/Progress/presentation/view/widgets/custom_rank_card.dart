import 'package:flutter/material.dart';
import 'package:medi_guard/core/utils/shared_preferences_service.dart';

class CustomRankCard extends StatefulWidget {
  final String rankName;
  const CustomRankCard({super.key, required this.rankName});

  @override
  State<CustomRankCard> createState() => _CustomRankCardState();
}

late String rankName;
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
  initState() async {
    super.initState();
    var usageDurationdays = await SharePreferencesService.getUsageDuration()
        .then((value) => value["days"]); //
    getRankIndex(usageDurationdays!);
    rankName = ranks[getRankIndex(usageDurationdays)];
  }

  int getRankIndex(int days) {
    if (0 < days && days < 5) return 0;
    if (5 <= days && days < 14) return 1;
    if (14 <= days && days < 30) return 2;
    if (30 <= days && days < 60) return 3;
    if (60 <= days && days < 90) return 4;
    if (90 <= days && days < 180) return 5;
    if (180 <= days && days < 365) return 6;
    if (365 <= days && days < 730) return 7;
    return 9; // أكثر من سنتين
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
