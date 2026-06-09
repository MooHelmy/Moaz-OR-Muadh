import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionScreen extends StatefulWidget {
  final void Function(bool showAccessibilityOnboarding) onGranted;
  const PermissionScreen({super.key, required this.onGranted});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _requesting = false;
  bool _waitingForSettingsReturn = false;

  // ✅ نحفظ الـ SDK version مرة واحدة
  int _sdkInt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    // نجيب الـ SDK version
    _sdkInt = await _getAndroidSdk();
    await _checkIfAlreadyGranted();
  }

  Future<int> _getAndroidSdk() async {
    try {
      // طريقة بسيطة بدون package إضافية
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 30;
    } catch (_) {
      return 30; // fallback آمن
    }
  }

  // ✅ تحديد الـ permissions المطلوبة حسب الـ SDK
  bool get _needsManageStorage => _sdkInt >= 30; // Android 11+
  bool get _needsMediaPermissions => _sdkInt >= 33; // Android 13+

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettingsReturn) {
      _waitingForSettingsReturn = false;
      _continueAfterManageStorageSettings();
    }
  }

  Future<void> _checkIfAlreadyGranted() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyGranted = prefs.getBool('permissions_granted') ?? false;

    if (alreadyGranted) {
      final storageOk = await _isStorageGranted();
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

  // ✅ يتحقق من الـ storage بكل الطرق الممكنة حسب الـ SDK
  Future<bool> _isStorageGranted() async {
    // Android 11+ → MANAGE_EXTERNAL_STORAGE
    if (_needsManageStorage) {
      if (await Permission.manageExternalStorage.isGranted) return true;
    }
    // Android 13+ → READ_MEDIA_IMAGES / VIDEO
    if (_needsMediaPermissions) {
      if (await Permission.photos.isGranted ||
          await Permission.videos.isGranted) return true;
    }
    // Android 10 وأقل → READ_EXTERNAL_STORAGE
    if (await Permission.storage.isGranted) return true;

    return false;
  }

  Future<void> _requestAll() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    try {
      if (_needsManageStorage) {
        // ─── Android 11+ ──────────────────────────────────────────────────
        // MANAGE_EXTERNAL_STORAGE بتفتح Settings خارجية
        // Samsung/Huawei بيعملوا Activity recreation لما ترجع
        if (await Permission.manageExternalStorage.isDenied) {
          _waitingForSettingsReturn = true;
          await Permission.manageExternalStorage.request();

          // بعض الأجهزة بترد فوراً (emulators/Pixel)
          await Future.delayed(const Duration(milliseconds: 600));

          // لو لسه بنستنى → didChangeAppLifecycleState هيكمل
          if (_waitingForSettingsReturn) return;
        } else {
          await _continueAfterManageStorageSettings();
        }
      } else {
        // ─── Android 10 وأقل ───────────────────────────────────────────────
        await _requestLegacyStorage();
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _continueAfterManageStorageSettings() async {
    try {
      final manageGranted = await Permission.manageExternalStorage.isGranted;

      if (!manageGranted) {
        // ✅ FIX: لو MANAGE_EXTERNAL_STORAGE اترفضت (emulator / no Play Store)
        // نحاول fallback لـ READ_MEDIA أو READ_EXTERNAL_STORAGE بدل كراش
        debugPrint('MANAGE_EXTERNAL_STORAGE denied → trying fallback');
        await _requestFallbackStorage();
        return;
      }

      await _requestNotificationAndFinish();
    } catch (e) {
      debugPrint('Continue after settings error: $e');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  // ✅ Fallback: Android 13+ → READ_MEDIA، أقل → READ_EXTERNAL_STORAGE
  Future<void> _requestFallbackStorage() async {
    try {
      if (_needsMediaPermissions) {
        // Android 13+ 
        await Permission.photos.request();
        await Future.delayed(const Duration(milliseconds: 300));
        await Permission.videos.request();
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        // Android 11-12
        await Permission.storage.request();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      await _requestNotificationAndFinish();
    } catch (e) {
      debugPrint('Fallback storage error: $e');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  // ✅ Android 10 وأقل
  Future<void> _requestLegacyStorage() async {
    try {
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await _requestNotificationAndFinish();
    } catch (e) {
      debugPrint('Legacy storage error: $e');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _requestNotificationAndFinish() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final storageGranted = await _isStorageGranted();

    if (!mounted) return;

    if (storageGranted) {
      final prefs = await SharedPreferences.getInstance();
      final alreadyShown =
          prefs.getBool('accessibility_onboarding_shown') ?? false;

      await prefs.setBool('permissions_granted', true);
      if (!alreadyShown) {
        await prefs.setBool('accessibility_onboarding_shown', true);
      }

      widget.onGranted(!alreadyShown);
    } else {
      // كل المحاولات فشلت → افتح Settings
      await openAppSettings();
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
