import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/domain/deletion/delete_manager.dart';
import 'package:medi_guard/domain/engines/decision_engine.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// ─── VideoMetadata ────────────────────────────────────────────────────────────
// نموذج بيانات بسيط يُرجع metadata الفيديو من native layer دون decode
class VideoMetadata {
  final int durationMs;
  final int width;
  final int height;

  const VideoMetadata({
    required this.durationMs,
    required this.width,
    required this.height,
  });
}

const String reset = '\x1B[0m';
const String red = '\x1B[31m';
// ignore: unused_element
const String yellow = '\x1B[33m';
const String blue = '\x1B[34m';
const String bold = '\x1B[1m';

const bool kDebugScan = kDebugMode;

const MethodChannel _mediaScannerChannel =
    MethodChannel('medi_guard/media_scanner');

class ScanQueue {
  final EnsembleScorer scorer;
  final DecisionEngine engine;
  final DeleteManager deleteManager;
  final ScanNotificationService notifier;

  // تم تثبيت عدد العمليات المتوازية بـ 2 لضمان الاستقرار بعد حذف خدمة فحص الجهاز
  final int _maxWorkers = 2;

  final Set<String> _pendingSet = {};
  final Set<String> _priorityPaths = {}; // تتبع الملفات ذات الأولوية
  final List<String> _queue = [];
  int _activeWorkers = 0;

  bool _cancelled = false;
  bool _isPaused = false;
  final List<Completer<void>> _activeCompleters = [];

  ScanQueue({
    required this.scorer,
    required this.engine,
    required this.deleteManager,
    required this.notifier,
  });

  /// الـ concurrency الحالي — للعرض في الـ UI
  int get currentConcurrency => _maxWorkers;

  int get pendingCount => _queue.length;
  bool get isProcessing => _activeWorkers > 0 || _queue.isNotEmpty;

  void pauseForBattery() {
    _isPaused = true;
  }

  void resumeFromBattery() {
    _isPaused = false;
    _trySpawnWorker();
  }

  void pauseHeavyTasks() {
    _isPaused = true;
  }

  void resumeHeavyTasks() {
    _isPaused = false;
    _trySpawnWorker();
  }

  void add(String path, {bool priority = false}) {
    if (_cancelled) return;
    if (!_pendingSet.contains(path)) {
      _pendingSet.add(path);
      if (priority) _priorityPaths.add(path);
      if (priority) {
        _queue.insert(0, path);
      } else {
        _queue.add(path);
      }
      _trySpawnWorker();
    }
  }

  void _trySpawnWorker() {
    if (_cancelled || _isPaused) return;
    // ✅ FIX: _maxWorkers بدل الثابت _concurrentFiles
    if (_activeWorkers >= _maxWorkers || _queue.isEmpty) return;

    _activeWorkers++;
    final path = _queue.removeAt(0);
    _pendingSet.remove(path);
    final bool isPriority = _priorityPaths.contains(path);

    final completer = Completer<void>();
    _activeCompleters.add(completer);

    Future.delayed(const Duration(milliseconds: 50)).then((_) {
      return _processFile(path, isPriority: isPriority);
    }).then((_) {
      completer.complete();
    }).catchError((e) {
      completer.complete();
    }).whenComplete(() {
      _activeCompleters.remove(completer);
      _priorityPaths.remove(path);
      _activeWorkers--;
      _trySpawnWorker();
    });
  }

  Future<void> dispose() async {
    _cancelled = true;
    _queue.clear();
    _pendingSet.clear();

    if (_activeCompleters.isNotEmpty) {
      await Future.wait(_activeCompleters.map((c) => c.future))
          .timeout(const Duration(seconds: 5), onTimeout: () => []);
    }

    await scorer.nsfwService.dispose();
  }

  Future<void> _processFile(String path, {bool isPriority = false}) async {
    if (_cancelled) return;
    try {
      if (ScanTargets.isVideo(path)) {
        await _processVideo(path, isPriority: isPriority);
      } else if (ScanTargets.isImage(path)) {
        await _processImage(path);
      }
    } catch (e) {
      // ScanQueue Error
    }
  }

