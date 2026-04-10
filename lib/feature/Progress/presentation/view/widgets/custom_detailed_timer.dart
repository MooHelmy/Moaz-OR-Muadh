import 'package:flutter/material.dart';

class CustomDetailedTimer extends StatefulWidget {
  const CustomDetailedTimer({super.key, required this.snapshot});
  final AsyncSnapshot<Map<String, int>> snapshot;

  @override
  State<CustomDetailedTimer> createState() => _CustomDetailedTimerState();
}

class _CustomDetailedTimerState extends State<CustomDetailedTimer> {
  @override
  Widget build(BuildContext context) {
    // Extract data safely, providing defaults if the snapshot is loading or null
    final Map<String, int> timerData =
        widget.snapshot.data ?? {"days": 0, "hours": 0, "minutes": 0};

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
          CustomTimetBlock(value: timerData["days"].toString(), label: "أيام"),
          _buildDivider(),
          CustomTimetBlock(value: timerData["hours"].toString(), label: "ساعة"),
          _buildDivider(),
          CustomTimetBlock(
            value: timerData["minutes"].toString(),
            label: "دقيقة",
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(height: 45, width: 1.5, color: const Color(0xFFF0F4F3));
  }
}

class CustomTimetBlock extends StatelessWidget {
  const CustomTimetBlock({super.key, required this.value, required this.label});
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
