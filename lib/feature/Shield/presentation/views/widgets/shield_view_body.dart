import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/accessibility_dialog.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_section_titel.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_security_hint.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_service_card.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/shield_channel.dart';
import 'package:medi_guard/core/utils/pin_security_service.dart';
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

  // ── PIN state (مخفي عن المستخدم تماماً)
  String _userPin = '';
  SharedPreferences? _prefs;

  // ── Master PIN — يُقرأ من PinSecurityService (يُحفظ من DeveloperScreen)

  // ── Lockout state
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  static const int _maxAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 2);

  // ── Lifecycle debounce
  int _lastLifecycleCheck = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPrefs();
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
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastLifecycleCheck > 4000) {
        _lastLifecycleCheck = now;
        _checkInitialStatus();
      }
    }
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _initializeUserPin();
    _loadLockoutState();
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

  // ── PIN: توليد وتحميل — مخفي عن المستخدم ────────────────────────────────

  Future<void> _initializeUserPin() async {
    if (_prefs == null) return;
    String? savedPin = _prefs!.getString('user_unique_pin');
    if (savedPin == null) {
      savedPin = _generatePin();
      await _prefs!.setString('user_unique_pin', savedPin);
    }
    // لا نعرض الـ PIN في الـ UI — بس نخزنه في الـ state للتحقق الداخلي
    _userPin = savedPin;
  }

  String _generatePin() {
    final random = Random.secure();
    // 8 أرقام عشوائية — أصعب من 4 للتخمين
    return List.generate(8, (_) => random.nextInt(10)).join();
  }

  // ── Lockout: تحميل وحفظ ───────────────────────────────────────────────────

  void _loadLockoutState() {
    if (_prefs == null) return;
    _failedAttempts = _prefs!.getInt('pin_failed_attempts') ?? 0;
    final lockoutMs = _prefs!.getInt('pin_lockout_until');
    if (lockoutMs != null) {
      _lockoutUntil = DateTime.fromMillisecondsSinceEpoch(lockoutMs);
    }
  }

  Future<void> _saveLockoutState() async {
    await _prefs!.setInt('pin_failed_attempts', _failedAttempts);
    if (_lockoutUntil != null) {
      await _prefs!
          .setInt('pin_lockout_until', _lockoutUntil!.millisecondsSinceEpoch);
    } else {
      await _prefs!.remove('pin_lockout_until');
    }
  }

  bool get _isLockedOut {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isBefore(_lockoutUntil!)) return true;
    _lockoutUntil = null;
    _failedAttempts = 0;
    _saveLockoutState();
    return false;
  }

  String get _lockoutRemaining {
    if (_lockoutUntil == null) return '';
    final remaining = _lockoutUntil!.difference(DateTime.now());
    if (remaining.isNegative) return '';
    final mins = remaining.inMinutes;
    final secs = remaining.inSeconds % 60;
    return mins > 0 ? '$mins د $secs ث' : '$secs ث';
  }

  Future<void> _recordFailedAttempt() async {
    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      _lockoutUntil = DateTime.now().add(_lockoutDuration);
      _failedAttempts = 0;
    }
    await _saveLockoutState();
  }

  Future<void> _recordSuccessfulAuth() async {
    _failedAttempts = 0;
    _lockoutUntil = null;
    await _saveLockoutState();
  }

  // ── Dialog التحقق من الـ PIN ───────────────────────────────────────────────

  Future<bool> _showPinDialog() async {
    if (_isLockedOut) {
      _showLockoutSnack();
      return false;
    }

    String input = '';
    bool? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final locked = _isLockedOut;
          final remaining = _lockoutRemaining;

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Icon(Icons.lock_person_rounded,
                    color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('تأكيد الهوية'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locked)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.block_rounded,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'محاولات كتير. انتظر $remaining',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    _failedAttempts > 0
                        ? 'محاولة ${_failedAttempts + 1} من $_maxAttempts'
                        : 'أدخل الرمز السري لإدارة إعدادات الحماية',
                    style: TextStyle(
                      fontSize: 13,
                      color: _failedAttempts > 0
                          ? Colors.orange
                          : Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 12,
                    onChanged: (v) => input = v,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        letterSpacing: 8,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••',
                      hintStyle: TextStyle(color: Theme.of(ctx).hintColor),
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
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  result = false;
                  Navigator.pop(dialogCtx);
                },
                child: Text('إلغاء',
                    style:
                        TextStyle(color: Theme.of(ctx).colorScheme.secondary)),
              ),
              if (!locked)
                ElevatedButton(
                  onPressed: () async {
                    final authorized = await _verifyPin(input);
                    if (authorized) {
                      result = true;
                      Navigator.pop(dialogCtx);
                    } else {
                      HapticFeedback.heavyImpact();
                      await _recordFailedAttempt();
                      setDialogState(() {});
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_isLockedOut
                              ? 'تم القفل. انتظر $_lockoutRemaining'
                              : 'رمز خاطئ — ${_maxAttempts - _failedAttempts} محاولات متبقية'),
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
                    backgroundColor: Theme.of(ctx).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('تأكيد',
                      style: TextStyle(color: Colors.white)),
                ),
            ],
          );
        },
      ),
    );

    return result ?? false;
  }

  // ── التحقق: يستخدم PinSecurityService (master أو user PIN) ──────────────

  Future<bool> _verifyPin(String input) async {
    if (input.isEmpty || _prefs == null) return false;

    final ok = PinSecurityService.verifyAny(_prefs!, input);
    if (ok) {
      await _recordSuccessfulAuth();
      return true;
    }
    return false;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showLockoutSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔒 محظور مؤقتاً — انتظر $_lockoutRemaining'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      children: [
        const CustomSectionTitel(title: 'حماية النظام'),
        CustomServiceCard(
          title: 'حماية الشبكة (VPN)',
          desc: 'تصفية المواقع عبر DNS آمن',
          icon: Icons.vpn_lock_rounded,
          isActive: isVpnActive,
          onChanged: (value) async {
            if (value) {
              setState(() => isVpnActive = true);
              MaadhShieldManager.toggleVpn(true);
            } else {
              if (_isLockedOut) {
                _showLockoutSnack();
                return;
              }
              final authorized = await _showPinDialog();
              if (authorized) {
                setState(() => isVpnActive = false);
                MaadhShieldManager.toggleVpn(false);
              }
            }
          },
        ),
        CustomServiceCard(
          title: 'الحارس الذكي (Accessibility)',
          desc: 'المراقبة المباشرة',
          icon: Icons.remove_red_eye_rounded,
          isActive: isAccessibilityActive,
          onChanged: (value) async {
            if (value) {
              return await showDialog(
                context: context,
                builder: (context) => MaadhAccessDialog(
                  onConfirm: () => MaadhShieldManager.requestAccessibility(),
                ),
              );
            } else {
              if (_isLockedOut) {
                _showLockoutSnack();
                return;
              }
              final authorized = await _showPinDialog();
              if (authorized) MaadhShieldManager.requestAccessibility();
            }
          },
        ),
        const SizedBox(height: 20),
        const CustomSectionTitel(title: 'الأمان المتقدم'),
        CustomServiceCard(
          title: 'قفل الحماية (Anti-Uninstall)',
          desc: 'منع حذف التطبيق تماماً',
          icon: Icons.admin_panel_settings_rounded,
          isActive: isAntiUninstallActive,
          isWarning: true,
          onChanged: (value) async {
            if (_isLockedOut) {
              _showLockoutSnack();
              return;
            }
            final authorized = await _showPinDialog();
            if (!authorized) return;
            setState(() => isAntiUninstallActive = value);
            MaadhShieldManager.toggleAntiUninstall(value);
            _showSuccessSnack(
                value ? '✓ تم تفعيل قفل الحماية' : '✓ تم إيقاف قفل الحماية');
          },
        ),
        const SizedBox(height: 20),
        const CustomSecurityHint(),
      ],
    );
  }
}
