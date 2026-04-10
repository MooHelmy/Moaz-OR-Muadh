import 'dart:async';

import 'package:flutter/material.dart';

class CustomDetailedTimer extends StatefulWidget {
  const CustomDetailedTimer({super.key, required this.snapshot});
  final AsyncSnapshot<DateTime?> snapshot;

  @override
  State<CustomDetailedTimer> createState() => _CustomDetailedTimerState();
}

class _CustomDetailedTimerState extends State<CustomDetailedTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // تشغيل مؤقت يطلب إعادة بناء الواجهة كل ثانية واحدة
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // إغلاق المؤقت عند الخروج من الصفحة لتوفير البطارية
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // حساب الفارق الزمني الحالي بناءً على تاريخ التثبيت والوقت الآن
    final DateTime? installDate = widget.snapshot.data;
    final DateTime now = DateTime.now();

    final Duration difference = installDate != null
        ? now.difference(installDate)
        : Duration.zero;

    final Map<String, String> timerData = {
      "days": difference.inDays.toString(),
      "hours": (difference.inHours % 24).toString().padLeft(2, '0'),
      "minutes": (difference.inMinutes % 60).toString().padLeft(2, '0'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEDF2F1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CustomTimeBlock(value: timerData["days"]!, label: "أيام"),
          _buildDivider(),
          CustomTimeBlock(value: timerData["hours"]!, label: "ساعة"),
          _buildDivider(),
          CustomTimeBlock(value: timerData["minutes"]!, label: "دقيقة"),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(height: 45, width: 1.5, color: const Color(0xFFF0F4F3));
  }
}

class CustomTimeBlock extends StatelessWidget {
  const CustomTimeBlock({super.key, required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF064E3B),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
