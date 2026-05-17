// ══════════════════════════════════════════════════════════════════════════════
//  media_store_poller.dart  —  v1.0
//
//  يسأل Android MediaStore عن الملفات الجديدة كل 5 دقايق
//  بدون FileObserver — يكشف الملفات بعد اكتمال الـ write
//
//  المصدر: ContentResolver query على MediaStore.Files
//  الأولوية: ScanPriority.high (أعلى من sweep، أقل من FileObserver)
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/domain/scanning/smart_scan_queue.dart';

class MediaStorePoller {
  static const _channel      = MethodChannel('medi_guard/media_store');
  static const _pollInterval = Duration(minutes: 5);
  static const _recentLimit  = 20;

  Timer? _timer;
  SmartScanQueue? _queue;
  bool _running = false;

  // Unix timestamp بالثوانٍ — آخر وقت عملنا فيه poll
  int _lastCheck = 0;

  // ─── Start ────────────────────────────────────────────────────────────────
  void start(SmartScanQueue queue) {
    if (_running) return;
    _running = true;
    _queue   = queue;

    // ابدأ من آخر 10 دقايق عشان نكتشف الملفات اللي جت أثناء الـ startup
    _lastCheck = DateTime.now()
        .subtract(const Duration(minutes: 10))
        .millisecondsSinceEpoch ~/ 1000;

    // أول poll بعد 30 ث من الـ start
    Timer(const Duration(seconds: 30), () {
      if (!_running) return;
      _poll();
      _timer = Timer.periodic(_pollInterval, (_) => _poll());
    });
  }

  // ─── Stop ─────────────────────────────────────────────────────────────────
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer  = null;
    _queue  = null;
  }

  // ─── Poll يدوي (عند app resume أو من onRepeatEvent) ───────────────────────
  Future<void> pollNow() async {
    if (!_running || _queue == null) return;
    await _poll();
  }

  // ─── Core Poll ────────────────────────────────────────────────────────────
  Future<void> _poll() async {
    if (!_running || _queue == null) return;

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getRecentMedia',
        {
          'sinceTimestamp': _lastCheck,
          'limit'         : _recentLimit,
        },
      );

      // حدّث الـ timestamp قبل المعالجة — حتى لو فيه error في الملفات
      _lastCheck = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (result == null || result.isEmpty) return;

      final paths = result
          .whereType<String>()
          .where(ScanTargets.isMediaFile)
          .toList();

      if (paths.isNotEmpty) {
        _queue!.addBatch(paths, priority: ScanPriority.high);
      }
    } catch (_) {
      // MediaStore مش متاح أو permission ناقصة → تجاهل هادي
    }
  }
}
