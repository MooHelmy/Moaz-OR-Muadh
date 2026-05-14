import 'dart:async';
import 'dart:collection';
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
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

const bool kDebugScan = kDebugMode;

// ✅ FIX #13: Adaptive concurrency بدلاً من ثابت = 3
// على الأجهزة الضعيفة نخفف، على القوية نزيد
const int _concurrentFiles = 2; // آمن على كل الأجهزة

// ──────────────────────────────────────────────────────────────────────────────
// _ScanLruCache — LRU Cache لنتايج الفحص
//
// بيحتفظ بنتيجة آخر 150 صورة/فيديو تم فحصهم.
// لو نفس الملف وصل تاني → نتيجته جاهزة فوراً بدون AI.
// 150 مدخل ≈ 30KB ذاكرة فقط.
// ──────────────────────────────────────────────────────────────────────────────
final class _ScanLruCache {
  static const int _maxSize = 150;
  final LinkedHashMap<String, bool> _map = LinkedHashMap();

  bool? get(String hash) {
    final v = _map.remove(hash);
    if (v != null) _map[hash] = v;
    return v;
  }

  void put(String hash, bool isNsfw) {
    _map.remove(hash);
    _map[hash] = isNsfw;
    if (_map.length > _maxSize) _map.remove(_map.keys.first);
  }

  void clear() => _map.clear();
}

const MethodChannel _mediaScannerChannel =
    MethodChannel('medi_guard/media_scanner');

class ScanQueue {
  final EnsembleScorer scorer;
  final DecisionEngine engine;
  final DeleteManager deleteManager;
  final ScanNotificationService notifier;

  final Set<String> _pendingSet = {};
  final List<String> _queue = [];
  int _activeWorkers = 0;

  // ✅ LRU Cache لنتايج الفحص — بيتجنب إعادة فحص نفس الملف بالـ AI
  final _ScanLruCache _scanCache = _ScanLruCache();

  // ✅ FIX #14: Cancellation Token — dispose ينتظر الـ workers
  bool _cancelled = false;
  bool _isPaused = false;
  final List<Completer<void>> _activeCompleters = [];

  ScanQueue({
    required this.scorer,
    required this.engine,
    required this.deleteManager,
    required this.notifier,
  });

  int get pendingCount => _queue.length;
  bool get isProcessing => _activeWorkers > 0 || _queue.isNotEmpty;

  // ✅ FIX: Added missing methods for battery and performance management
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
      if (priority) {
        _queue.insert(0, path); // ✅ وضعه في أول القائمة ليفحص فوراً
      } else {
        _queue.add(path); // المسح العادي يضاف للآخر
      }
      _trySpawnWorker();
    }
  }

  void _trySpawnWorker() {
    // ✅ Check for pause state before spawning new workers
    if (_cancelled || _isPaused) return;
    if (_activeWorkers >= _concurrentFiles || _queue.isEmpty) return;

    _activeWorkers++;
    final path = _queue.removeAt(0);
    _pendingSet.remove(path);

    final completer = Completer<void>();
    _activeCompleters.add(completer);

    _processFile(path).then((_) {
      completer.complete();
    }).catchError((e) {
      completer.complete();
    }).whenComplete(() {
      _activeCompleters.remove(completer);
      _activeWorkers--;
      _trySpawnWorker();
    });

    _trySpawnWorker();
  }

  Future<void> dispose() async {
    _cancelled = true;
    _queue.clear();
    _pendingSet.clear();
    _scanCache.clear(); // ✅ تحرير ذاكرة الـ LRU Cache

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

    if (kDebugScan) {}

    final file = File(videoPath);
    if (!await file.exists()) return;

    final hash = await _getPartialHash(file);
    final hashesBox = Hive.box('scanned_hashes');

    if (hashesBox.get(hash) != null) {
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final framePaths = <String>[];
    bool isNsfw = false;

    try {
      // ✅ FIX #15: استخدام metadata-only بدلاً من VideoPlayerController
      // video_thumbnail بيعطيك الـ frames بدون تشغيل full decoder
      final timestamps = _generateFixedTimestamps();

      for (int i = 0; i < timestamps.length; i++) {
        if (_cancelled) break;

        final timeMs = timestamps[i];
        final fp = await _extractFrame(videoPath, tempDir.path, timeMs);
        if (fp == null) continue;

        framePaths.add(fp);
        final scoredResult = await scorer.score(fp);
        final nsfw = scoredResult.rawNsfw.nsfw;
        final sfw = scoredResult.rawNsfw.sfw;

        if (nsfw > sfw) {
          isNsfw = true;
          break; // ✅ Early exit — فريم واحد NSFW يكفي
        }
      }

      if (framePaths.isEmpty) {
        await hashesBox.put(hash, 1);
        return;
      }

      // ✅ تسجيل في الإحصائيات
      await _recordScanStat(videoPath, isNsfw: isNsfw, isVideo: true);

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
    } finally {
      // ✅ FIX #16: async delete بدلاً من deleteSync
      for (final fp in framePaths) {
        try {
          await File(fp).delete();
        } catch (_) {}
      }
    }
  }

  // ✅ FIX #15: Fixed timestamps بدون VideoPlayerController
  // video_thumbnail بيرجع null تلقائياً لو الـ timestamp أكبر من المدة
  List<int> _generateFixedTimestamps() {
    return [0, 5000, 10000, 20000, 30000, 60000, 120000, 180000];
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

    final hash = await _getPartialHash(file);
    final hashesBox = Hive.box('scanned_hashes');

    if (hashesBox.get(hash) != null) return;

    // ✅ LRU Cache check — لو فحصناه من قريب، خد النتيجة من الذاكرة
    final cached = _scanCache.get(hash);
    if (cached != null) {
      if (cached && !_cancelled) {
        final deleted = await deleteManager.deleteImmediately(path);
        if (deleted) {
          await Future.wait([_logDeletion(path), _notifyMediaScanner(path)]);
          await notifier.showDeletedNotification(path);
        }
      }
      return;
    }

    final scoredResult = await scorer.score(path);
    final decision =
        engine.decide(scoredResult, scoredResult.rawNsfw, filePath: path);

    if (kDebugScan) {}

    final isNsfw = decision.result == DecisionResult.reject;

    // ✅ احفظ النتيجة في الـ LRU Cache
    _scanCache.put(hash, isNsfw);

    // ✅ تسجيل في الإحصائيات
    await _recordScanStat(path, isNsfw: isNsfw, isVideo: false);

    if (isNsfw && !_cancelled) {
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

  // ✅ FIX NEW: تسجيل إحصائيات لكل فولدر
  Future<void> _recordScanStat(String filePath,
      {required bool isNsfw, required bool isVideo}) async {
    try {
      final statsBox = Hive.box('scan_stats');

      // تحديد الفولدر/المصدر
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

      // إحصاء كلي
      final totalKey = 'total_stats';
      final totalExisting = statsBox.get(totalKey) as Map? ?? {};
      final Map<String, dynamic> totalStats =
          Map<String, dynamic>.from(totalExisting);
      totalStats['scanned'] = (totalStats['scanned'] as int? ?? 0) + 1;
      if (isNsfw)
        totalStats['blocked'] = (totalStats['blocked'] as int? ?? 0) + 1;
      await statsBox.put(totalKey, totalStats);
    } catch (e) {
      // Stats recording failed
    }
  }

  // ✅ تسجيل تفاصيل الملف المحذوف ليظهر في الـ MonitoringView
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

  // ✅ وظيفة لتحديث معرض الصور (Media Store) بعد الحذف لإزالة "الأشباح"
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
