import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:medi_guard/core/constants/keys.dart';

class MaadhShieldManager {
  static const platform = MethodChannel('com.maadh.shield/vpn');
  static const _adminChannel = MethodChannel('com.maadh.shield/admin');

  // ─── VPN ────────────────────────────────────────────────────────────────────
  static Future<void> toggleVpn(bool isActive) async {
    try {
      if (isActive) {
        await platform.invokeMethod('startVpn');
      } else {
        await platform.invokeMethod('stopVpn');
      }
    } on PlatformException catch (e) {
      log("خطأ في الـ VPN: ${e.message}");
    }
  }

  // ─── Accessibility ──────────────────────────────────────────────────────────
  static Future<void> requestAccessibility() async {
    try {
      await platform.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      log("خطأ في فتح الإعدادات: ${e.message}");
    }
  }

  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await platform.invokeMethod('isAccessibilityEnabled') ?? false;
    } on PlatformException catch (e) {
      log("فشل التحقق من الحارس: ${e.message}");
      return false;
    }
  }

  // ─── Anti-Uninstall (Device Admin) ──────────────────────────────────────────

  /// هل صلاحية Device Admin مفعلة حالياً؟
  static Future<bool> isAdminActive() async {
    try {
      return await _adminChannel.invokeMethod('isAdminActive') ?? false;
    } on PlatformException catch (e) {
      log("فشل التحقق من Admin: ${e.message}");
      return false;
    }
  }

  /// فتح شاشة تفعيل صلاحية Device Admin
  static Future<void> requestAdmin() async {
    try {
      await _adminChannel.invokeMethod('requestAdmin');
    } on PlatformException catch (e) {
      log("خطأ في طلب Admin: ${e.message}");
    }
  }

  /// توليد PIN عشوائي من 6 أرقام — يُحفظ كـ hash في Native ويُرجع للـ Flutter مرة واحدة فقط
  static Future<String> generateAndSavePin() async {
    try {
      return await _adminChannel.invokeMethod('generateAndSavePin') ??
          KAntiUninstall;
    } on PlatformException catch (e) {
      log("خطأ في توليد PIN: ${e.message}");
      return KAntiUninstall;
    }
  }

  /// التحقق من PIN — لو صح يُلغى Device Admin ويرجع true
  static Future<bool> verifyPinAndRemoveAdmin(String pin) async {
    try {
      return await _adminChannel.invokeMethod(
            'verifyPinAndRemoveAdmin',
            {'pin': pin},
          ) ??
          false;
    } on PlatformException catch (e) {
      log("خطأ في التحقق من PIN: ${e.message}");
      return false;
    }
  }

  /// هل خاصية Anti-Uninstall مفعلة (Device Admin نشط + علامة Flutter)؟
  static Future<bool> isAntiUninstallActive() async {
    try {
      return await _adminChannel.invokeMethod('isAntiUninstallActive') ?? false;
    } on PlatformException catch (e) {
      log("فشل التحقق من Anti-Uninstall: ${e.message}");
      return false;
    }
  }

  /// حفظ حالة التفعيل من Flutter
  static Future<void> setAntiUninstallActive(bool active) async {
    try {
      await _adminChannel.invokeMethod(
        'setAntiUninstallActive',
        {'active': active},
      );
    } on PlatformException catch (e) {
      log("خطأ في حفظ حالة Anti-Uninstall: ${e.message}");
    }
  }
}
