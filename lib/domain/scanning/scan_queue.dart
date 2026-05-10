import 'dart:async';
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
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

const String _reset = '\x1B[0m';
const String _red = '\x1B[31m';
const String _green = '\x1B[32m';
const String _yellow = '\x1B[33m';
const String _blue = '\x1B[34m';
const String _cyan = '\x1B[36m';
const String _bold = '\x1B[1m';

// ✅ 8 فريمات بتوزيع ذكي حسب مدة الفيديو
const int _framesPerVideo = 8;

// ─── debug mode ──────────────────────────────────────────────
// في debug mode: يظهر اسم الملف + نتيجة كل فريم + القرار النهائي
// في release mode: لا شيء
const bool kDebugScan = kDebugMode;

const int _concurrentFiles = 3;

class ScanQueue {
  final EnsembleScorer scorer;
  final DecisionEngine engine;
  final DeleteManager deleteManager;
  final ScanNotificationService notifier;

  final Set<String> _pendingSet = {};
  final List<String> _queue = [];
  int _activeWorkers = 0;

  ScanQueue({
    required this.scorer,
    required this.engine,
    required this.deleteManager,
    required this.notifier,
  });

  int get pendingCount => _queue.length;
  bool get isProcessing => _activeWorkers > 0 || _queue.isNotEmpty;

  void add(String path) {
    if (!_pendingSet.contains(path)) {
      _pendingSet.add(path);
      _queue.add(path);
      _trySpawnWorker();
    }
  }

