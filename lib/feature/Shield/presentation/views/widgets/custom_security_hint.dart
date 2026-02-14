import 'package:flutter/material.dart';

class CustomSecurityHint extends StatelessWidget {
  const CustomSecurityHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4F1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB2DFD6)),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Color(0xFF064E3B), size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "تفعيل هذه الدروع هو استعانة بالأسباب لثبات القلب. نسأل الله لنا ولك العصمة من الفتن.",
              style: TextStyle(
                color: Color(0xFF064E3B),
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
