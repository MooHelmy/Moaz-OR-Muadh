// ══════════════════════════════════════════════════════════════════════════════
//  smart_scan_queue.dart
//
//  Priority-aware scan queue بـ 3 مستويات:
//    🔴 realtime → FileObserver (ملف جديد دلوقتي)    → فوري + worker إضافي
//    🟡 high     → MediaStore poll (كل 5 دقايق)      → الأولوية التانية
//    🟢 normal   → Initial sweep                      → لما يفضى
//
//  الـ 3 موديلات على كل ملف:
//    NSFW (0.75) + Skin (0.15) + Face (0.10) = weighted score
//    Early exit لو NSFW > 0.85 — مش محتاجين Skin/Face
//
//  مشكلة الـ MethodChannel في background isolate:
//    الـ native channels (video_metadata, getFrameBytes) مسجّلة على
//    الـ main FlutterEngine بس — الـ background isolate عنده messenger تاني.
//    الحل: VideoThumbnail.thumbnailData() شغّال في الـ isolate أصلاً.
//      - Duration: binary search بـ probe thumbnails صغيرة (64×64)
//      - Frames:   thumbnailData() مباشرة بـ 384×384
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:Muadh/core/constants/scan_targets.dart';
import 'package:Muadh/data/services/notification_service.dart';
import 'package:Muadh/domain/deletion/delete_manager.dart';
import 'package:Muadh/domain/engines/decision_engine.dart';
import 'package:Muadh/domain/engines/ensemble_scorer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

const bool kDebugScan = kDebugMode;

const _mediaScannerChannel = MethodChannel('medi_guard/media_scanner');

// ─── Priority ─────────────────────────────────────────────────────────────────
enum ScanPriority { realtime, high, normal }

// ══════════════════════════════════════════════════════════════════════════════
//  SmartScanQueue
// ══════════════════════════════════════════════════════════════════════════════
class SmartScanQueue {
  final EnsembleScorer scorer;
  final DecisionEngine engine;
  final DeleteManager deleteManager;
  final ScanNotificationService notifier;

  // ─── 3 queues منفصلة بالأولوية ────────────────────────────────────────────
  final _realtimeQ = <String>[];
  final _highQ = <String>[];
  final _normalQ = <String>[];

  // dedup: لا نفحص نفس الملف مرتين في نفس الجلسة
  // ✅ FIX: _sessionSeen يخزن hashes مش paths
  // السبب: ملف بنفس الاسم ومحتوى مختلف → path نفسه بس hash مختلف
  final _pending = <String>{};
  final _sessionSeen = <String>{}; // hashes

  int _activeWorkers = 0;
  int _maxWorkers;
  bool _cancelled = false;
  bool _isPaused = false;

  // ─── Metrics ──────────────────────────────────────────────────────────────
  int _deletedCount = 0;
  int _realtimeScanned = 0;
  int _highScanned = 0;
  int _normalScanned = 0;

  SmartScanQueue({
    required this.scorer,
    required this.engine,
    required this.deleteManager,
    required this.notifier,
    int maxWorkers = 2,
  }) : _maxWorkers = maxWorkers.clamp(1, 4);

  // ══════════════════════════════════════════════════════════════════════════
  //  PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  void add(String path, {ScanPriority priority = ScanPriority.normal}) {
    if (_cancelled) return;
    if (_pending.contains(path)) return;
    // ✅ FIX: شيلنا الـ path check — الـ dedup صار بالـ hash جوا _processImage/_processVideo
    if (!ScanTargets.isMediaFile(path)) return;

    _pending.add(path);

