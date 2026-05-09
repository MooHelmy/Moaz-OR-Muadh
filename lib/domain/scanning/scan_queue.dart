import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/domain/deletion/delete_manager.dart';
import 'package:medi_guard/domain/engines/decision_engine.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

const String _reset = '\x1B[0m';
const String _red = '\x1B[31m';
const String _green = '\x1B[32m';
const String _yellow = '\x1B[33m';
const String _blue = '\x1B[34m';

// ✅ عدد الـ frames المطلوب فحصها من كل فيديو
const int _videoFrameCount = 8;

class ScanQueue {
  final EnsembleScorer scorer;
  final DecisionEngine engine;
  final DeleteManager deleteManager;
  final ScanNotificationService notifier;

  final List<String> _queue = [];
  bool _isProcessing = false;

  ScanQueue({
    required this.scorer,
    required this.engine,
    required this.deleteManager,
    required this.notifier,
  });

  int get pendingCount => _queue.length;
  bool get isProcessing => _isProcessing;

  void add(String path) {
    if (!_queue.contains(path)) {
      _queue.add(path);
      _processNext();
    }
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;
    final path = _queue.removeAt(0);
    await _processFile(path);
    _isProcessing = false;
    _processNext();
  }

  Future<void> dispose() async {
    _queue.clear();
    await scorer.nsfwService.dispose();
  }

  Future<void> _processFile(String path) async {
    try {
      if (ScanTargets.isVideo(path)) {
        await _processVideo(path);
      } else if (ScanTargets.isImage(path)) {
        await _processImage(path);
      }
    } catch (e) {
      debugPrint('❌ ScanQueue Error for $path: $e');
    }
  }