  // ─── VIDEO ──────────────────────────────────────────────
  Future<void> _processVideo(String videoPath,
      {bool isPriority = false}) async {
    if (_cancelled) return;

    final file = File(videoPath);
    if (!await file.exists()) return;

    final hash = await _getPartialHash(file);
    final hashesBox = Hive.box('scanned_hashes');

    if (hashesBox.get(hash) != null) return;

    final metadata = await _getVideoMetadata(videoPath);
    final timestamps = _generateAdaptiveTimestamps(metadata.durationMs);

    // ✅ FIX: لا temp files — كل frame تُعالَج من memory مباشرة
    bool isNsfw = false;
    int framesExtracted = 0;

    for (int i = 0; i < timestamps.length; i++) {
      if (_cancelled) break;

      // ✅ ميزة الأولوية القصوى: إذا ظهر ملف جديد (Priority) وأنا حالياً أفحص ملف عادي، توقف فوراً
      if (!isPriority && _priorityPaths.isNotEmpty) {
        // أعد الملف الحالي إلى "رأس" الطابور ليتم استكماله فور انتهاء الملف المستعجل
        _queue.insert(0, videoPath);
        _pendingSet.add(videoPath); // أعده لمجموعة الانتظار
        return; // اخرج لترك المجال للملف الجديد
      }

      final frameBytes = await _extractFrameBytes(videoPath, timestamps[i]);
      if (frameBytes == null) continue;

      framesExtracted++;
      final scoredResult = await scorer.score(frameBytes);

      // ✅ منطق الحذف الفوري: إذا كان الفريم الحالي (سواء الأول أو الثاني أو غيره) إباحي، احذف واخرج
      // درجة NSFW > SFW تعني أن الموديل واثق من وجود محتوى غير لائق
      if (scoredResult.rawNsfw.isNsfw) {
        isNsfw = true;
        if (kDebugScan) {
          debugPrint(
              '[ScanQueue] Video frame $i is NSFW. Deleting immediately: $videoPath');
        }
        break;
      }
    }

    // ✅ FIX #6: سجّل stats حتى لو ما استخرجناش أي frame
    await _recordScanStat(videoPath,
        isNsfw: framesExtracted == 0 ? false : isNsfw, isVideo: true);

    if (isNsfw && !_cancelled) {
      final deleted = await deleteManager.deleteImmediately(videoPath);
      if (deleted) {
        await Future.wait([
          _logDeletion(videoPath),
          _notifyMediaScanner(videoPath),
        ]);
        await notifier.showDeletedNotification(videoPath);
      }
    }

    await hashesBox.put(hash, 1);
    await _periodicCompact();
  }

  // ─── VIDEO METADATA ──────────────────────────────────────────────────────────
  // ✅ FIX: استبدال thumbnail probing بـ MediaMetadataRetriever
  //
  // الكود القديم كان يعمل حتى 6 probes، كل probe = video decode + JPEG encode
  // الكود الجديد: native metadata فقط — لا يوجد frame decode على الإطلاق
  // النتيجة: من ~1–5 ثوانٍ إلى <50ms على أي جهاز
  static const MethodChannel _videoMetaChannel =
      MethodChannel('medi_guard/video_metadata');

