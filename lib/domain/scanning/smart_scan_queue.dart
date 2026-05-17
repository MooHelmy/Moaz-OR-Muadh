// ══════════════════════════════════════════════════════════════════════════════
//  smart_scan_queue.dart  —  v1.0
//
//  Priority-aware scan queue بـ 3 مستويات:
//    🔴 realtime  → FileObserver (ملف جديد دلوقتي)       → فوري
//    🟡 high      → MediaStore recent (اتفتح مؤخراً)     → قريب
//    🟢 normal    → Background sweep                      → لما يفضى
//
//  الـ 3 موديلات بتشتغل مع بعض على كل ملف:
//    NSFW (0.75) + Skin (0.15) + Face (0.10) = weighted score
//    Early exit لو NSFW > 0.85 — مش محتاجين Skin/Face
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/domain/deletion/delete_manager.dart';
import 'package:medi_guard/domain/engines/decision_engine.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';

// ─── Priority ─────────────────────────────────────────────────────────────────
enum ScanPriority { realtime, high, normal }

// ─── VideoMetadata ────────────────────────────────────────────────────────────
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

// ─── Channels ─────────────────────────────────────────────────────────────────
const _videoMetaChannel   = MethodChannel('medi_guard/video_metadata');
const _mediaScannerChannel = MethodChannel('medi_guard/media_scanner');

const bool kDebugScan = kDebugMode;

// ══════════════════════════════════════════════════════════════════════════════
//  SmartScanQueue
// ══════════════════════════════════════════════════════════════════════════════
class SmartScanQueue {
  final EnsembleScorer scorer;
  final DecisionEngine engine;
  final DeleteManager deleteManager;
  final ScanNotificationService notifier;

  // ─── 3 queues منفصلة ──────────────────────────────────────────────────────
  final _realtimeQ = <String>[];
  final _highQ     = <String>[];
  final _normalQ   = <String>[];

  // dedup: لا نفحص نفس الملف مرتين في نفس الجلسة
  final _pending       = <String>{};
  final _sessionSeen   = <String>{};

  int  _activeWorkers = 0;
  int  _maxWorkers    = 2;
  bool _cancelled     = false;
  bool _isPaused      = false;

  // ─── Metrics ──────────────────────────────────────────────────────────────
  int _deletedCount    = 0;
  int _realtimeScanned = 0;
  int _highScanned     = 0;
  int _normalScanned   = 0;

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
    if (_sessionSeen.contains(path)) return;
    if (!ScanTargets.isMediaFile(path)) return;

    _pending.add(path);