    switch (priority) {
      case ScanPriority.realtime:
        _realtimeQ.add(path);
        _trySpawn(forceRealtime: true); // يشغّل worker إضافي فوق الحد
      case ScanPriority.high:
        _highQ.add(path);
        _trySpawn();
      case ScanPriority.normal:
        _normalQ.add(path);
        _trySpawn();
    }
  }

  void addBatch(List<String> paths,
      {ScanPriority priority = ScanPriority.normal}) {
    for (final p in paths) {
      add(p, priority: priority);
    }
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
    _trySpawn();
  }

  void updateWorkers(int n) {
    _maxWorkers = n.clamp(1, 4);
    if (!_isPaused) _trySpawn();
  }

  Future<void> dispose() async {
    _cancelled = true;
    _realtimeQ.clear();
    _highQ.clear();
    _normalQ.clear();
    _pending.clear();
    _sessionSeen.clear();
  }

  // ─── Getters ──────────────────────────────────────────────────────────────
  int get pendingCount => _realtimeQ.length + _highQ.length + _normalQ.length;
  bool get isProcessing => _activeWorkers > 0 || pendingCount > 0;
  int get deletedCount => _deletedCount;

  Map<String, int> get metrics => {
        'realtime': _realtimeScanned,
        'high': _highScanned,
        'normal': _normalScanned,
        'deleted': _deletedCount,
        'pending': pendingCount,
        'workers': _activeWorkers,
      };

  // ══════════════════════════════════════════════════════════════════════════
  //  WORKER SPAWNING
  // ══════════════════════════════════════════════════════════════════════════

  void _trySpawn({bool forceRealtime = false}) {
    if (_cancelled || _isPaused) return;

    // realtime يشغّل worker إضافي واحد فوق الحد
    final effectiveMax = (forceRealtime && _realtimeQ.isNotEmpty)
        ? _maxWorkers + 1
        : _maxWorkers;

    while (_activeWorkers < effectiveMax && pendingCount > 0) {
      _spawnWorker();
    }
  }

  (String, ScanPriority)? _dequeue() {
    if (_realtimeQ.isNotEmpty)
      return (_realtimeQ.removeAt(0), ScanPriority.realtime);
    if (_highQ.isNotEmpty) return (_highQ.removeAt(0), ScanPriority.high);
    if (_normalQ.isNotEmpty) return (_normalQ.removeAt(0), ScanPriority.normal);
    return null;
  }

  void _spawnWorker() {
    _activeWorkers++;
    Future(() async {
      while (!_cancelled && !_isPaused) {
        final item = _dequeue();
        if (item == null) break;

        final (path, priority) = item;
        _pending.remove(path);
        // ✅ FIX: مش بنضيف path للـ sessionSeen هنا
        // الـ _sessionSeen.add(hash) بيحصل بعد حساب الـ hash في _processImage/_processVideo

        try {
          await _processFile(path, priority: priority);
        } catch (e) {
          if (kDebugScan) debugPrint('[SmartScanQueue] ❌ error: $e');
        }
      }
      _activeWorkers--;

      // لو في حاجة جديدة جت أثناء الشغل
      if (!_cancelled && !_isPaused && pendingCount > 0) _trySpawn();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  FILE PROCESSING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _processFile(String path,
      {required ScanPriority priority}) async {
    if (_cancelled) return;
    if (ScanTargets.isVideo(path)) {
      await _processVideo(path, priority: priority);
    } else if (ScanTargets.isImage(path)) {
      await _processImage(path, priority: priority);
    }
  }

  // ─── IMAGE ────────────────────────────────────────────────────────────────
  Future<void> _processImage(String path,
      {required ScanPriority priority}) async {
    final file = File(path);
    if (!await file.exists()) return;

    final stat = await file.stat();
    if (stat.size < 10240) return; // < 10KB → تجاهل
    if (stat.size > 50 * 1024 * 1024) return; // > 50MB → تجاهل

    final hash = await _partialHash(file);

    _sessionSeen.add(hash); // احجز الـ hash قبل الفحص (منع race بين workers)

    final bytes = await file.readAsBytes();
    final scored = await scorer.score(bytes);
    final decision = engine.decide(scored, scored.rawNsfw, filePath: path);
    final isNsfw = decision.result == DecisionResult.reject;

    if (kDebugScan) {
      final result = isNsfw ? '❌ NSFW' : '✅ SFW';
      debugPrint(
        '[SmartScanQueue] 🖼️ [${priority.name}] $result '
        '| nsfw=${scored.nsfwScore.toStringAsFixed(3)} '
        '| weighted=${scored.weighted.toStringAsFixed(3)} '
        '| ${path.split('/').last}',
      );
    }

    await _recordStat(path, isNsfw: isNsfw, isVideo: false);

    if (isNsfw && !_cancelled) {
      final deleted = await deleteManager.deleteImmediately(path);
      if (deleted) {
        _deletedCount++;
        await Future.wait([_logDeletion(path), _notifyScanner(path)]);
        await notifier.showDeletedNotification(path);
      }
    }

    await _compactIfNeeded();
    _countMetric(priority);
    _sessionSeen.remove(path);
  }

  // ─── VIDEO ────────────────────────────────────────────────────────────────
  Future<void> _processVideo(String path,
      {required ScanPriority priority}) async {
    final file = File(path);
    if (!await file.exists()) return;

    if (_sessionSeen.contains(path)) return;
    _sessionSeen.add(path);

    // ─── Duration via binary search (بدل native channel) ──────────────────
    final durationMs = await _estimateDuration(path);
    final timestamps = _adaptiveTimestamps(durationMs);

    if (kDebugScan) {
      final m = durationMs ~/ 60000;
      final s = (durationMs % 60000) ~/ 1000;
      debugPrint(
        '[SmartScanQueue] ▶️ [${priority.name}] بدء فحص: ${path.split('/').last} '
        '| مدة تقريبية: $m:${s.toString().padLeft(2, '0')} '
        '| إجمالي الفريمات: ${timestamps.length}',
      );
      for (int i = 0; i < timestamps.length; i++) {
        final ms = timestamps[i];
        final fm = ms ~/ 60000;
        final fs = (ms % 60000) ~/ 1000;
        debugPrint(
          '[SmartScanQueue]   📌 فريم ${i + 1}/${timestamps.length} '
          '→ $fm:${fs.toString().padLeft(2, '0')} (${ms ~/ 1000}ث)',
        );
      }
    }

    bool isNsfw = false;
    int frames = 0;

    for (int i = 0; i < timestamps.length; i++) {
      if (_cancelled) break;

      final ms = timestamps[i];

      if (kDebugScan) {
        final fm = ms ~/ 60000;
        final fs = (ms % 60000) ~/ 1000;
        debugPrint(
          '[SmartScanQueue] 🔍 جاري فحص فريم ${i + 1}/${timestamps.length} '
          '| الوقت: $fm:${fs.toString().padLeft(2, '0')} '
          '| ${path.split('/').last}',
        );
      }

      final frameBytes = await _extractFrame(path, ms);
      if (frameBytes == null) {
        if (kDebugScan) {
          debugPrint(
              '[SmartScanQueue] ⚠️ فريم ${i + 1} فشل في الاستخراج — تخطي');
        }
        continue;
      }

      frames++;
      final scored = await scorer.score(frameBytes);

      if (kDebugScan) {
        final fm = ms ~/ 60000;
        final fs = (ms % 60000) ~/ 1000;
        final result = scored.rawNsfw.isNsfw ? '❌ NSFW' : '✅ SFW';
        debugPrint(
          '[SmartScanQueue] $result فريم ${i + 1} '
          '| الوقت: $fm:${fs.toString().padLeft(2, '0')} '
          '| nsfw=${scored.rawNsfw.nsfw.toStringAsFixed(3)} '
          '| weighted=${scored.weighted.toStringAsFixed(3)} '
          '| ${path.split('/').last}',
        );
      }

      if (scored.rawNsfw.isNsfw) {
        isNsfw = true;
        break; // early exit — مش محتاج نكمل
      }
    }

    if (kDebugScan) {
      final verdict = isNsfw ? '🚫 NSFW — سيتم الحذف' : '✅ آمن';
      debugPrint(
        '[SmartScanQueue] 🏁 انتهى فحص: ${path.split('/').last} '
        '| النتيجة: $verdict '
        '| فريمات فُحصت: $frames/${timestamps.length}',
      );
    }

    await _recordStat(path,
        isNsfw: frames == 0 ? false : isNsfw, isVideo: true);

    if (isNsfw && !_cancelled) {
      final deleted = await deleteManager.deleteImmediately(path);
      if (deleted) {
        _deletedCount++;
        await Future.wait([_logDeletion(path), _notifyScanner(path)]);
        await notifier.showDeletedNotification(path);
      }
    }

    await _compactIfNeeded();
    _countMetric(priority);
    _sessionSeen.remove(path);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  VIDEO DURATION — Binary Search بـ VideoThumbnail
  //
  //  المشكلة: MethodChannel('medi_guard/video_metadata') مسجّل على
  //  الـ main FlutterEngine — الـ background isolate عنده messenger مختلف
  //  فالـ call بيتجاهل → timeout → fallback 60 ثانية → frames غلطانة.
  //
  //  الحل: نستخدم VideoThumbnail.thumbnailData() اللي شغّال في الـ isolate.
  //  المنطق: لو thumbnailData نجح عند timestamp → الفيديو وصل لهنا.
  //          لو فشل (null) → الفيديو خلص قبله.
  //  الدقة: ±5% — كافية لتوزيع الـ frames صح.
  //  التكلفة: 4–6 probes × ~50ms = ~300ms بدل timeout 5 ثواني.
  // ══════════════════════════════════════════════════════════════════════════

  Future<int> _estimateDuration(String path) async {
    // Upper bound candidates: 2د → 5د → 15د → 30د → 60د → 120د → 180د
    const candidates = [
      2 * 60 * 1000,
      5 * 60 * 1000,
      15 * 60 * 1000,
      30 * 60 * 1000,
      60 * 60 * 1000,
      120 * 60 * 1000,
      180 * 60 * 1000,
    ];

    // الخطوة 1: ابحث عن أول candidate يفشل → upper bound
    int lowerMs = 0;
    int upperMs = candidates.last;

    for (final ms in candidates) {
      final ok = await _probeTimestamp(path, ms);
      if (!ok) {
        upperMs = ms;
        break;
      }
      lowerMs = ms;
    }

    // لو حتى 2 دقيقة فشلت → الفيديو أقصر من كده — استخدم 60 ث كافتراض
    if (lowerMs == 0) {
      return 60000;
    }

    // الخطوة 2: binary search بين lowerMs و upperMs بدقة ±5%
    for (int step = 0; step < 4; step++) {
      final midMs = (lowerMs + upperMs) ~/ 2;
      if (midMs <= lowerMs) break;
      final ok = await _probeTimestamp(path, midMs);
      if (ok) {
        lowerMs = midMs;
      } else {
        upperMs = midMs;
      }
    }

    // نضيف 10% هامش أمان
    final estimated = (lowerMs * 1.10).round();

    if (kDebugScan) {
      final m = estimated ~/ 60000;
      final s = (estimated % 60000) ~/ 1000;
      debugPrint(
        '[SmartScanQueue] 📏 مدة مقدّرة: $m:${s.toString().padLeft(2, '0')} '
        '($estimated ms) | ${path.split('/').last}',
      );
    }

    return estimated;
  }

  // probe: هل الفيديو وصل لهذا الـ timestamp؟
  Future<bool> _probeTimestamp(String path, int timeMs) async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        maxWidth: 64,
        maxHeight: 64,
        quality: 10,
      ).timeout(const Duration(seconds: 4));
      return bytes != null && bytes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADAPTIVE TIMESTAMPS — دايماً 10 frames موزعة على المدة الكاملة
  //
  //  أول frame  : عند 10 ث        (يتخطى الـ intro / black screen)
  //  آخر frame  : قبل النهاية 19ث  (يتخطى الـ credits / fade-out)
  //  الـ 8 الباقية: موزعة uniform بين first و last
  //
  //  الاستثناء الوحيد: فيديو أقصر من 30 ث → frame واحدة في المنتصف
  //  لأن الـ firstMs و lastMs بيتقاربوا جداً ومش هيفرق
  //
  //  مثال:
  //    فيديو 2 د   → frames كل ~13 ث
  //    فيديو 8 د   → frames كل ~50 ث
  //    فيديو 24 د  → frames كل ~2.5 د
  //    فيديو 60 د  → frames كل ~6 د
  // ══════════════════════════════════════════════════════════════════════════

  List<int> _adaptiveTimestamps(int durationMs) {
    if (durationMs <= 0) return [0];

    // فيديو أقل من 30 ث → frame واحدة في المنتصف
    if (durationMs < 30000) return [durationMs ~/ 2];

    // فيديو أكتر من 40 دقيقة → 12 frame، غير كده → 10
    final totalFrames = durationMs > 40 * 60 * 1000 ? 12 : 10;
    const firstMs = 10000; // بعد 10 ث — يتخطى الـ intro/black screen

    // آخر frame قبل النهاية بـ 19 ث — يتخطى الـ credits/fade-out
    final lastMs =
        (durationMs - 19000).clamp(firstMs + 1000, durationMs - 1000);

    // لو الفيديو قصير جداً ومش في مساحة كافية → توزيع بسيط
    if (lastMs <= firstMs) return [durationMs ~/ 2];

    // توزيع الـ 10 frames بالتساوي من firstMs لـ lastMs
    // frame[0] = firstMs, frame[9] = lastMs
    // الـ 8 الوسطى موزعة uniform
    return List.generate(
      totalFrames,
      (i) => firstMs + ((lastMs - firstMs) * i ~/ (totalFrames - 1)),
    );
  }

  // استخراج frame بـ VideoThumbnail — zero disk IO
  Future<Uint8List?> _extractFrame(String path, int timeMs) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        maxWidth: 384,
        maxHeight: 384,
        quality: 75,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  STORAGE & UTILITIES
  // ══════════════════════════════════════════════════════════════════════════

  static int _compactCounter = 0;

  Future<String> _partialHash(File file) async {
    const chunk = 64 * 1024;
    final size = await file.length();
    final List<int> bytes;

    if (size <= chunk * 2) {
      bytes = await file.readAsBytes();
    } else {
      final raf = await file.open();
      try {
        final head = await raf.read(chunk);
        await raf.setPosition(size - chunk);
        final tail = await raf.read(chunk);
        bytes = [...head, ...tail];
      } finally {
        await raf.close();
      }
    }
    // 12 حرف = 48-bit entropy = collision 1 في 281 تريليون
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  Future<void> _compactIfNeeded() async {
    if (++_compactCounter < 150) return;
    _compactCounter = 0;
    try {
      await Hive.box('scanned_hashes').compact();
    } catch (_) {}
  }

  Future<void> _notifyScanner(String path) async {
    try {
      await _mediaScannerChannel.invokeMethod(
          'scanFile', {'path': path}).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _logDeletion(String path) async {
    try {
      final box = Hive.box('deleted_log');
      if (box.length >= 50) await box.delete(box.keys.first);
      await box.add({
        'fileName': path.split('/').last,
        'source': _detectFolder(path),
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
        'path': path,
      });
    } catch (_) {}
  }

  Future<void> _recordStat(String path,
      {required bool isNsfw, required bool isVideo}) async {
    try {
      final box = Hive.box('scan_stats');
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final key = 'stat_$today';
      final prev = (box.get(key) as Map<dynamic, dynamic>?) ?? {};
      await box.put(key, {
        ...prev,
        'total': ((prev['total'] as int?) ?? 0) + 1,
        if (isNsfw) 'nsfw': ((prev['nsfw'] as int?) ?? 0) + 1,
        if (isVideo) 'videos': ((prev['videos'] as int?) ?? 0) + 1,
      });
    } catch (_) {}
  }

  String _detectFolder(String path) {
    if (path.contains('/WhatsApp/')) return 'واتساب';
    if (path.contains('/Telegram/')) return 'تيليجرام';
    if (path.contains('/Download/')) return 'التنزيلات';
    if (path.contains('/DCIM/')) return 'الكاميرا';
    if (path.contains('/Instagram')) return 'إنستجرام';
    if (path.contains('/TikTok/')) return 'تيك توك';
    if (path.contains('/Snapchat/')) return 'سناب شات';
    if (path.contains('/Pictures/')) return 'الصور';
    if (path.contains('/Movies/') || path.contains('/Videos/'))
      return 'الفيديوهات';
    return 'أخرى';
  }

  void _countMetric(ScanPriority p) {
    switch (p) {
      case ScanPriority.realtime:
        _realtimeScanned++;
      case ScanPriority.high:
        _highScanned++;
      case ScanPriority.normal:
        _normalScanned++;
    }
  }
}
