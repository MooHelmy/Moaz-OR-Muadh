// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Shield/data/services/shield_state_service.dart';
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
  bool isAntiUninstallActive = false;
  bool isAdminPinActive = false;

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

  Future<void> _checkInitialStatus() async {
    final savedState = await ShieldStateService.loadState();
    final accessibilityStatus =
        await MaadhShieldManager.isAccessibilityEnabled();

    if (savedState.vpnActive) {
      await MaadhShieldManager.toggleVpn(true);
    }

    if (mounted) {
      setState(() {
        isVpnActive = savedState.vpnActive;
        isAccessibilityActive =
            accessibilityStatus || savedState.accessibilityActive;
        isAntiUninstallActive = savedState.antiUninstallActive;
        isAdminPinActive =
            savedState.adminPin != null && savedState.adminPin!.isNotEmpty;
      });
    }

    if (savedState.accessibilityActive && !accessibilityStatus && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRestoreAccessibilityDialog();
      });
    }
  }

  void _showRestoreAccessibilityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Text("إعادة تفعيل الحارس الذكي"),
          ],
        ),
        content: const Text(
          "الحارس الذكي محفوظ مفعلاً سابقاً. من فضلك أعد تفعيله من إعدادات الوصول.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("لاحقاً",
                style:
                    TextStyle(color: Theme.of(context).colorScheme.secondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              MaadhShieldManager.requestAccessibility();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text("اذهب للإعدادات"),
          ),
        ],
      ),
    );
  }

  Future<bool> _showSetPinDialog(String type) async {
    String pin = "";
    String confirmPin = "";
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Icon(Icons.lock, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(type == 'antiUninstall'
                    ? "اضبط رمز حماية عدم الحذف"
                    : type == 'accessibility'
                        ? "اضبط رمز حماية الحارس الذكي"
                        : "اضبط رمز المدير"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(type == 'antiUninstall'
                    ? "اختر رمزًا سريًا مختلفًا عن بقية المستخدمين لوقف حماية عدم حذف التطبيق."
                    : type == 'accessibility'
                        ? "اختر رمزًا سريًا مختلفًا عن بقية المستخدمين لوقف الحارس الذكي."
                        : "اختر رمزًا سريًا مختلفًا عن بقية المستخدمين لرمز المدير."),
                const SizedBox(height: 20),
                TextField(
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  onChanged: (v) => pin = v,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      letterSpacing: 8,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "الرمز",
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
                const SizedBox(height: 12),
                TextField(
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  onChanged: (v) => confirmPin = v,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      letterSpacing: 8,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "أعد كتابة الرمز",
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
              ElevatedButton(
                onPressed: () async {
                  if (pin.isEmpty || pin != confirmPin) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text("الرمز غير متطابق، حاول مرة أخرى."),
                        backgroundColor: Theme.of(context).colorScheme.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                    return;
                  }

                  if (type == 'antiUninstall') {
                    await ShieldStateService.saveAntiUninstallPin(pin);
                  } else if (type == 'accessibility') {
                    await ShieldStateService.saveAccessibilityPin(pin);
                  } else if (type == 'admin') {
                    await ShieldStateService.saveAdminPin(pin);
                  }

                  Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  "حفظ الرمز",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showPinDialog() async {
    return await _verifyPin('admin');
  }

  Future<bool> _verifyPin(String type) async {
    final state = await ShieldStateService.loadState();
    final correctPin = type == 'antiUninstall'
        ? state.antiUninstallPin
        : type == 'accessibility'
            ? state.accessibilityPin
            : state.adminPin;

    if ((correctPin == null || correctPin.isEmpty) &&
        !await ShieldStateService.hasPin('admin')) {
      return false;
    }

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
              ElevatedButton(
                onPressed: () async {
                  if (await ShieldStateService.validatePin(input, type)) {
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
              await ShieldStateService.updateVpnActive(true);
              MaadhShieldManager.toggleVpn(true);
            } else {
              // محاولة إيقاف -> طلب رمز سري
              bool authorized = await _showPinDialog();
              if (authorized) {
                setState(() => isVpnActive = false);
                await ShieldStateService.updateVpnActive(false);
                MaadhShieldManager.toggleVpn(false);
              }
            }
          },
        ),
        CustomServiceCard(
          title: "الحارس الذكي (Accessibility)",
          desc: "تعزيز الأمان للمحتوى المباشر",
          icon: Icons.remove_red_eye_rounded,
          isActive: isAccessibilityActive,
          onChanged: (value) async {
            if (value) {
              final hasPin = await ShieldStateService.hasPin('accessibility');
              if (!hasPin) {
                final created = await _showSetPinDialog('accessibility');
                if (!created) return;
              }
              await ShieldStateService.updateAccessibilityActive(true);
              setState(() => isAccessibilityActive = true);
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
              bool authorized = await _verifyPin('accessibility');
              if (authorized) {
                await ShieldStateService.updateAccessibilityActive(false);
                setState(() => isAccessibilityActive = false);
                MaadhShieldManager.requestAccessibility();
              }
            }
          },
        ),
        const SizedBox(height: 20),
        const CustomSectionTitel(title: "الأمان المتقدم"),
        CustomServiceCard(
          title: "رمز المدير",
          desc: "رمز إداري واحد للتحكم بكل الحماية",
          icon: Icons.admin_panel_settings_rounded,
          isActive: isAdminPinActive,
          onChanged: (value) async {
            if (value) {
              final created = await _showSetPinDialog('admin');
              if (!created) return;
              setState(() => isAdminPinActive = true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    "تم ضبط رمز المدير. يمكنك استخدامه للتحكم في أي حماية.",
                  ),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                ),
              );
            } else {
              final authorized = await _verifyPin('admin');
              if (authorized) {
                await ShieldStateService.removeAdminPin();
                setState(() => isAdminPinActive = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("تم حذف رمز المدير."),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            }
          },
        ),
        const SizedBox(height: 15),
        CustomServiceCard(
          title: "قفل الحماية (Anti-Uninstall)",
          desc: "حماية إضافية ضد الإزالة غير المصرح بها",
          icon: Icons.admin_panel_settings_rounded,
          isActive: isAntiUninstallActive,
          isWarning: true,
          onChanged: (value) async {
            if (value) {
              final hasPin = await ShieldStateService.hasPin('antiUninstall');
              if (!hasPin) {
                final created = await _showSetPinDialog('antiUninstall');
                if (!created) return;
              }
              setState(() => isAntiUninstallActive = true);
              await ShieldStateService.updateAntiUninstallActive(true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                      "تم تفعيل حماية عدم حذف التطبيق. لإيقافها تحتاج كلمة سر."),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                ),
              );
            } else {
              bool authorized = await _verifyPin('antiUninstall');
              if (authorized) {
                setState(() => isAntiUninstallActive = false);
                await ShieldStateService.updateAntiUninstallActive(false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        const Text("تم تعطيل الحماية بعد إدخال الرمز السري."),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            }
          },
        ),
        const SizedBox(height: 30),
        const CustomSecurityHint(),
      ],
    );
  }
}
