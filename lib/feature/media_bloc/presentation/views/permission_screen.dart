import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionScreen extends StatefulWidget {
  final void Function(bool showAccessibilityOnboarding) onGranted;
  const PermissionScreen({super.key, required this.onGranted});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _loading = true;
  bool _requesting = false; // ← منع double-tap أو double-call

  @override
  void initState() {
    super.initState();
    _checkIfAlreadyGranted();
  }

  Future<void> _checkIfAlreadyGranted() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyGranted = prefs.getBool('permissions_granted') ?? false;

    if (alreadyGranted) {
      final storageOk = await Permission.manageExternalStorage.isGranted ||
          await Permission.storage.isGranted;

      if (storageOk && mounted) {
        final showOnboarding =
            !(prefs.getBool('accessibility_onboarding_shown') ?? false);
        if (showOnboarding) {
          await prefs.setBool('accessibility_onboarding_shown', true);
        }
        widget.onGranted(showOnboarding);
        return;
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestAll() async {
    // منع التنفيذ المزدوج
    if (_requesting) return;
    setState(() => _requesting = true);

    try {
      // ✅ نطلب الصلاحيات واحدة واحدة مع await كامل بينهم
      // manageExternalStorage أولاً لأنها الأهم
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
        // ننتظر شوية عشان Android يستقر بعد الـ dialog
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final storageGranted = await Permission.manageExternalStorage.isGranted ||
          await Permission.storage.isGranted;

      if (!mounted) return;

      if (storageGranted) {
        final prefs = await SharedPreferences.getInstance();
        final alreadyShown =
            prefs.getBool('accessibility_onboarding_shown') ?? false;
        final showOnboarding = !alreadyShown;

        await prefs.setBool('permissions_granted', true);
        if (showOnboarding) {
          await prefs.setBool('accessibility_onboarding_shown', true);
        }

        widget.onGranted(showOnboarding);
      } else {
        // المستخدم رفض — افتح الإعدادات
        await openAppSettings();
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Color(0xFF10B981)),
              const SizedBox(height: 24),
              const Text(
                'معاذ يحتاج صلاحية الوصول للملفات\nعشان يحميك تلقائياً',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'لن تُسأل مرة أخرى بعد المنح',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                // لو بيشتغل → disable الزر
                onPressed: _requesting ? null : _requestAll,
                icon: _requesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_open),
                label: Text(
                    _requesting ? 'جاري المنح...' : 'منح الصلاحيات والبدء'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF064E3B),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
