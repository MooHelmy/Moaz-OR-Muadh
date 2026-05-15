// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:medi_guard/core/constants/keys.dart';
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

  // Helper for showing consistent SnackBars
  void _showSnackBar(String message,
      {Color? backgroundColor, bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ??
            (isError ? Theme.of(context).colorScheme.error : Colors.green),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─── دالة رمز السري العام (للـ VPN وغيره) ───────────────────────────────────
  Future<bool> _showPinDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => PinInputAlertDialog(
            title: "تأكيد الهوية",
            description: "أدخل الرمز السري لإدارة إعدادات الحماية",
            icon: Icons.lock_person_rounded,
            maxLength: 4, // Assuming KAccessibility is a 4-digit PIN
            hintText: "••••",
            onConfirm: (pin) {
              if (pin == KAccessibility) {
                Navigator.pop(context, true);
              } else {
                _showSnackBar("رمز خاطئ! لا يمكن تعديل الإعدادات.",
                    isError: true);
              }
            },
            onCancel: () => Navigator.pop(context, false),
          ),
        ) ??
        false;
  }

  // ─── تفعيل Anti-Uninstall ────────────────────────────────────────────────────
  // Delay duration for checking admin status after request
  static const _adminRequestDelay = Duration(seconds: 2);

  Future<void> _enableAntiUninstall() async {
    // 1. توليد PIN وعرضه للمستخدم مرة واحدة فقط
    final pin = await MaadhShieldManager.generateAndSavePin();
    if (!mounted) return;

    // Mask the PIN: show the first two digits and mask the rest with hash symbols.
    final maskedPin = pin.substring(0, 2) + '#&\$';

    bool userConfirmed = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GeneratedPinDisplayDialog(
        maskedPin: maskedPin,
        onConfirm: () {
          userConfirmed = true;
          Navigator.pop(ctx);
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );

    if (!userConfirmed) return;

    // 2. طلب صلاحية Device Admin
    await MaadhShieldManager.requestAdmin();

    // 3. انتظر ثم تحقق لو تم التفعيل
    await Future.delayed(_adminRequestDelay);
    if (!mounted) return;

    final isActive = await MaadhShieldManager.isAdminActive();
    if (isActive) {
      await MaadhShieldManager.setAntiUninstallActive(true);
      if (mounted) setState(() => isAntiUninstallActive = true);
      _showSnackBar("✅ تم تفعيل حماية التطبيق بنجاح");
    } else {
      _showSnackBar("⚠️ لم يتم منح الصلاحية، الحماية غير مفعلة", isError: true);
    }
  }

  // ─── إلغاء Anti-Uninstall ────────────────────────────────────────────────────
  Future<void> _disableAntiUninstall() async {
    final authorized = await showDialog<bool>(
          context: context,
          builder: (ctx) => PinInputAlertDialog(
            title: "إلغاء الحماية",
            description: "أدخل رمز الـ 6 أرقام الذي تم عرضه عند التفعيل",
            icon: Icons.lock_open_rounded,
            maxLength: 6,
            hintText: "• • • • • •",
            onConfirm: (inputPin) async {
              final ok =
                  await MaadhShieldManager.verifyPinAndRemoveAdmin(inputPin);
              if (ok) {
                if (mounted) Navigator.pop(ctx, true);
              } else {
                if (mounted) {
                  _showSnackBar("❌ رمز خاطئ! حاول مجدداً.", isError: true);
                }
              }
            },
            onCancel: () => Navigator.pop(ctx, false),
          ),
        ) ??
        false;

    if (authorized) {
      await MaadhShieldManager.setAntiUninstallActive(false);
      if (mounted) {
        setState(() => isAntiUninstallActive = false);
        _showSnackBar("✅ تم إلغاء حماية التطبيق",
            backgroundColor: Colors.orange);
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

// Extracted Widget for a generic PIN input dialog
class PinInputAlertDialog extends StatefulWidget {
  final String title;
  final String description;
  final int maxLength;
  final Function(String pin) onConfirm;
  final VoidCallback onCancel;
  final String hintText;
  final IconData icon;

  const PinInputAlertDialog({
    Key? key,
    required this.title,
    required this.description,
    this.maxLength = 6,
    required this.onConfirm,
    required this.onCancel,
    this.hintText = "• • • • • •",
    required this.icon,
  }) : super(key: key);

  @override
  State<PinInputAlertDialog> createState() => PinInputAlertDialogState();
}

class PinInputAlertDialogState extends State<PinInputAlertDialog> {
  String _inputPin = "";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(widget.icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(widget.title),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.description,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: widget.maxLength,
            onChanged: (v) => setState(() => _inputPin = v),
            textAlign: TextAlign.center,
            style: const TextStyle(
                letterSpacing: 8, fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: "",
              hintText: widget.hintText,
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          onPressed: widget.onCancel,
          child: Text("إلغاء",
              style: TextStyle(color: theme.colorScheme.secondary)),
        ),
        ElevatedButton(
          onPressed: () => widget.onConfirm(_inputPin),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("تأكيد"),
        ),
      ],
    );
  }
}

// Extracted Widget for displaying the generated PIN once
class _GeneratedPinDisplayDialog extends StatelessWidget {
  final String maskedPin;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _GeneratedPinDisplayDialog({
    Key? key,
    required this.maskedPin,
    required this.onConfirm,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              maskedPin,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: theme.colorScheme.onPrimaryContainer,
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
          onPressed: onCancel,
          child: Text("إلغاء",
              style: TextStyle(color: theme.colorScheme.secondary)),
        ),
        ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("حفظت الرمز ✓"),
        ),
      ],
    );
  }
}
