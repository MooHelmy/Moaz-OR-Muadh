import 'package:flutter/material.dart';
import 'package:muadh/feature/Progress/presentation/view/blocks_details_view.dart';

class CustomActivityLog extends StatelessWidget {
  const CustomActivityLog({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CustomActiveLog(
          title: "تم حجب موقع مشبوه",
          time: "منذ 15 دقيقة",
          icon: Icons.block_flipped,
          color: Colors.red,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (BuildContext context) => const BlocksDetailsView(),
              ),
            );
          },
        ),
        CustomActiveLog(
          title: "تصفية نتائج البحث",
          time: "منذ ساعتين",
          icon: Icons.security_rounded,
          color: Colors.blue,
        ),
        CustomActiveLog(
          title: "ثبات على العهد",
          time: "فجر اليوم",
          icon: Icons.auto_awesome_rounded,
          color: Colors.amber,
        ),
      ],
    );
  }
}

class CustomActiveLog extends StatelessWidget {
  final String title;
  final String time;
  final IconData icon;
  final Color color;
  final void Function()? onTap;

  const CustomActiveLog({
    super.key,
    required this.title,
    required this.time,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            CircleAvatar(
              // ignore: deprecated_member_use
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF374151),
                    ),
                  ),
                  Text(
                    time,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left_rounded, color: Colors.grey[300]),
          ],
        ),
      ),
    );
  }
}
