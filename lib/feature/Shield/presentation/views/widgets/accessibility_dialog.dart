import 'package:flutter/material.dart';

class MaadhAccessDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const MaadhAccessDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.security_update_good_rounded,
              size: 60,
              color: Color(0xFF10B981),
            ),
            const SizedBox(height: 15),
            const Text(
              "تفعيل الحارس الذكي",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF064E3B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "ليتمكن مَعاذ من حمايتك، يحتاج لتفعيل 'خدمة الوصول'.\n\n💡 في هواتف Realme:\nابحث عن 'التطبيقات التي تم تنزيلها' (Downloaded Apps) ثم اختر 'Maadh Smart Shield'.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onConfirm(); // هنا بننادي على الـ Method Channel
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF064E3B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                "اذهب للإعدادات وفعّل مَعاذ",
                style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "ليس الآن",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
