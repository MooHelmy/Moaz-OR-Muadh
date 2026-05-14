// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:medi_guard/core/utils/pin_security_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DeveloperScreen — شاشة مخفية للمطور
// تُفتح بـ 7 نقرات على اسم التطبيق في الـ TopBar
// ─────────────────────────────────────────────────────────────────────────────
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  SharedPreferences? _prefs;
  bool _authenticated = false;
  bool _loading = true;
  bool _hasMaster = false;

  final _authController = TextEditingController();
  final _newMasterCtrl = TextEditingController();
  final _confirmMasterCtrl = TextEditingController();
  bool _obscureAuth = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _authError;
  String? _saveError;
  String? _saveSuccess;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasMaster = PinSecurityService.hasMasterPin(_prefs!);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _authController.dispose();
    _newMasterCtrl.dispose();
    _confirmMasterCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    final pin = _authController.text.trim();
    if (pin.isEmpty) return;

    if (PinSecurityService.isLocked(_prefs!)) {
      final rem = PinSecurityService.lockRemaining(_prefs!);
      final mins = rem.inMinutes.toString();
      final secs = (rem.inSeconds % 60).toString().padLeft(2, '0');
      setState(() => _authError = 'محاولات كثيرة — انتظر $mins:$secs');
      return;
    }

    if (PinSecurityService.verifyMasterPin(_prefs!, pin)) {
      await PinSecurityService.resetFailedAttempts(_prefs!);
      setState(() {
        _authenticated = true;
        _authError = null;
      });
    } else {
      await PinSecurityService.recordFailedAttempt(_prefs!);
      final rem = PinSecurityService.remainingAttempts(_prefs!);
      setState(() => _authError = rem > 0
          ? 'كلمة المرور غلط — باقي $rem محاولة'
          : 'تم تجميد الدخول لمدة 3 دقائق');
    }
  }

  Future<void> _saveMasterPin() async {
    final newPin = _newMasterCtrl.text.trim();
    final confirm = _confirmMasterCtrl.text.trim();

    if (newPin.length < 8) {
      setState(() {
        _saveError = 'لازم يكون 8 أحرف على الأقل';
        _saveSuccess = null;
      });
      return;
    }
    if (newPin != confirm) {
      setState(() {
        _saveError = 'كلمتا المرور مش متطابقتين';
        _saveSuccess = null;
      });
      return;
    }

    await PinSecurityService.saveMasterPin(_prefs!, newPin);
    _newMasterCtrl.clear();
    _confirmMasterCtrl.clear();
    setState(() {
      _hasMaster = true;
      _saveError = null;
      _saveSuccess = '✓ تم حفظ الـ Master PIN';
    });
  }

  Future<void> _resetUserPin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد إعادة التعيين'),
        content: const Text('هيتم توليد رقم سري جديد للمستخدم. متأكد؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ts = DateTime.now().microsecondsSinceEpoch;
    final newPin = (ts % 900000 + 100000).toString();
    await PinSecurityService.saveUserPin(_prefs!, newPin);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('رقم المستخدم الجديد: $newPin  (سيُحذف من هنا بعد 10 ثواني)'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 10),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('⚙️ وضع المطور', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _authenticated ? _buildPanel() : _buildAuthGate(),
        ),
      ),
    );
  }

  Widget _buildAuthGate() => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.shield_moon_rounded,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          const Text('وضع المطور',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _hasMaster ? 'أدخل Master PIN' : 'لم يتم تعيين Master PIN بعد',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          if (_hasMaster) ...[
            TextField(
              controller: _authController,
              obscureText: _obscureAuth,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  letterSpacing: 4, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '••••••••',
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureAuth ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureAuth = !_obscureAuth),
                ),
              ),
              onSubmitted: (_) => _authenticate(),
            ),
            if (_authError != null) ...[
              const SizedBox(height: 10),
              Text(_authError!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _authenticate,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('دخول', style: TextStyle(fontSize: 16)),
              ),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'عيّن Master PIN من أول تشغيل في debug mode',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      );

  Widget _buildPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Master PIN'),
          _card(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_hasMaster ? 'تغيير الـ Master PIN' : 'تعيين Master PIN',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 4),
              Text('8 أحرف على الأقل',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              _pinField('Master PIN الجديد', _newMasterCtrl, _obscureNew,
                  () => setState(() => _obscureNew = !_obscureNew)),
              const SizedBox(height: 10),
              _pinField('تأكيد Master PIN', _confirmMasterCtrl, _obscureConfirm,
                  () => setState(() => _obscureConfirm = !_obscureConfirm)),
              if (_saveError != null) ...[
                const SizedBox(height: 8),
                Text(_saveError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              if (_saveSuccess != null) ...[
                const SizedBox(height: 8),
                Text(_saveSuccess!,
                    style: const TextStyle(color: Colors.green, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveMasterPin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('حفظ'),
                ),
              ),
            ],
          )),
          const SizedBox(height: 20),
          _sectionTitle('إدارة المستخدم'),
          _card(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('إعادة تعيين رقم المستخدم',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 4),
              Text('يُولَّد رقم جديد ويُعرض لك',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _resetUserPin,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.orange),
                  label: const Text('إعادة تعيين',
                      style: TextStyle(color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          )),
          const SizedBox(height: 20),
          _sectionTitle('معلومات الأمان'),
          _card(
              child: Column(children: [
            _infoRow('تشفير الـ PIN', 'SHA-256 + salt'),
            _infoRow('الـ Lockout', '5 محاولات / 3 دقائق'),
            _infoRow('User PIN', '6 أرقام'),
            _infoRow('Master PIN', '8+ أحرف'),
          ])),
          const SizedBox(height: 30),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withOpacity(0.4)),
        ),
        child: child,
      );

  Widget _pinField(String label, TextEditingController ctrl, bool obs,
          VoidCallback toggle) =>
      TextField(
        controller: ctrl,
        obscureText: obs,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          suffixIcon: IconButton(
              icon: Icon(obs ? Icons.visibility_off : Icons.visibility),
              onPressed: toggle),
        ),
      );

  Widget _infoRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(v,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