  void _trySpawnWorker() {
    if (_activeWorkers >= _concurrentFiles || _queue.isEmpty) return;

    _activeWorkers++;

    final path = _queue.removeAt(0);
    _pendingSet.remove(path);

    _processFile(path).whenComplete(() {
      _activeWorkers--;
      _trySpawnWorker();
    });

    _trySpawnWorker();
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
  Future<void> _processVideo(String videoPath) async {
    final fileName = videoPath.split('/').last;

    if (kDebugScan) {
      debugPrint('');
      debugPrint(
          '$_bold$_blue╔══════════════════════════════════════════════════╗$_reset');
      debugPrint(
          '$_bold$_blue║  🎥  VIDEO SCAN                                   ║$_reset');
      debugPrint('$_bold$_blue║  📄  $fileName$_reset');
      debugPrint(
          '$_bold$_blue╚══════════════════════════════════════════════════╝$_reset');
    } else {
      debugPrint('${_blue}🎥 Processing video: $fileName$_reset');
    }

    final file = File(videoPath);
    if (!await file.exists()) return;

    final hash = await _getPartialHash(file);

    final hashesBox = Hive.box('scanned_hashes');
    if (hashesBox.get(hash) != null) {
      debugPrint('⏭️ Already scanned (hash match): $fileName');
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final framePaths = <String>[];
    bool isNsfw = false;

    try {
      // ✅ توزيع ذكي: 8 فريمات بناءً على مدة الفيديو
      final timestamps = await _generateFrameTimestamps(videoPath);

      if (kDebugScan) {
        debugPrint(
            '$_cyan   📊 Frame plan: ${timestamps.length} frames$_reset');
      }

      for (int i = 0; i < timestamps.length; i++) {
        final timeMs = timestamps[i];
        final fp = await _extractFrame(videoPath, tempDir.path, timeMs);

        if (fp == null) {
          if (kDebugScan) {
            debugPrint(
                '$_yellow   ⚠️  Frame ${i + 1}@${timeMs}ms → extraction failed$_reset');
          }
          continue;
        }

        framePaths.add(fp);

        final scoredResult = await scorer.score(fp);
        final nsfw = scoredResult.rawNsfw.nsfw;
        final sfw = scoredResult.rawNsfw.sfw;
        final frameIsNsfw = nsfw > sfw;

        if (kDebugScan) {
          final label = _frameLabel(i, timestamps.length);
          final verdict = frameIsNsfw
              ? '${_red}🔴 REJECT$_reset'
              : '${_green}✅ SAFE  $_reset';
          debugPrint(
            '   Frame ${(i + 1).toString().padLeft(2)} [$label] @${timeMs}ms'
            ' │ NSFW=${nsfw.toStringAsFixed(3)}'
            ' SFW=${sfw.toStringAsFixed(3)}'
            ' Skin=${scoredResult.skinScore.toStringAsFixed(3)}'
            ' Face=${scoredResult.faceScore.toStringAsFixed(3)}'
            ' │ $verdict',
          );
        }

        // 🔥 early exit — فريم واحد NSFW يكفي
        if (frameIsNsfw) {
          isNsfw = true;
          break;
        }
      }

      if (framePaths.isEmpty) {
        debugPrint('⚠️ No frames extracted from: $fileName');
        await hashesBox.put(hash, 1);
        return;
      }

      // ─── Debug Summary ────────────────────────────────
      if (kDebugScan) {
        debugPrint('   ─────────────────────────────────────────────────────');
        debugPrint(
            '   📸 Scanned   : ${framePaths.length} / ${timestamps.length} frames');
        final verdictStr = isNsfw
            ? '${_red}🔴 NSFW → REJECT$_reset'
            : '${_green}✅ SAFE  → ACCEPT$_reset';
        debugPrint('   🏁 Verdict   : $verdictStr');
        debugPrint('   ─────────────────────────────────────────────────────');
        debugPrint('');
      } else {
        debugPrint(
          '📸 Scanned ${framePaths.length} frames → '
          '${isNsfw ? "NSFW🔴" : "SAFE✅"}',
        );
      }

      if (isNsfw) {
        debugPrint('${_red}🔥 VIDEO REJECTED → deleting$_reset');
        final deleted = await deleteManager.deleteImmediately(videoPath);
        if (deleted) await notifier.showDeletedNotification(videoPath);
      } else {
        debugPrint('${_green}✅ VIDEO SAFE: $fileName$_reset');
      }

      await hashesBox.put(hash, 1);
    } finally {
      for (final fp in framePaths) {
        try {
          File(fp).deleteSync();
        } catch (_) {}
      }
    }
  }

  // ──────────────────────────────────────────────────────────────
  // ✅ توزيع ذكي للفريمات الـ 8 حسب مدة الفيديو:
  //
  //   Frame 1 → بعد 10 ثواني من البداية     (تجنب الـ intro الأبيض)
  //   Frame 2 → 15% من المدة
  //   Frame 3 → 30% من المدة
  //   Frame 4 → 40% من المدة
  //   Frame 5 → 50% من المدة (المنتصف)
  //   Frame 6 → 60% من المدة
  //   Frame 7 → 75% من المدة
  //   Frame 8 → قبل النهاية بـ 15 ثانية     (قبل الـ outro)
  //
  //   لو الفيديو < 20 ثانية → توزيع بالتساوي تلقائياً
  // ──────────────────────────────────────────────────────────────
  Future<List<int>> _generateFrameTimestamps(String videoPath) async {
    // ✅ نحاول نجيب المدة من VideoPlayerController
    // لو فشل في الـ background isolate نستخدم fixed fallback timestamps
    int durationMs = 0;

    try {
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      durationMs = controller.value.duration.inMilliseconds;
      await controller.dispose();
    } catch (e) {
      debugPrint(
          '⚠️ Duration via VideoPlayer failed: $e → using fixed timestamps');
    }

    // ✅ لو مش عارفين المدة → timestamps ثابتة متنوعة
    // video_thumbnail بيرجع null تلقائياً لو الـ timestamp أكبر من المدة
    if (durationMs <= 0) {
      return [0, 5000, 10000, 20000, 30000, 60000, 120000, 180000];
    }

    // فيديو قصير جداً (< 20s) → توزيع بالتساوي
    if (durationMs < 20000) {
      final step = durationMs ~/ (_framesPerVideo + 1);
      return List.generate(
        _framesPerVideo,
        (i) => (step * (i + 1)).clamp(0, durationMs - 1),
      );
    }

    final ts = <int>[];

    // Frame 1: 10% من المدة لو < 100s، وإلا 10 ثواني ثابتة
    final frame1 = durationMs < 100000 ? (durationMs * 0.10).toInt() : 10000;
    ts.add(frame1.clamp(0, durationMs - 1));

    // Frames 2-7: نسب ثابتة من المدة
    for (final pct in [0.15, 0.30, 0.40, 0.50, 0.60, 0.75]) {
      ts.add((durationMs * pct).toInt().clamp(0, durationMs - 1));
    }

    // Frame 8: قبل النهاية (15s أو 10% لو الفيديو < 60s)
    final endOffset = durationMs < 60000 ? (durationMs * 0.10).toInt() : 15000;
    ts.add((durationMs - endOffset).clamp(0, durationMs - 1));

    return ts.toSet().toList()..sort();
  }

  // label للـ debug
  String _frameLabel(int index, int total) {
    if (index == 0) return 'START+10s';
    if (index == total - 1) return 'END-15s  ';
    const pcts = [
      '  15%    ',
      '  30%    ',
      '  40%    ',
      '  50%MID ',
      '  60%    ',
      '  75%    '
    ];
    final mid = index - 1;
    return mid < pcts.length ? pcts[mid] : '${index + 1}/$total     ';
  }

  Future<String?> _extractFrame(
    String videoPath,
    String tempDir,
    int timeMs,
  ) async {
    try {
      return await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        quality: 75,
      );
    } catch (e) {
      debugPrint('⚠️ Frame extraction failed (timeMs=$timeMs): $e');
      return null;
    }
  }

  // ─── IMAGE ────────────────────────────────────────────
  Future<void> _processImage(String path) async {
    final file = File(path);
    if (!await file.exists()) return;

    final stat = await file.stat();
    if (stat.size < 10240) return;

    final hash = await _getPartialHash(file);

    final hashesBox = Hive.box('scanned_hashes');
    if (hashesBox.get(hash) != null) {
      debugPrint('⏭️ Already scanned: ${path.split('/').last}');
      return;
    }

    final fileName = path.split('/').last;

    if (kDebugScan) {
      debugPrint('');
      debugPrint(
          '$_bold$_cyan╔══════════════════════════════════════════════════╗$_reset');
      debugPrint(
          '$_bold$_cyan║  🖼️  IMAGE SCAN                                   ║$_reset');
      debugPrint('$_bold$_cyan║  📄  $fileName$_reset');
      debugPrint(
          '$_bold$_cyan╚══════════════════════════════════════════════════╝$_reset');
    }

    final scoredResult = await scorer.score(path);
    final decision =
        engine.decide(scoredResult, scoredResult.rawNsfw, filePath: path);

    if (kDebugScan) {
      debugPrint(
          '   NSFW Score  : ${scoredResult.rawNsfw.nsfw.toStringAsFixed(3)}');
      debugPrint(
          '   SFW Score   : ${scoredResult.rawNsfw.sfw.toStringAsFixed(3)}');
      debugPrint(
          '   Skin Ratio  : ${scoredResult.skinScore.toStringAsFixed(3)}');
      debugPrint(
          '   Face Score  : ${scoredResult.faceScore.toStringAsFixed(3)}');
      debugPrint(
          '   Weighted    : ${scoredResult.weighted.toStringAsFixed(3)}');
      debugPrint('   ─────────────────────────────────────────────────────');

      final verdictStr = switch (decision.result) {
        DecisionResult.reject =>
          '${_red}🔴 REJECT — ${decision.reason} (${(decision.confidence * 100).toStringAsFixed(1)}%)$_reset',
        DecisionResult.accept =>
          '${_green}✅ ACCEPT (conf=${(decision.confidence * 100).toStringAsFixed(1)}%)$_reset',
        DecisionResult.review =>
          '${_yellow}🟡 REVIEW (conf=${(decision.confidence * 100).toStringAsFixed(1)}%)$_reset',
      };
      debugPrint('   🏁 Decision  : $verdictStr');
      debugPrint('');
    }

    if (decision.result == DecisionResult.reject) {
      final deleted = await deleteManager.deleteImmediately(path);
      if (deleted) await notifier.showDeletedNotification(path);
    }

    await hashesBox.put(hash, 1);

    // ✅ حفظ الـ anchor بعد ما الصورة اتسكانت فعلاً
  }

  // ─── HASH ────────────────────────────────────────────
  Future<String> _getPartialHash(File file) async {
    const chunkSize = 64 * 1024;

    final size = await file.length();

    if (size <= chunkSize * 2) {
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    }

    final raf = await file.open();

    try {
      final head = await raf.read(chunkSize);

      await raf.setPosition(size - chunkSize);
      final tail = await raf.read(chunkSize);

      final combined = [...head, ...tail];

      return sha256.convert(combined).toString();
    } finally {
      await raf.close();
    }
  }
}
