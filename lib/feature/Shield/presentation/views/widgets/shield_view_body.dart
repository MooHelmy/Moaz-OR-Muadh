import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/accessibility_dialog.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_section_titel.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_security_hint.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_service_card.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/shield_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShieldViewBody extends StatefulWidget {
  const ShieldViewBody({super.key});

  @override
  State<ShieldViewBody> createState() => _ShieldViewBodyState();
}

class _ShieldViewBodyState extends State<ShieldViewBody>
    with WidgetsBindingObserver {
  bool isVpnActive = false;
  bool isAccessibilityActive = false;
  bool isAntiUninstallActive = false;
  String _userPin = '';

  @override
  void initState() {
    super.initState();
    // إضافة مراقب لحالة التطبيق
    WidgetsBinding.instance.addObserver(this);
    _initializeUserPin();
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
    final antiUninstallStatus =
        await MaadhShieldManager.isAntiUninstallEnabled();
    if (mounted) {
      setState(() {
        isAccessibilityActive = accessibilityStatus;
        isAntiUninstallActive = antiUninstallStatus;
      });
    }
  }

  // دالة لتوليد رقم سري فريد لكل مستخدم
  Future<void> _initializeUserPin() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedPin = prefs.getString('user_unique_pin');

    if (savedPin == null) {
      // توليد رقم سري فريد بناءً على معرف الجهاز
      savedPin = await _generateUniquePin();
      await prefs.setString('user_unique_pin', savedPin);
    }

    setState(() {
      _userPin = savedPin!;
    });
  }

  // توليد رقم سري فريد بناءً على معرف الجهاز
  Future<String> _generateUniquePin() async {
    // الحصول على معرف فريد للجهاز (يمكن استخدام device_info_plus لاحقاً)
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSeed = random.nextInt(999999);

    // دمج البيانات لإنشاء hash فريد
    final uniqueData = '$timestamp-$randomSeed-${random.nextInt(10000)}';
    final bytes = utf8.encode(uniqueData);
    final hash = sha256.convert(bytes);

    // استخراج 4 أرقام من الـ hash
    final hashString = hash.toString();
    final numbers = hashString.replaceAll(RegExp(r'[^0-9]'), '');

    // التأكد من وجود 4 أرقام على الأقل
    if (numbers.length < 4) {
      // إذا لم يكن كافياً، أضف أرقام عشوائية
      final additionalNumbers =
          List.generate(4 - numbers.length, (_) => random.nextInt(10));
      return numbers + additionalNumbers.join('');
    }

    // أخذ أول 4 أرقام من الـ hash
    return numbers.substring(0, 4);
  }

  // دالة لإعادة تعيين الرقم السري
  Future<void> _resetUserPin() async {
    final newPin = await _generateUniquePin();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_unique_pin', newPin);

    setState(() {
      _userPin = newPin;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إعادة تعيين الرقم السري الجديد: $newPin'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // دالة لإظهار نافذة طلب الرمز السري
  Future<bool> _showPinDialog() async {
    String input = "";
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Icon(Icons.lock_person_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text("تأكيد الهوية"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("رقمك السري: $_userPin"),
                const SizedBox(height: 8),
                const Text("أدخل الرمز السري لإدارة إعدادات الحماية"),
                const SizedBox(height: 20),
                TextField(
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  onChanged: (v) => input = v,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      letterSpacing: 8,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "••••",
                    hintStyle: TextStyle(color: Theme.of(context).hintColor),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("إلغاء",
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary)),
              ),
              TextButton(
                onPressed: () async {
                  await _resetUserPin();
                  Navigator.pop(context, false);
                },
                child: const Text("إعادة تعيين الرقم",
                    style: TextStyle(color: Colors.orange)),
              ),
              ElevatedButton(
                onPressed: () {
                  // استخدام الرقم السري الفريد للمستخدم
                  if (input == _userPin) {
                    Navigator.pop(context, true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            const Text("رمز خاطئ! لا يمكن تعديل الإعدادات."),
                        backgroundColor: Theme.of(context).colorScheme.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
          desc: "المراقبة  المباشرة",
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
          isActive: isAntiUninstallActive,
          isWarning: true,
          onChanged: (value) async {
            if (value) {
              // تفعيل -> طلب رمز سري
              bool authorized = await _showPinDialog();
              if (authorized) {
                setState(() => isAntiUninstallActive = true);
                MaadhShieldManager.toggleAntiUninstall(true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✓ تم تفعيل قفل الحماية'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            } else {
              // إيقاف -> طلب رمز سري
              bool authorized = await _showPinDialog();
              if (authorized) {
                setState(() => isAntiUninstallActive = false);
                MaadhShieldManager.toggleAntiUninstall(false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✓ تم إيقاف قفل الحماية'),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            }
          },
        ),
        const SizedBox(height: 30),
        // زر لعرض الرقم السري
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.pin_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'رقمك السري الحالي',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _userPin.isEmpty ? 'جاري التحميل...' : _userPin,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'احتفظ بهذا الرقم آمناً',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const CustomSecurityHint(),
      ],
    );
  }
}