    switch (priority) {
      case ScanPriority.realtime:
        _realtimeQ.add(path);
        _trySpawn(forceRealtime: true); // ممكن يتجاوز الحد بـ +1
      case ScanPriority.high:
        _highQ.add(path);
        _trySpawn();
      case ScanPriority.normal:
        _normalQ.add(path);
        _trySpawn();
    }
  }

  void addBatch(List<String> paths, {ScanPriority priority = ScanPriority.normal}) {
    for (final p in paths) add(p, priority: priority);
  }

  void pause()  { _isPaused = true; }
  void resume() { _isPaused = false; _trySpawn(); }

  void updateWorkers(int n) {
    _maxWorkers = n.clamp(1, 4);
    if (!_isPaused) _trySpawn();
  }

  Future<void> dispose() async {
    _cancelled = true;
    _realtimeQ.clear(); _highQ.clear(); _normalQ.clear();
    _pending.clear();
  }

  // ─── Getters ──────────────────────────────────────────────────────────────
  int get pendingCount  => _realtimeQ.length + _highQ.length + _normalQ.length;
  bool get isProcessing => _activeWorkers > 0 || pendingCount > 0;
  int get deletedCount  => _deletedCount;

  Map<String, int> get metrics => {
    'realtime' : _realtimeScanned,
    'high'     : _highScanned,
    'normal'   : _normalScanned,
    'deleted'  : _deletedCount,
    'pending'  : pendingCount,
    'workers'  : _activeWorkers,
  };

  // ══════════════════════════════════════════════════════════════════════════
  //  WORKER SPAWNING
  // ══════════════════════════════════════════════════════════════════════════

  void _trySpawn({bool forceRealtime = false}) {
    if (_cancelled || _isPaused) return;

    // realtime ممكن يشغّل worker إضافي واحد فوق الحد
    final effectiveMax = (forceRealtime && _realtimeQ.isNotEmpty)
        ? _maxWorkers + 1
        : _maxWorkers;

    // نشغّل workers بالعدد المطلوب — كل worker يشيل من الـ queue بنفسه
    while (_activeWorkers < effectiveMax && pendingCount > 0) {
      _spawnWorker();
    }
  }

  (String, ScanPriority)? _dequeue() {
    if (_realtimeQ.isNotEmpty) return (_realtimeQ.removeAt(0), ScanPriority.realtime);
    if (_highQ.isNotEmpty)     return (_highQ.removeAt(0),     ScanPriority.high);
    if (_normalQ.isNotEmpty)   return (_normalQ.removeAt(0),   ScanPriority.normal);
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
        _sessionSeen.add(path);

        try {
          await _processFile(path, priority: priority);
        } catch (e) {
          if (kDebugScan) debugPrint('[SmartScanQueue] error: $e');
        }
      }
      _activeWorkers--;

      // لو في الـ queue حاجة تانية جت أثناء الانتظار
      if (!_cancelled && !_isPaused && pendingCount > 0) _trySpawn();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  FILE PROCESSING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _processFile(String path, {required ScanPriority priority}) async {
    if (_cancelled) return;
    final ext = path.split('.').last.toLowerCase();
    if (ScanTargets.videoExtensions.contains('.$ext')) {
      await _processVideo(path, priority: priority);
    } else {
      await _processImage(path, priority: priority);
    }
  }

  // ─── IMAGE ────────────────────────────────────────────────────────────────
  Future<void> _processImage(String path, {required ScanPriority priority}) async {
    final file = File(path);
    if (!await file.exists()) return;

    final stat = await file.stat();
    if (stat.size < 10240)           return; // < 10KB → skip
    if (stat.size > 50 * 1024 * 1024) return; // > 50MB → skip

    final hash = await _partialHash(file);
    final box  = Hive.box('scanned_hashes');
    if (box.get(hash) != null) return; // سبق فحصه

    final bytes   = await file.readAsBytes();
    final scored  = await scorer.score(bytes);
    final decision = engine.decide(scored, scored.rawNsfw, filePath: path);
    final isNsfw  = decision.result == DecisionResult.reject;

    await _recordStat(path, isNsfw: isNsfw, isVideo: false);

    if (isNsfw && !_cancelled) {
      final deleted = await deleteManager.deleteImmediately(path);
      if (deleted) {
        _deletedCount++;
        await Future.wait([_logDeletion(path), _notifyScanner(path)]);
        await notifier.showDeletedNotification(path);
        if (kDebugScan) debugPrint('🗑️ [${priority.name}] image: $path');
      }
    }

    await box.put(hash, 1);
    await _compactIfNeeded();
    _metric(priority);
  }

  // ─── VIDEO ────────────────────────────────────────────────────────────────
  Future<void> _processVideo(String path, {required ScanPriority priority}) async {
    final file = File(path);
    if (!await file.exists()) return;

    final hash = await _partialHash(file);
    final box  = Hive.box('scanned_hashes');
    if (box.get(hash) != null) return;

    final meta       = await _videoMetadata(path);
    final timestamps = _adaptiveTimestamps(meta.durationMs);

    bool isNsfw = false;
    int  frames = 0;

    for (final ms in timestamps) {
      if (_cancelled) break;

      final frameBytes = await _frameBytes(path, ms);
      if (frameBytes == null) continue;

      frames++;
      final scored = await scorer.score(frameBytes);

      if (kDebugScan) {
        debugPrint(
          '[${priority.name}] @${ms}ms '
          'nsfw=${scored.nsfwScore.toStringAsFixed(2)} '
          'skin=${scored.rawSkinScore.toStringAsFixed(2)} '
          'weighted=${scored.weighted.toStringAsFixed(2)}',
        );
      }

      if (scored.rawNsfw.nsfw > scored.rawNsfw.sfw) {
        isNsfw = true;
        break; // early exit
      }
    }

    await _recordStat(path, isNsfw: frames == 0 ? false : isNsfw, isVideo: true);

    if (isNsfw && !_cancelled) {
      final deleted = await deleteManager.deleteImmediately(path);
      if (deleted) {
        _deletedCount++;
        await Future.wait([_logDeletion(path), _notifyScanner(path)]);
        await notifier.showDeletedNotification(path);
        if (kDebugScan) debugPrint('🗑️ [${priority.name}] video @frame$frames: $path');
      }
    }

    await box.put(hash, 1);
    await _compactIfNeeded();
    _metric(priority);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADAPTIVE TIMESTAMPS
  //  • أول frame  : بعد 8 ث          (تتخطى intro/black screen)
  //  • آخر frame  : قبل النهاية 15 ث  (تتخطى credits/fade-out)
  //  • الوسطى     : في الربع الأخير   (NSFW غالباً في النهاية)
  // ══════════════════════════════════════════════════════════════════════════
  List<int> _adaptiveTimestamps(int durationMs) {
    if (durationMs <= 0) return [0];

    // فيديو قصير جداً → المنتصف بس
    if (durationMs < 30000) return [durationMs ~/ 2];

    const firstMs = 8000;
    final lastMs  = (durationMs - 15000).clamp(firstMs + 1000, durationMs - 1000);
    if (lastMs <= firstMs) return [durationMs ~/ 2];

    // عدد الـ frames الوسطى حسب المدة
    final mid = durationMs < 60000   ? 0
              : durationMs < 300000  ? 2
              : durationMs < 1800000 ? 4
              :                        6;

    if (mid == 0) return [firstMs, lastMs];

    // الوسطى في الربع الأخير (75% → lastMs-1s)
    final rangeStart = (durationMs * 0.75).round().clamp(firstMs + 1000, lastMs - 1000);
    final rangeEnd   = lastMs - 1000;
    final range      = rangeEnd - rangeStart;

    final middle = range > 0
        ? List.generate(mid, (i) => rangeStart + range * (i + 1) ~/ (mid + 1))
        : List.generate(mid, (i) => firstMs + (lastMs - firstMs) * (i + 1) ~/ (mid + 1));

    return [firstMs, ...middle, lastMs];
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  NATIVE CALLS
  // ══════════════════════════════════════════════════════════════════════════

  Future<VideoMetadata> _videoMetadata(String path) async {
    try {
      final r = await _videoMetaChannel
          .invokeMapMethod<String, dynamic>('getVideoMetadata', {'path': path})
          .timeout(const Duration(seconds: 5));
      if (r != null) {
        return VideoMetadata(
          durationMs: (r['durationMs'] as num?)?.toInt() ?? 60000,
          width:      (r['width']      as num?)?.toInt() ?? 0,
          height:     (r['height']     as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    return VideoMetadata(durationMs: 60000, width: 0, height: 0);
  }

  Future<Uint8List?> _frameBytes(String path, int timeMs) async {
    try {
      return await _videoMetaChannel.invokeMethod<Uint8List>(
        'getFrameBytes',
        {'path': path, 'timeMs': timeMs, 'size': 384},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<void> _notifyScanner(String path) async {
    try {
      await _mediaScannerChannel
          .invokeMethod('scanFile', {'path': path})
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HASH & STORAGE
  // ══════════════════════════════════════════════════════════════════════════

  static int _compactCounter = 0;

  Future<String> _partialHash(File file) async {
    const chunk = 64 * 1024;
    final size  = await file.length();
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
    // 12 حرف = 48-bit = احتمال collision 1 في 281 تريليون
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  Future<void> _compactIfNeeded() async {
    if (++_compactCounter < 150) return;
    _compactCounter = 0;
    try { await Hive.box('scanned_hashes').compact(); } catch (_) {}
  }

  Future<void> _logDeletion(String path) async {
    try {
      final box = Hive.box('deleted_log');
      if (box.length >= 50) await box.delete(box.keys.first);
      await box.add({
        'fileName' : path.split('/').last,
        'source'   : _folder(path),
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
        'path'     : path,
      });
    } catch (_) {}
  }

  Future<void> _recordStat(String path, {required bool isNsfw, required bool isVideo}) async {
    try {
      final box   = Hive.box('scan_stats');
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final key   = 'stat_$today';
      final prev  = (box.get(key) as Map?) ?? {};
      await box.put(key, {
        ...prev,
        'total' : ((prev['total']  as int?) ?? 0) + 1,
        if (isNsfw)  'nsfw'  : ((prev['nsfw']   as int?) ?? 0) + 1,
        if (isVideo) 'videos': ((prev['videos'] as int?) ?? 0) + 1,
      });
    } catch (_) {}
  }

  String _folder(String path) {
    if (path.contains('/WhatsApp/')) return 'WhatsApp';
    if (path.contains('/Telegram/')) return 'Telegram';
    if (path.contains('/Download/')) return 'Download';
    if (path.contains('/DCIM/'))     return 'Camera';
    if (path.contains('/Pictures/')) return 'Pictures';
    return 'Other';
  }

  void _metric(ScanPriority p) {
    switch (p) {
      case ScanPriority.realtime: _realtimeScanned++;
      case ScanPriority.high:     _highScanned++;
      case ScanPriority.normal:   _normalScanned++;
    }
  }
}
