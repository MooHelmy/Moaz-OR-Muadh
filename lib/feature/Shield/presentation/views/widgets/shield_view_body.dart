import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/accessibility_dialog.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_section_titel.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_security_hint.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_service_card.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/shield_channel.dart';

class ShieldViewBody extends StatefulWidget {
  const ShieldViewBody({super.key});

  @override
  State<ShieldViewBody> createState() => _ShieldViewBodyState();
}

class _ShieldViewBodyState extends State<ShieldViewBody>
    with WidgetsBindingObserver {
  bool isVpnActive = false;
  bool isAccessibilityActive = false;

  @override
  void initState() {
    super.initState();
    // إضافة مراقب لحالة التطبيق
    WidgetsBinding.instance.addObserver(this);
    _checkInitialStatus();
  }

  @override
  void dispose() {
    // إزالة المراقب عند الخروج
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند العودة للتطبيق (Resumed)، تحقق من الحالة مجدداً
    if (state == AppLifecycleState.resumed) {
      _checkInitialStatus();
    }
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

  // دالة لإظهار نافذة طلب الرمز السري
  Future<bool> _showPinDialog() async {
    String input = "";
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("أدخل رمز الحماية"),
            content: TextField(
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              onChanged: (v) => input = v,
              decoration: const InputDecoration(
                hintText: "الرمز السري (0000)",
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () {
                  // هنا يمكنك تغيير الرمز "0000" لأي رمز تريده
                  if (input == "0000") {
                    Navigator.pop(context, true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("رمز خاطئ! لا يمكن إيقاف الحماية."),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF064E3B),
                ),
                child: const Text(
                  "تأكيد",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;
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
          onChanged: (value) async {
            if (value) {
              // تفعيل مباشر
              setState(() => isVpnActive = true);
              MaadhShieldManager.toggleVpn(true);
            } else {
              // محاولة إيقاف -> طلب رمز سري
              bool authorized = await _showPinDialog();
              if (authorized) {
                setState(() => isVpnActive = false);
                MaadhShieldManager.toggleVpn(false);
              }
            }
          },
        ),
        CustomServiceCard(
          title: "الحارس الذكي (Accessibility)",
          desc: "مراقبة الكلمات والمحتوى المباشر",
          icon: Icons.remove_red_eye_rounded,
          isActive: isAccessibilityActive,
          onChanged: (value) async {
            if (value) {
              // تفعيل -> الذهاب للإعدادات
              return await showDialog(
                context: context,
                builder: (context) => MaadhAccessDialog(
                  onConfirm: () {
                    MaadhShieldManager.requestAccessibility();
                  },
                ),
              );
            } else {
              // إيقاف -> طلب رمز سري أولاً
              bool authorized = await _showPinDialog();
              if (authorized) {
                // إذا الرمز صحيح، نرسله للإعدادات ليقوم بالإيقاف يدوياً
                MaadhShieldManager.requestAccessibility();
              }
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
