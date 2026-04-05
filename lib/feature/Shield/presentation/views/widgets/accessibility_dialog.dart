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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5), // خلفية خضراء فاتحة جداً
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  // ignore: deprecated_member_use
                  color: const Color(0xFF10B981).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "اتبع الخطوات التالية:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF064E3B),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "1. اضغط على الزر بالأسفل.",
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 5),
                  // Text(
                  //   "2. ابحث عن 'التطبيقات التي تم تنزيلها' (Downloaded Apps).",
                  //   style: TextStyle(fontSize: 14),
                  // ),
                  // SizedBox(height: 5),
                  Text(
                    "3. اختر 'Maadh Smart Shield' وفعّله.",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
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
