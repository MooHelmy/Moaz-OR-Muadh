import 'package:flutter/material.dart';
import 'package:muadh/core/themes.dart';

class StatusCircle extends StatelessWidget {
  final bool active;
  final int blockedCount;

  const StatusCircle({
    required this.active,
    required this.blockedCount,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.emerald, width: 8),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield, size: 60, color: AppTheme.emerald),
          SizedBox(height: 10),
          Text(active ? "الدرع نشط" : "الدرع متوقف", style: AppTheme.titleText),
          Text(
            "تم صد $blockedCount محاولة اليوم",
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}