  Future<VideoMetadata> _getVideoMetadata(String videoPath) async {
    try {
      final result = await _videoMetaChannel.invokeMapMethod<String, dynamic>(
          'getVideoMetadata',
          {'path': videoPath}).timeout(const Duration(seconds: 5));

      if (result != null) {
        return VideoMetadata(
          durationMs: (result['durationMs'] as num?)?.toInt() ?? 60000,
          width: (result['width'] as num?)?.toInt() ?? 0,
          height: (result['height'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    return VideoMetadata(durationMs: 60000, width: 0, height: 0);
  }

  // ✅ FIX: توزيع الـ frames حسب مدة الفيديو — مش عدد ثابت
  //
  // المنطق:
  //   فيديو 10 ثواني  → 3 frames (مش محتاج أكثر)
  //   فيديو دقيقة     → 5 frames
  //   فيديو 10 دقايق  → 8 frames
  //   فيديو ساعة+     → 12 frame (max)
  //
  // كمان بيتخطى أول 5% وآخر 5% من الفيديو عشان يتجنب:
  //   - الـ black screen في البداية
  //   - الـ credits في النهاية
  // ignore: unused_element_parameter
  List<int> _generateAdaptiveTimestamps(int durationMs, {int? workerCount}) {
    if (durationMs <= 0) return [0];

    // ─── عدد الـ frames حسب المدة ───────────────────────────────────────────
    final int frameCount;
    if (durationMs < 15000) {
      // أقل من 15 ثانية → 3 frames كافية
      frameCount = 3;
    } else if (durationMs < 60000) {
      // 15 ثانية → دقيقة → 5 frames
      frameCount = 5;
    } else if (durationMs < 300000) {
      // 1 → 5 دقايق → 8 frames
      frameCount = 8;
    } else if (durationMs < 1800000) {
      // 5 → 30 دقيقة → 10 frames
      frameCount = 10;
    } else {
      // أكثر من 30 دقيقة → 12 frames (max)
      frameCount = 12;
    }

    // ─── نتخطى أول 5% وآخر 5% ────────────────────────────────────────────────
    final int startMs = (durationMs * 0.05).round().clamp(2000, 10000);
    final int endMs = (durationMs * 0.95).round();
    final int rangeMs = endMs - startMs;

    if (rangeMs <= 0) return [durationMs ~/ 2];

    // ─── توزيع uniform بين start و end ───────────────────────────────────────
    if (frameCount == 1) return [startMs + rangeMs ~/ 2];

    return List.generate(
      frameCount,
      (i) => startMs + (rangeMs * i ~/ (frameCount - 1)),
    );
  }

  // ✅ FIX: thumbnailData() بدل thumbnailFile() — zero disk IO
  //
  // القديم: decode → JPEG encode → write temp file → re-open → read → process
  // الجديد: decode → JPEG encode → Uint8List في memory → process مباشرة
  // النتيجة: نوفر write + open + read لكل frame = أسرع بشكل ملحوظ
  Future<Uint8List?> _extractFrameBytes(String videoPath, int timeMs) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        // تم تغيير الحجم لـ 384 ليتطابق مع ما يتوقعه الموديل في nsfw_service
        // هذا يحل خطأ ORT_RUNTIME_EXCEPTION (axis == 1 || axis == largest)
        maxWidth: 384,
        maxHeight: 384,
        quality: 75,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── IMAGE ────────────────────────────────────────────
  Future<void> _processImage(String path) async {
    if (_cancelled) return;

    final file = File(path);
    if (!await file.exists()) return;

    final stat = await file.stat();
    if (stat.size < 5120) return;
    if (stat.size > 50 * 1024 * 1024) return;

    final hash = await _getPartialHash(file);
    final hashesBox = Hive.box('scanned_hashes');

    if (hashesBox.get(hash) != null) return;

    // ✅ FIX: نقرأ الـ bytes مرة واحدة ونمررها للـ scorer
    // بدل ما كل service تفتح الملف من جديد (قبل كانت 3 disk reads لكل صورة)
    final imageBytes = await file.readAsBytes();
    final scoredResult = await scorer.score(imageBytes);
    final decision =
        engine.decide(scoredResult, scoredResult.rawNsfw, filePath: path);

    await _recordScanStat(path,
        isNsfw: decision.result == DecisionResult.reject, isVideo: false);

    if (decision.result == DecisionResult.reject && !_cancelled) {
      final deleted = await deleteManager.deleteImmediately(path);
      if (deleted) {
        await Future.wait([
          _logDeletion(path),
          _notifyMediaScanner(path),
        ]);
        await notifier.showDeletedNotification(path);
      }
    }

    await hashesBox.put(hash, 1);
    await _periodicCompact();
  }

  Future<void> _recordScanStat(String filePath,
      {required bool isNsfw, required bool isVideo}) async {
    try {
      final statsBox = Hive.box('scan_stats');

      final folder = _detectFolder(filePath);
      final key = 'folder_$folder';

      final existing = statsBox.get(key) as Map? ?? {};
      final Map<String, dynamic> stats = Map<String, dynamic>.from(existing);

      stats['total'] = (stats['total'] as int? ?? 0) + 1;
      stats['folder'] = folder;
      if (isVideo) {
        stats['videos'] = (stats['videos'] as int? ?? 0) + 1;
      } else {
        stats['images'] = (stats['images'] as int? ?? 0) + 1;
      }
      if (isNsfw) {
        stats['blocked'] = (stats['blocked'] as int? ?? 0) + 1;
      } else {
        stats['safe'] = (stats['safe'] as int? ?? 0) + 1;
      }
      stats['lastScan'] = DateTime.now().millisecondsSinceEpoch;

      await statsBox.put(key, stats);

      final totalKey = 'total_stats';
      final totalExisting = statsBox.get(totalKey) as Map? ?? {};
      final Map<String, dynamic> totalStats =
          Map<String, dynamic>.from(totalExisting);
      totalStats['scanned'] = (totalStats['scanned'] as int? ?? 0) + 1;
      // ignore: curly_braces_in_flow_control_structures
      if (isNsfw)
        totalStats['blocked'] = (totalStats['blocked'] as int? ?? 0) + 1;
      await statsBox.put(totalKey, totalStats);
    } catch (e) {
      // Stats recording failed
    }
  }

  Future<void> _logDeletion(String path) async {
    try {
      final box = Hive.box('deleted_log');

      // ✅ FIX: نحتفظ بآخر 50 فقط — بعد كده نحذف الأقدم
      // الـ deleted_log مش محتاجه يكبر للأبد — 50 كافية للعرض في الـ UI
      if (box.length >= 50) {
        final oldestKey = box.keys.first;
        await box.delete(oldestKey);
      }

      await box.add({
        'fileName': path.split('/').last,
        'source': _detectFolder(path),
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
        'path': path,
      });
    } catch (_) {}
  }

  Future<void> _notifyMediaScanner(String path) async {
    try {
      await _mediaScannerChannel.invokeMethod('scanFile', {'path': path});
    } catch (e) {
      // Media Scanner Notification failed
    }
  }

  String _detectFolder(String path) {
    if (path.contains('whatsapp') || path.contains('WhatsApp')) return 'واتساب';
    if (path.contains('telegram') || path.contains('Telegram'))
      return 'تيليجرام';
    if (path.contains('Download')) return 'التنزيلات';
    if (path.contains('DCIM')) return 'الكاميرا';
    if (path.contains('Instagram')) return 'إنستجرام';
    if (path.contains('TikTok')) return 'تيك توك';
    if (path.contains('Facebook')) return 'فيسبوك';
    if (path.contains('Snapchat')) return 'سناب شات';
    if (path.contains('Pictures')) return 'الصور';
    if (path.contains('Movies') || path.contains('Videos')) return 'الفيديوهات';
    return 'أخرى';
  }

  // ─── HASH ────────────────────────────────────────────
  // ✅ FIX: نستخدم أول 12 حرف من SHA-256 بدل الـ 64 كاملة
  //
  // 12 hex chars = 48 bits entropy = احتمال collision 1 في 281 تريليون
  // كافي تماماً لملفات المستخدم (أقل من مليون ملف على أي جهاز)
  // النتيجة: كل entry = ~32 bytes بدل ~100 bytes = توفير 68% من المساحة
  static int _scansSinceCompact = 0;
  static const int _compactEvery = 150;

  Future<String> _getPartialHash(File file) async {
    const chunkSize = 64 * 1024;
    final size = await file.length();

    final List<int> bytes;
    if (size <= chunkSize * 2) {
      bytes = await file.readAsBytes();
    } else {
      final raf = await file.open();
      try {
        final head = await raf.read(chunkSize);
        await raf.setPosition(size - chunkSize);
        final tail = await raf.read(chunkSize);
        bytes = [...head, ...tail];
      } finally {
        await raf.close();
      }
    }

    // ✅ أول 12 حرف فقط — 48-bit collision space
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  // ✅ FIX: compact أثناء الـ scan بدل الانتظار للـ startup التالي
  Future<void> _periodicCompact() async {
    _scansSinceCompact++;
    if (_scansSinceCompact < _compactEvery) return;
    _scansSinceCompact = 0;

    try {
      final hashesBox = Hive.box('scanned_hashes');
      // الـ compact سيتم تنفيذه الآن بناءً على العداد _scansSinceCompact
      await hashesBox.compact();
    } catch (_) {}
  }
}
