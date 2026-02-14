import 'package:flutter/material.dart';
import 'package:muadh/feature/home/presentation/views/widgets/custom_emergency_button.dart';

class CustomVerseCard extends StatelessWidget {
  const CustomVerseCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 25),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "«مَعَاذَ اللَّهِ ۖ إِنَّهُ رَبِّي أَحْسَنَ مَثْوَايَ»",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              color: Color(0xFF064E3B),
              fontWeight: FontWeight.bold,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 25),
          const EmergencyActionButton(), // زر منفصل لسهولة التعديل
        ],
      ),
    );
  }
}
