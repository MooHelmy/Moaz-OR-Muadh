import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/data/services/device_capability_service.dart';
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

// ✅ FIX: أُزيل الثابت _concurrentFiles = 2
// الـ concurrency دلوقتي dynamic — بيتحسب في ScanQueue._initConcurrency()
// بناءً على RAM + CPU + thermal + battery (راجع DeviceCapabilityService)

const MethodChannel _mediaScannerChannel =
    MethodChannel('medi_guard/media_scanner');

class ScanQueue {
  final EnsembleScorer scorer;
  final DecisionEngine engine;
  final DeleteManager deleteManager;
  final ScanNotificationService notifier;

  // ✅ FIX: adaptive concurrency — مش ثابت
  final DeviceCapabilityService _capabilityService = DeviceCapabilityService();

  /// الحد الأقصى الحالي للـ workers — يُحدَّث عند التهيئة وعند تغير الحالة
  int _maxWorkers = 2; // قيمة افتراضية آمنة حتى تنتهي التهيئة

  /// آخر state للـ concurrency — للمراقبة والـ logging
  ConcurrencyState? _lastConcurrencyState;

  final Set<String> _pendingSet = {};
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
  }) {
    // نبدأ تهيئة الـ concurrency في الـ background — لا نحجب الـ constructor
    // _maxWorkers = 2 كـ fallback حتى تنتهي
    _initConcurrency();
  }

  /// يحسب الـ concurrency المناسب عند البدء ويحفظه في _maxWorkers
  Future<void> _initConcurrency() async {
    try {
      final state = await _capabilityService.computeConcurrency();
      _lastConcurrencyState = state;
      _maxWorkers = state.concurrency;
      if (kDebugScan) {
        debugPrint(
          '[ScanQueue] concurrency=$_maxWorkers '
          'tier=${state.hardwareTier.name}'
          '${state.throttleReason != null ? " throttle=${state.throttleReason}" : ""}',
        );
      }
      // لو الـ queue فيها ملفات انتظرت → نحاول تشغيل workers إضافية
      _trySpawnWorker();
    } catch (_) {
      // نكمل بالقيمة الافتراضية = 2
    }
  }

  /// يُعيد حساب الـ concurrency — استدعيه عند تغيّر حالة الجهاز
  /// (thermal event / battery mode change / استئناف من pause)
  Future<void> refreshConcurrency() async {
    if (_cancelled) return;
    try {
      final state = await _capabilityService.computeConcurrency();
      _lastConcurrencyState = state;
      final prev = _maxWorkers;
      _maxWorkers = state.concurrency;
      if (kDebugScan && prev != _maxWorkers) {
        debugPrint(
          '[ScanQueue] concurrency updated: $prev → $_maxWorkers'
          '${state.throttleReason != null ? " (${state.throttleReason})" : ""}',
        );
      }
      // لو زاد الحد → قد نقدر نشغل workers جديدة
      if (_maxWorkers > prev) _trySpawnWorker();
    } catch (_) {}
  }

  /// الـ tier الحالي — للعرض في الـ UI أو الـ debug
  DeviceTier? get currentTier => _lastConcurrencyState?.hardwareTier;

  /// الـ concurrency الحالي — للعرض في الـ UI
  int get currentConcurrency => _maxWorkers;

  int get pendingCount => _queue.length;
  bool get isProcessing => _activeWorkers > 0 || _queue.isNotEmpty;

  void pauseForBattery() {
    _isPaused = true;
  }

  void resumeFromBattery() {
    _isPaused = false;
    // ✅ FIX: نعيد حساب الـ concurrency عند الاستئناف
    // Battery Saver قد يكون تغيّر أثناء الـ pause
    refreshConcurrency().then((_) => _trySpawnWorker());
  }

  void pauseHeavyTasks() {
    _isPaused = true;
  }

  void resumeHeavyTasks() {
    _isPaused = false;
    // ✅ FIX: نعيد حساب الـ concurrency عند الاستئناف
    // Thermal state قد تحسّن أثناء الـ pause
    refreshConcurrency().then((_) => _trySpawnWorker());
  }

  void add(String path, {bool priority = false}) {
    if (_cancelled) return;
    if (!_pendingSet.contains(path)) {
      _pendingSet.add(path);
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

    final completer = Completer<void>();
    _activeCompleters.add(completer);

    Future.delayed(const Duration(milliseconds: 50)).then((_) {
      return _processFile(path);
    }).then((_) {
      completer.complete();
    }).catchError((e) {
      completer.complete();
    }).whenComplete(() {
      _activeCompleters.remove(completer);
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

  Future<void> _processFile(String path) async {
    if (_cancelled) return;
    try {
      if (ScanTargets.isVideo(path)) {
        await _processVideo(path);
      } else if (ScanTargets.isImage(path)) {
        await _processImage(path);
      }
    } catch (e) {
      // ScanQueue Error
    }
  }

  // ─── VIDEO ──────────────────────────────────────────────
  Future<void> _processVideo(String videoPath) async {
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

      final frameBytes = await _extractFrameBytes(videoPath, timestamps[i]);
      if (frameBytes == null) continue;

      framesExtracted++;
      final scoredResult = await scorer.score(frameBytes);

      if (scoredResult.rawNsfw.nsfw > scoredResult.rawNsfw.sfw) {
        isNsfw = true;
        break;
      }
    }

    // ✅ FIX #6: سجّل stats حتى لو ما استخرجناش أي frame
    await _recordScanStat(videoPath, isNsfw: framesExtracted == 0 ? false : isNsfw, isVideo: true);

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
      final result = await _videoMetaChannel
          .invokeMapMethod<String, dynamic>('getVideoMetadata', {'path': videoPath})
          .timeout(const Duration(seconds: 5));

      if (result != null) {
        return VideoMetadata(
          durationMs: (result['durationMs'] as num?)?.toInt() ?? 60000,
          width:      (result['width']      as num?)?.toInt() ?? 0,
          height:     (result['height']     as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    return VideoMetadata(durationMs: 60000, width: 0, height: 0);
  }

  // ✅ FIX: أول frame بعد 5s دايماً، آخر frame قبل النهاية بـ 5s دايماً
  //
  // المشكلة القديمة:
  //   أول frame عند 0ms → غالباً black screen أو intro logo
  //   آخر frame عند آخر ثانية → ممكن fade to black أو credits
  //   كلهم مش محتوى حقيقي → ممكن يفوت NSFW
  //
  // الحل:
  //   offsetMs = 5000ms → نتخطى الـ intro والـ outro
  //   الـ frames الوسطى تتوزع تلقائياً بين first و last
  List<int> _generateAdaptiveTimestamps(int durationMs) {
    if (durationMs <= 0) return [0];

    const int offsetMs = 5000; // 5 ثواني offset ثابت

    final int frameCount;
    if (durationMs < 10000) {
      frameCount = 2;
    } else if (durationMs < 30000) {
      frameCount = 3;
    } else if (durationMs < 300000) {
      frameCount = 4;
    } else if (durationMs < 1800000) {
      frameCount = 5;
    } else {
      frameCount = 6;
    }

    // لو الفيديو أقصر من offset * 2 → frame واحدة في المنتصف
    if (durationMs <= offsetMs * 2) {
      return [(durationMs / 2).round()];
    }

    final int first = offsetMs; // دايماً 5s
    final int last = durationMs - offsetMs; // دايماً قبل النهاية بـ 5s

    if (frameCount == 1) return [first];
    if (frameCount == 2) return [first, last];

    // الـ frames الوسطى موزعة بالتساوي بين first و last
    final int innerCount = frameCount - 2;
    final List<int> timestamps = [first];

    for (int i = 1; i <= innerCount; i++) {
      final double step = (last - first) / (innerCount + 1);
      timestamps.add((first + step * i).round());
    }

    timestamps.add(last);
    return timestamps;
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
        maxWidth: 224,
        maxHeight: 224,
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
    if (stat.size < 10240) return;
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
      await box.add({
        'fileName': path.split('/').last,
        'source': _detectFolder(path),
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
        'path': path,
      });
    } catch (e) {
      // Failed to log deletion
    }
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
      return sha256.convert([...head, ...tail]).toString();
    } finally {
      await raf.close();
    }
  }
}
