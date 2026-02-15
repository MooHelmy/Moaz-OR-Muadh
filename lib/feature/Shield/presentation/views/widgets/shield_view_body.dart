import 'package:flutter/material.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/custom_section_titel.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/custom_security_hint.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/custom_service_card.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/shield_channel.dart';

class ShieldViewBody extends StatefulWidget {
  const ShieldViewBody({super.key});

  @override
  State<ShieldViewBody> createState() => _ShieldViewBodyState();
}

class _ShieldViewBodyState extends State<ShieldViewBody> {
  bool isVpnActive = false;
  bool isAccessibilityActive = false;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
  }

  void _checkInitialStatus() async {
    final accessibilityStatus =
        await MaadhShieldManager.isAccessibilityEnabled();
    if (mounted) {
      setState(() {
        isAccessibilityActive = accessibilityStatus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: [
        const CustomSectionTitel(title: "حماية النظام"),
        CustomServiceCard(
          title: "حماية الشبكة (VPN)",
          desc: "تصفية المواقع عبر DNS آمن",
          icon: Icons.vpn_lock_rounded,
          isActive: isVpnActive,
          onChanged: (value) {
            setState(() => isVpnActive = value);
            MaadhShieldManager.toggleVpn(value);
          },
        ),
        CustomServiceCard(
          title: "الحارس الذكي (Accessibility)",
          desc: "مراقبة الكلمات والمحتوى المباشر",
          icon: Icons.remove_red_eye_rounded,
          isActive: isAccessibilityActive,
          onChanged: (value) {
            if (value) {
              MaadhShieldManager.requestAccessibility();
            }
          },
        ),
        const SizedBox(height: 20),
        const CustomSectionTitel(title: "الأمان المتقدم"),
        CustomServiceCard(
          title: "قفل الحماية (Anti-Uninstall)",
          desc: "منع حذف التطبيق تماماً",
          icon: Icons.admin_panel_settings_rounded,
          isActive: false,
          isWarning: true,
          onChanged: (value) {
            // سيتم إضافة هذه الميزة لاحقاً
          },
        ),
        const SizedBox(height: 30),
        const CustomSecurityHint(),
      ],
    );
  }
}
