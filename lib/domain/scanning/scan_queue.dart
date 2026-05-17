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
        await _processImage(path, isPriority: isPriority);
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

    if (kDebugScan) {
      final totalFrames = timestamps.length;
      final videoName = videoPath.split('/').last;
      debugPrint(
          '[ScanQueue] ▶️ بدء فحص: $videoName | إجمالي الفريمات: $totalFrames');
      for (int idx = 0; idx < timestamps.length; idx++) {
        final ms = timestamps[idx];
        final m = ms ~/ 60000;
        final s = (ms % 60000) ~/ 1000;
        debugPrint(
          '[ScanQueue]   📌 فريم ${idx + 1}/$totalFrames → ${m}:${s.toString().padLeft(2, '0')} (${ms ~/ 1000}ث)',
        );
      }
    }

    // ✅ FIX: لا temp files — كل frame تُعالَج من memory مباشرة
    bool isNsfw = false;
    int framesExtracted = 0;

    for (int i = 0; i < timestamps.length; i++) {
      if (_cancelled) break;

      // ✅ ميزة الأولوية القصوى: إذا ظهر ملف جديد (Priority) وأنا حالياً أفحص ملف عادي، توقف فوراً
      if (!isPriority && _priorityPaths.isNotEmpty) {
        // أعد الملف بعد كل الـ priority items في القائمة مباشرة
        // بحيث يُستكمل فحصه فوراً بعد انتهاء الملفات المستعجلة
        final insertPos = _queue.indexWhere((p) => !_priorityPaths.contains(p));
        if (insertPos == -1) {
          _queue.add(videoPath); // كل القائمة priority → ضيفه في الآخر
        } else {
          _queue.insert(insertPos, videoPath);
        }
        _pendingSet.add(videoPath); // أعده لمجموعة الانتظار
        // لا نسجل stat هنا — الملف لم يكتمل فحصه بعد
        return; // اخرج لترك المجال للملف الجديد
      }

      if (kDebugScan) {
        final ms = timestamps[i];
        final m = ms ~/ 60000;
        final s = (ms % 60000) ~/ 1000;
        debugPrint(
          '[ScanQueue] 🔍 جاري فحص فريم ${i + 1}/${timestamps.length} | الوقت: ${m}:${s.toString().padLeft(2, '0')} | ${videoPath.split('/').last}',
        );
      }

      final frameBytes = await _extractFrameBytes(videoPath, timestamps[i]);
      if (frameBytes == null) {
        if (kDebugScan)
          debugPrint('[ScanQueue] ⚠️ فريم ${i + 1} فشل في الاستخراج — تخطي');
        continue;
      }

      framesExtracted++;
      final scoredResult = await scorer.score(frameBytes);

      if (kDebugScan) {
        final ms = timestamps[i];
        final m = ms ~/ 60000;
        final s = (ms % 60000) ~/ 1000;
        final result = scoredResult.rawNsfw.isNsfw ? '❌ NSFW' : '✅ SFW';
        debugPrint(
          '[ScanQueue] $result فريم ${i + 1} | الوقت: ${m}:${s.toString().padLeft(2, '0')} | Score: ${scoredResult.rawNsfw.nsfw.toStringAsFixed(3)} | ${videoPath.split('/').last}',
        );
      }

      // ✅ منطق الحذف الفوري: إذا كان الفريم الحالي (سواء الأول أو الثاني أو غيره) إباحي، احذف واخرج
      // درجة NSFW > SFW تعني أن الموديل واثق من وجود محتوى غير لائق
      if (scoredResult.rawNsfw.isNsfw) {
        isNsfw = true;
        break;
      }
    }

    if (kDebugScan) {
      final videoName = videoPath.split('/').last;
      final verdict = isNsfw ? '🚫 محتوى غير لائق — سيتم الحذف' : '✅ آمن';
      debugPrint(
          '[ScanQueue] 🏁 انتهى فحص: $videoName | النتيجة: $verdict | فريمات فُحصت: $framesExtracted/${timestamps.length}');
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
  //
  // المشكلة: الـ MethodChannel (medi_guard/video_metadata) مسجّل في MainActivity
  // فقط على الـ main FlutterEngine، لكن _processVideo يتشغل في background isolate
  // (FlutterForegroundTask) اللي عنده binary messenger مختلف تماماً.
  // النتيجة: الـ call بيتجاهل → timeout → fallback 60 ثانية → frames غلطانة.
  //
  // الحل: binary search بـ VideoThumbnail نفسه اللي شغال في الـ isolate أصلاً.
  // المنطق: لو thumbnailData نجح عند timestamp معين → الفيديو وصل لهنا على الأقل.
  //         لو فشل (null) → الفيديو خلص قبله.
  // الدقة: ±5% من المدة الحقيقية — كافية لتوزيع الـ frames صح.
  // التكلفة: 4-5 thumbnail probes = ~200-500ms بدل timeout 5 ثواني.
  Future<VideoMetadata> _getVideoMetadata(String videoPath) async {
    // نبدأ بـ upper bound تدريجي: 2د → 5د → 15د → 30د → 60د → 120د → 180د
    const List<int> candidates = [
      2 * 60 * 1000,
      5 * 60 * 1000,
      15 * 60 * 1000,
      30 * 60 * 1000,
      60 * 60 * 1000,
      120 * 60 * 1000,
      180 * 60 * 1000,
    ];

    // الخطوة 1: ابحث عن أول candidate يفشل — ده upper bound للمدة
    int lowerMs = 0;
    int upperMs = candidates.last;

    for (final ms in candidates) {
      final probe = await _probeTimestamp(videoPath, ms);
      if (!probe) {
        upperMs = ms;
        break;
      }
      lowerMs = ms;
    }

    // لو حتى أول candidate فشل، الفيديو أقل من دقيقتين — استخدم 60 ث كافتراض
    if (lowerMs == 0 && upperMs == candidates.first) {
      return VideoMetadata(durationMs: 60000, width: 0, height: 0);
    }

    // الخطوة 2: binary search بين lowerMs و upperMs بدقة ±5%
    for (int step = 0; step < 4; step++) {
      final midMs = (lowerMs + upperMs) ~/ 2;
      if (midMs <= lowerMs) break;
      final probe = await _probeTimestamp(videoPath, midMs);
      if (probe) {
        lowerMs = midMs;
      } else {
        upperMs = midMs;
      }
    }

    // lowerMs = آخر timestamp نجح فيه → تقريب للمدة الحقيقية
    // نضيف 10% هامش أمان لنضمن إن lastMs صح
    final estimatedMs = (lowerMs * 1.10).round();

    if (kDebugScan) {
      final m = estimatedMs ~/ 60000;
      final s = (estimatedMs % 60000) ~/ 1000;
      debugPrint(
          '[ScanQueue] 📏 Duration estimated: $m:${s.toString().padLeft(2, '0')} ($estimatedMs ms) for ${videoPath.split('/').last}');
    }

    return VideoMetadata(durationMs: estimatedMs, width: 0, height: 0);
  }

  // probe: هل الفيديو وصل لهذا الـ timestamp؟
  // نجاح = thumbnailData رجعت bytes غير null
  Future<bool> _probeTimestamp(String videoPath, int timeMs) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        maxWidth: 64, // صغير جداً — بس عايزين نعرف هل نجح أو لا
        maxHeight: 64,
        quality: 10,
      ).timeout(const Duration(seconds: 4));
      return bytes != null && bytes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ─── توزيع الـ frames بمنطق ذكي ─────────────────────────────────────────────
  //
  //  توزيع على منطقتين:
  //    • النصف الأول (first → 50%): ثلث الـ frames الوسطى
  //    • النصف الثاني (50% → last): ثلثين الـ frames الوسطى
  //
  //  السبب: NSFW content ممكن يكون في أي مكان في الفيديو، مش بس في الآخر.
  //  التوزيع على كل الفيديو مع تركيز في النص والنهاية يضمن ما نفوتش حاجة.
  //
  //  عدد الـ frames الإجمالي:
  //    < 30 ث   → 1  (المنتصف فقط)
  //    30ث–1د   → 3  (أولى + وسط + أخيرة)
  //    1–5 د    → 5  (أولى + 3 وسطى + أخيرة)
  //    5–30 د   → 7  (أولى + 5 وسطى + أخيرة)
  //    30+ د    → 9  (أولى + 7 وسطى + أخيرة)
  List<int> _generateAdaptiveTimestamps(int durationMs) {
    if (durationMs <= 0) return [0];

    // فيديو قصير جداً → خد من المنتصف بس
    if (durationMs < 30000) return [durationMs ~/ 2];

    // Frame أولى دايماً عند 8 ث
    const int firstMs = 8000;

    // Frame أخيرة دايماً قبل النهاية بـ 15 ث
    final int lastMs =
        (durationMs - 15000).clamp(firstMs + 1000, durationMs - 1000);

    if (lastMs <= firstMs) return [durationMs ~/ 2];

    // ─── عدد الـ frames الوسطى ────────────────────────────────────────────
    final int middleCount;
    if (durationMs < 60000) {
      middleCount = 1; // < دقيقة  → 3 إجمالي
    } else if (durationMs < 300000) {
      middleCount = 3; // 1-5 د    → 5 إجمالي
    } else if (durationMs < 1800000) {
      middleCount = 5; // 5-30 د   → 7 إجمالي
    } else {
      middleCount = 7; // 30+ د    → 9 إجمالي
    }

    if (middleCount == 0) return [firstMs, lastMs];

    // ─── توزيع على النصف الأول والنصف الثاني ────────────────────────────
    final int midMs = ((firstMs + lastMs) / 2).round();

    // ثلث الـ frames في النصف الأول، ثلثين في النصف الثاني
    final int firstHalfCount = (middleCount / 3).round();
    final int secondHalfCount = middleCount - firstHalfCount;

    final List<int> firstHalf = List.generate(
      firstHalfCount,
      (i) => firstMs + ((midMs - firstMs) * (i + 1) ~/ (firstHalfCount + 1)),
    );

    final List<int> secondHalf = List.generate(
      secondHalfCount,
      (i) => midMs + ((lastMs - midMs) * (i + 1) ~/ (secondHalfCount + 1)),
    );

    return [firstMs, ...firstHalf, ...secondHalf, lastMs];
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
  Future<void> _processImage(String path, {bool isPriority = false}) async {
    if (_cancelled) return;

    // ✅ yield للأولوية: إذا ظهر ملف جديد (Priority) وأنا حالياً أفحص صورة عادية، أعدها وتوقف
    if (!isPriority && _priorityPaths.isNotEmpty) {
      final insertPos = _queue.indexWhere((p) => !_priorityPaths.contains(p));
      if (insertPos == -1) {
        _queue.add(path);
      } else {
        _queue.insert(insertPos, path);
      }
      _pendingSet.add(path);
      return;
    }

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
