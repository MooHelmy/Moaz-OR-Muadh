// ignore_for_file: deprecated_member_use

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
  bool isAntiUninstallActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInitialStatus();
    }
  }

  void _checkInitialStatus() async {
    final accessibilityStatus =
        await MaadhShieldManager.isAccessibilityEnabled();
    final antiUninstallStatus =
        await MaadhShieldManager.isAntiUninstallActive();

    if (mounted) {
      setState(() {
        isAccessibilityActive = accessibilityStatus;
        isAntiUninstallActive = antiUninstallStatus;
      });
    }
  }

  // ─── دالة رمز السري العام (للـ VPN وغيره) ───────────────────────────────────
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
                onPressed: () {
                  if (input == "0000") {
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

  // ─── تفعيل Anti-Uninstall ────────────────────────────────────────────────────
  Future<void> _enableAntiUninstall() async {
    // 1. توليد PIN وعرضه للمستخدم مرة واحدة فقط
    final pin = await MaadhShieldManager.generateAndSavePin();
    if (!mounted) return;

    bool userConfirmed = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          Icon(Icons.shield_rounded, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 12),
          const Text("رمز إلغاء الحماية"),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "احفظ هذا الرمز جيداً.\nستحتاجه لإيقاف الحماية لاحقاً.\nلن يظهر مجدداً!",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                pin.codeUnitAt(1).toString(), // عرض الرمز كأرقام فقط
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "⚠️ هذا الرمز لا يمكن استرجاعه",
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("إلغاء",
                style: TextStyle(color: Theme.of(ctx).colorScheme.secondary)),
          ),
          ElevatedButton(
            onPressed: () {
              userConfirmed = true;
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("حفظت الرمز ✓"),
          ),
        ],
      ),
    );

    if (!userConfirmed) return;

    // 2. طلب صلاحية Device Admin
    await MaadhShieldManager.requestAdmin();

    // 3. انتظر ثم تحقق لو تم التفعيل
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final isActive = await MaadhShieldManager.isAdminActive();
    if (isActive) {
      await MaadhShieldManager.setAntiUninstallActive(true);
      if (mounted) setState(() => isAntiUninstallActive = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("✅ تم تفعيل حماية التطبيق بنجاح"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("⚠️ لم يتم منح الصلاحية، الحماية غير مفعلة"),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // ─── إلغاء Anti-Uninstall ────────────────────────────────────────────────────
  Future<void> _disableAntiUninstall() async {
    String inputPin = "";

    final authorized = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setStateDialog) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: Row(children: [
                Icon(Icons.lock_open_rounded,
                    color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 12),
                const Text("إلغاء الحماية"),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "أدخل رمز الـ 6 أرقام الذي تم عرضه عند التفعيل",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    onChanged: (v) => inputPin = v,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        letterSpacing: 8,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: "",
                      hintText: "• • • • • •",
                      filled: true,
                      fillColor: Theme.of(ctx)
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
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text("إلغاء",
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.secondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final ok = await MaadhShieldManager.verifyPinAndRemoveAdmin(
                        inputPin);
                    if (ok) {
                      Navigator.pop(ctx, true);
                    } else {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: const Text("❌ رمز خاطئ! حاول مجدداً."),
                          backgroundColor: Theme.of(ctx).colorScheme.error,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.primary,
                    foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("تأكيد"),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (authorized) {
      await MaadhShieldManager.setAntiUninstallActive(false);
      if (mounted) {
        setState(() => isAntiUninstallActive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("✅ تم إلغاء حماية التطبيق"),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: [
        const CustomSectionTitel(title: "حماية النظام"),

        // ── VPN Card ────────────────────────────────────────
        CustomServiceCard(
          title: "حماية الشبكة (VPN)",
          desc: "تصفية المواقع عبر DNS آمن",
          icon: Icons.vpn_lock_rounded,
          isActive: isVpnActive,
          onChanged: (value) async {
            if (value) {
              setState(() => isVpnActive = true);
              MaadhShieldManager.toggleVpn(true);
            } else {
              bool authorized = await _showPinDialog();
              if (authorized) {
                setState(() => isVpnActive = false);
                MaadhShieldManager.toggleVpn(false);
              }
            }
          },
        ),

        // ── Accessibility Card ───────────────────────────────
        CustomServiceCard(
          title: "الحارس الذكي (Accessibility)",
          desc: "مراقبة الكلمات والمحتوى المباشر",
          icon: Icons.remove_red_eye_rounded,
          isActive: isAccessibilityActive,
          onChanged: (value) async {
            if (value) {
              return await showDialog(
                context: context,
                builder: (context) => MaadhAccessDialog(
                  onConfirm: () {
                    MaadhShieldManager.requestAccessibility();
                  },
                ),
              );
            } else {
              bool authorized = await _showPinDialog();
              if (authorized) {
                MaadhShieldManager.requestAccessibility();
              }
            }
          },
        ),

        const SizedBox(height: 20),
        const CustomSectionTitel(title: "الأمان المتقدم"),

        // ── Anti-Uninstall Card ──────────────────────────────
        CustomServiceCard(
          title: "قفل الحماية (Anti-Uninstall)",
          desc: isAntiUninstallActive
              ? "التطبيق محمي — لا يمكن حذفه"
              : "منع حذف التطبيق تماماً",
          icon: Icons.admin_panel_settings_rounded,
          isActive: isAntiUninstallActive,
          isWarning: true,
          onChanged: (value) async {
            if (value) {
              await _enableAntiUninstall();
            } else {
              await _disableAntiUninstall();
            }
          },
        ),

        const SizedBox(height: 30),
        const CustomSecurityHint(),
      ],
    );
  }
}
