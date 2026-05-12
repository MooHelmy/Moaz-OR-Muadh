import 'package:flutter/material.dart';
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
          const CustomSectionLabel(label: "إحصائيات الحماية العامة"),
          // بدلاً من سجل المعارك، نضع ملخصاً ذكياً لإنجاز التطبيق
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
              ],
            ),
            child: const Center(
                child: Text("سيتم هنا عرض إحصائيات المجلدات المحمية قريباً")),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
