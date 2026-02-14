import 'package:flutter/material.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/custom_section_titel.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/custom_security_hint.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/custom_service_card.dart';

class ShieldViewBody extends StatelessWidget {
  const ShieldViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: [
        CustomSectionTitel(title: "حماية النظام"), // Custom Widget 2
        CustomServiceCard(
          title: "حماية الشبكة (VPN)",
          desc: "تصفية المواقع عبر DNS آمن",
          icon: Icons.vpn_lock_rounded,
          isActive: true,
        ), // Custom Widget 3
        CustomServiceCard(
          title: "الحارس الذكي (Accessibility)",
          desc: "مراقبة الكلمات والمحتوى المباشر",
          icon: Icons.remove_red_eye_rounded,
          isActive: true,
        ),
        SizedBox(height: 20),
        CustomSectionTitel(title: "الأمان المتقدم"),
        CustomServiceCard(
          title: "قفل الحماية (Anti-Uninstall)",
          desc: "منع حذف التطبيق تماماً",
          icon: Icons.admin_panel_settings_rounded,
          isActive: false,
          isWarning: true, // لتغيير اللون للأحمر
        ),
        SizedBox(height: 30),
        CustomSecurityHint(), // Custom Widget 4
      ],
    );
  }
}
