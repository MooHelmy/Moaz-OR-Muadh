import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeleteManager {
  // MethodChannel للـ native delete — أقوى من Dart في بعض الأجهزة
  static const _channel = MethodChannel('com.maadh.shield/delete');

  Future<bool> deleteImmediately(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('⚠️ File not found at deletion time: $filePath');
        return false;
      }

      // سجّل في Firebase قبل الحذف
      await _logDeletion(filePath);

      // ✅ حاول الحذف الـ native أولاً (أقوى وأضمن على Android 11+)
      bool deleted = false;
      try {
        deleted = await _channel.invokeMethod<bool>('deleteFile', {
              'path': filePath,
            }) ??
            false;
      } catch (_) {
        // لو الـ channel مش موجود، نرجع للـ Dart
        deleted = false;
      }

      // ✅ Fallback: حذف عبر Dart
      if (!deleted) {
        await file.delete();
        deleted = true;
        debugPrint('🗑️ Dart delete succeeded: $filePath');
      } else {
        debugPrint('🔥 Native delete succeeded: $filePath');
      }

      return deleted;
    } catch (e) {
      debugPrint('❌ CRITICAL: Delete failed for $filePath → $e');
      debugPrint('💡 تأكد من صلاحية MANAGE_EXTERNAL_STORAGE');
      return false;
    }
  }

  Future<void> _logDeletion(String path) async {
    try {
      await FirebaseFirestore.instance.collection('deleted_files').add({
        'path': path,
        'fileName': path.split('/').last,
        'deletedAt': DateTime.now().toIso8601String(),
        'source': _detectSource(path),
      });
    } catch (_) {}
  }

  String _detectSource(String path) {
    if (path.contains('whatsapp') || path.contains('WhatsApp'))
      return 'WhatsApp';
    if (path.contains('telegram') || path.contains('Telegram'))
      return 'Telegram';
    if (path.contains('Download')) return 'Downloads';
    if (path.contains('DCIM')) return 'Camera';
    if (path.contains('Instagram')) return 'Instagram';
    if (path.contains('TikTok')) return 'TikTok';
    if (path.contains('Facebook')) return 'Facebook';
    return 'Unknown';
  }
}
