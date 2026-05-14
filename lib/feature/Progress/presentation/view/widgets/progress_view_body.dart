// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Progress/presentation/view/widgets/custom_rank_card.dart';
import 'package:medi_guard/feature/Progress/presentation/view/widgets/custom_section_lable.dart';

class ProgressViewBody extends StatelessWidget {
  const ProgressViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          const CustomRankCard(), // نقل الرتبة هنا أيضاً لتعزيز الشعور بالإنجاز
          const SizedBox(height: 25),
          const CustomSectionLabel(label: "إحصائيات الحماية العامة"),
          const SizedBox(height: 15),
          _buildStatSummaryTile(
            context,
            title: "قوة الصمود",
            subtitle: "مدى التزام الدرع بحماية الخصوصية",
            value: "99%",
            icon: Icons.auto_awesome_rounded,
            color: Colors.amber,
          ),
          const SizedBox(height: 12),
          _buildStatSummaryTile(
            context,
            title: "تصفية الشوائب",
            subtitle: "إجمالي العناصر غير المرغوبة التي تم صدها",
            value: "نشط",
            icon: Icons.cleaning_services_rounded,
            color: Colors.blue,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildStatSummaryTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color)),
          const SizedBox(width: 15),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text(subtitle,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ]),
          ),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
