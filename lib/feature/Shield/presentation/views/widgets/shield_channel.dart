import 'dart:developer';

import 'package:flutter/services.dart';

class MaadhShieldManager {
  static const platform = MethodChannel('com.maadh.shield/anti_uninstall');

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

  static Future<void> requestAccessibility() async {
    try {
      await platform.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      log("خطأ في فتح الإعدادات: ${e.message}");
    }
  }

  // التحقق من تفعيل الحارس الذكي
  static Future<bool> isAccessibilityEnabled() async {
    try {
      return await platform.invokeMethod('isAccessibilityEnabled') ?? false;
    } on PlatformException catch (e) {
      log("فشل التحقق من الحارس: ${e.message}");
      return false;
    }
  }

  // تفعيل/إيقاف قفل الحماية (Anti-Uninstall)
  static Future<void> toggleAntiUninstall(bool isActive) async {
    try {
      if (isActive) {
        await platform.invokeMethod('enableAntiUninstall');
      } else {
        await platform.invokeMethod('disableAntiUninstall');
      }
    } on PlatformException catch (e) {
      log("خطأ في قفل الحماية: ${e.message}");
    }
  }

  // التحقق من حالة قفل الحماية
  static Future<bool> isAntiUninstallEnabled() async {
    try {
      return await platform.invokeMethod('isAntiUninstallEnabled') ?? false;
    } on PlatformException catch (e) {
      log("فشل التحقق من قفل الحماية: ${e.message}");
      return false;
    }
  }
}