  // ─── VIDEO ──────────────────────────────────────────────
  // ✅ بيستخرج _videoFrameCount frames من الفيديو ويفحصهم
  // لو أي frame REJECT → يحذف الفيديو فوراً
  Future<void> _processVideo(String videoPath) async {
    debugPrint(
        '$_blue🎥 Processing video: ${videoPath.split('/').last}$_reset');

    final file = File(videoPath);
    if (!await file.exists()) return;

    // ✅ check hash أولاً عشان ما نفحصش نفس الفيديو مرتين
    final hash = await _getFileHash(file);
    final hashesBox = Hive.box('scanned_hashes');
    if (hashesBox.values.contains(hash)) {
      debugPrint(
          '⏭️ Already scanned (hash match): ${videoPath.split('/').last}');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final framePaths = <String>[];
    bool isNsfw = false;

    try {
      // استخراج الـ frames بالتوازي عشان يكون أسرع
      final futures = <Future<String?>>[];
      for (int i = 0; i < _videoFrameCount; i++) {
        // نوزع الـ frames على طول الفيديو
        // timeMs = null → بيختار تلقائياً، لكن بنستخدم i * offset
        futures.add(_extractFrame(videoPath, tempDir.path, i));
      }

      final results = await Future.wait(futures);
      for (final fp in results) {
        if (fp != null) framePaths.add(fp);
      }

      if (framePaths.isEmpty) {
        debugPrint('⚠️ No frames extracted from: $videoPath');
        await hashesBox.add(hash);
        return;
      }

      debugPrint('📸 Extracted ${framePaths.length} frames from video');

      // ✅ القاعدة: لو NSFW > SFW في أي frame → حذف فوري
      // مش بنستخدم threshold ثابت — بنقارن الاحتمالين مباشرة
      for (int i = 0; i < framePaths.length; i++) {
        final framePath = framePaths[i];
        final scoredResult = await scorer.score(framePath);

        final nsfw = scoredResult.rawNsfw.nsfw;
        final sfw = scoredResult.rawNsfw.sfw;
        // ✅ الشرط الوحيد: هل الموديل شايفه NSFW أكتر من SFW؟
        final frameIsNsfw = nsfw > sfw;

        debugPrint('   Frame $i → NSFW=${nsfw.toStringAsFixed(3)}'
            ' SFW=${sfw.toStringAsFixed(3)}'
            ' → ${frameIsNsfw ? "REJECT🔴" : "SAFE✅"}');

        if (frameIsNsfw) {
          isNsfw = true;
          break; // frame واحد يكفي
        }
      }

      // قرار نهائي على الفيديو
      if (isNsfw) {
        debugPrint('$_red🔥 VIDEO REJECTED → deleting: $videoPath$_reset');
        final deleted = await deleteManager.deleteImmediately(videoPath);
        if (deleted) await notifier.showDeletedNotification(videoPath);
      } else {
        debugPrint('$_green✅ VIDEO SAFE: ${videoPath.split('/').last}$_reset');
      }

      await hashesBox.add(hash);
    } finally {
      // ✅ امسح الـ frames المؤقتة دايماً
      for (final fp in framePaths) {
        try {
          File(fp).deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<String?> _extractFrame(
      String videoPath, String tempDir, int index) async {
    try {
      // نوزع الـ timestamps على طول الفيديو: 10%, 20%, ... 90%
      // video_thumbnail بيدعم timeMs بس مش بيعرف duration → نستخدم position أرقام ثابتة
      // نستخدم null لأول frame و positions مختلفة للباقي
      final timeMs = index == 0 ? 0 : (index * 5000); // كل 5 ثواني

      final path = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        quality: 75,
      );
      return path;
    } catch (e) {
      debugPrint('⚠️ Frame extraction failed (index=$index): $e');
      return null;
    }
  }

  // ─── IMAGE ──────────────────────────────────────────────
  Future<void> _processImage(String path) async {
    final file = File(path);
    if (!await file.exists()) return;

    final stat = await file.stat();
    if (stat.size < 10240) return; // أصغر من 10KB → تجاهل

    // ✅ تحقق من الـ Hash
    final hash = await _getFileHash(file);
    final hashesBox = Hive.box('scanned_hashes');
    if (hashesBox.values.contains(hash)) {
      debugPrint('⏭️ Already scanned: ${path.split('/').last}');
      return;
    }

    final fileName = path.split('/').last;
    debugPrint('$_reset-----------------------------------------------');
    debugPrint('🔍 Scanning: $_blue$fileName$_reset');

    final scoredResult = await scorer.score(path);
    final decision = engine.decide(scoredResult, scoredResult.rawNsfw);

    // ✅ احفظ القرار في Hive
    final decisionsBox = Hive.box('decisions');

    // ✅ حل مشكلة المساحة: خزّن بيانات مبسطة بس
    // مش بنخزن الـ path الطويل كـ key، بنخزن الـ hash بس
    await decisionsBox.put(hash.substring(0, 16), {
      's': decision.result.name[0], // 'a', 'r', 'v' — حرف واحد بدل كلمة
      't': DateTime.now().millisecondsSinceEpoch, // int بدل string
      'w': (scoredResult.weighted * 1000).round(), // int بدل double
    });

    String resultColor;
    switch (decision.result) {
      case DecisionResult.accept:
        resultColor = _green;
        break;
      case DecisionResult.review:
        resultColor = _yellow;
        break;
      case DecisionResult.reject:
        resultColor = _red;
        break;
    }

    debugPrint('   ↳ 🔞 NSFW:  ${scoredResult.rawNsfw}');
    debugPrint('   ↳ 👤 Skin:  ${scoredResult.skinScore.toStringAsFixed(3)}');
    debugPrint('   ↳ 🎭 Face:  ${scoredResult.faceScore.toStringAsFixed(3)}');
    debugPrint('   ↳ 📈 TOTAL: ${scoredResult.weighted.toStringAsFixed(3)}');
    debugPrint(
        '   ↳ ⚖️ RESULT: $resultColor${decision.result.name.toUpperCase()} (${decision.reason})$_reset');
    debugPrint('$_reset-----------------------------------------------');

    if (decision.result == DecisionResult.reject) {
      final deleted = await deleteManager.deleteImmediately(path);
      if (deleted) await notifier.showDeletedNotification(path);
    }

    await hashesBox.add(hash);

    // ✅ تنظيف دوري لـ Hive: لو الـ hashesBox وصل 5000 مدخلة → امسح القديم
    _cleanupHiveIfNeeded(hashesBox);
  }

  // ─── Hive Cleanup ───────────────────────────────────────
  // ✅ حل مشكلة المساحة: امسح الـ hashes القديمة لو كتر عددها
  void _cleanupHiveIfNeeded(Box hashesBox) {
    const maxEntries = 5000;
    if (hashesBox.length > maxEntries) {
      final keysToDelete =
          hashesBox.keys.take(hashesBox.length - maxEntries).toList();
      hashesBox.deleteAll(keysToDelete);
      // compact بعد الحذف عشان المساحة تترجع فعلاً
      hashesBox.compact();
      debugPrint('🧹 Hive cleanup: deleted ${keysToDelete.length} old hashes');
    }
  }

  Future<String> _getFileHash(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }
}
