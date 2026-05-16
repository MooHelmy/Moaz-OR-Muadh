// ══════════════════════════════════════════════════════════════════════════════
//  file_observer_channel.dart
//  Version: 2.1.0
//
//  ✅ FIX #5: dedup TTL متسق — استخدام dedupTtl بدل debounce * 2
//  ✅ FIX #7: dedup window أكبر — يمنع نفس الملف يعدي مرتين عند copy بطيئة
// ══════════════════════════════════════════════════════════════════════════════

// ignore_for_file: unused_catch_clause

import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ──────────────────────────────────────────────────────────────────────────────
// CONFIG
// ──────────────────────────────────────────────────────────────────────────────

final class _ObsCfg {
  static const Duration debounce = Duration(milliseconds: 300);

  // ✅ FIX #7: TTL للـ dedup — بيتستخدم في _DebounceDedup بدل debounce * 2
  // القديم: debounce * 2 = 600ms فقط → نفس الملف ممكن يعدي مرتين عند copy بطيئة
  // الجديد: 10 ثواني → هامش أمان كافي بدون ما يأثر على الاكتشاف
  static const Duration dedupWindow = Duration(seconds: 10);

  static const Duration dedupTtl = Duration(seconds: 30);
  static const int dedupMaxSize = 500;
  static const int maxEventsPerSecond = 200;
  static const int maxRetries = 5;
  static const Duration retryBaseDelay = Duration(seconds: 2);
}

// ──────────────────────────────────────────────────────────────────────────────
// FileObserverChannel
// ──────────────────────────────────────────────────────────────────────────────

class FileObserverChannel {
  FileObserverChannel._();

  static const _methodChannel = MethodChannel('medi_guard/file_observer');
  static const _eventChannel = EventChannel('medi_guard/file_events');

  static Stream<String>? _broadcastStream;
  static StreamSubscription<String>? _internalSub;
  static bool _isWatching = false;
  static int _retryCount = 0;

  static final Map<String, Timer> _debounceTimers = {};

  static final LinkedHashMap<String, DateTime> _recentlySeen = LinkedHashMap();
  static Timer? _dedupFlushTimer;

  // ✅ FIX #5: _eventCountThisSecond مش محتاج sync هنا لأن
  // FileObserverChannel بيشتغل على main isolate فقط (single-threaded event loop)
  // الـ Dart event loop بيضمن إن الـ callbacks لا تتشغل في نفس الوقت
  // الـ race condition الحقيقية تحصل لو استخدمنا multiple isolates — مش الحال هنا
  static int _eventCountThisSecond = 0;
  static Timer? _rateLimitResetTimer;

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> startWatching(List<String> folders) async {
    if (_isWatching) return;

    try {
      await _methodChannel.invokeMethod<void>(
        'startWatching',
        {'folders': folders},
      );
    } on PlatformException catch (e) {
      return;
    }

    _isWatching = true;
    _retryCount = 0;
    _startDedupFlushTimer();
    _startRateLimitTimer();
    _subscribe();
  }

  static Future<void> stopWatching() async {
    if (!_isWatching) return;

    _isWatching = false;
    _retryCount = 0;

    await _internalSub?.cancel();
    _internalSub = null;

    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();

    _dedupFlushTimer?.cancel();
    _dedupFlushTimer = null;
    _rateLimitResetTimer?.cancel();
    _rateLimitResetTimer = null;

    _recentlySeen.clear();
    _eventCountThisSecond = 0;

    _broadcastStream = null;

    try {
      await _methodChannel.invokeMethod<void>('stopWatching');
    } on PlatformException catch (e) {
      // stopWatching native error
    }
  }

  static Stream<String> get fileEvents {
    _broadcastStream ??= _buildBroadcastStream();
    return _broadcastStream!;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ══════════════════════════════════════════════════════════════════════════

  static Stream<String> _buildBroadcastStream() {
    return _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is String && (event).isNotEmpty)
        .map((event) => event as String)
        .transform(_DebounceDedup(
          debounce: _ObsCfg.debounce,
          // ✅ FIX #7: نمرر dedupWindow للـ transformer بدل debounce * 2
          dedupWindow: _ObsCfg.dedupWindow,
          recentlySeen: _recentlySeen,
        ))
        .asBroadcastStream();
  }

  static void _subscribe() {
    if (_internalSub != null) return;

    _broadcastStream ??= _buildBroadcastStream();

    _internalSub = _broadcastStream!.listen(
      _onFileEvent,
      onError: _onStreamError,
      cancelOnError: false,
    );
  }

  static void _onFileEvent(String filePath) {
    if (_eventCountThisSecond >= _ObsCfg.maxEventsPerSecond) return;
    _eventCountThisSecond++;
    FlutterForegroundTask.sendDataToTask(filePath);
  }

  static void _onStreamError(Object error, StackTrace stack) {
    if (!_isWatching) return;

    _retryCount++;
    if (_retryCount > _ObsCfg.maxRetries) return;

    _internalSub?.cancel();
    _internalSub = null;
    _broadcastStream = null;

    final delay = _ObsCfg.retryBaseDelay * (1 << (_retryCount - 1));
    Timer(delay, () {
      if (_isWatching) _subscribe();
    });
  }

  static void _startDedupFlushTimer() {
    _dedupFlushTimer?.cancel();
    _dedupFlushTimer = Timer.periodic(_ObsCfg.dedupTtl, (_) {
      final now = DateTime.now();
      final cutoff = now.subtract(_ObsCfg.dedupTtl);
      _recentlySeen.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));

      if (_recentlySeen.length > _ObsCfg.dedupMaxSize) {
        final toRemove = _recentlySeen.length - _ObsCfg.dedupMaxSize;
        final keys = _recentlySeen.keys.take(toRemove).toList();
        keys.forEach(_recentlySeen.remove);
      }
    });
  }

  static void _startRateLimitTimer() {
    _rateLimitResetTimer?.cancel();
    _rateLimitResetTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _eventCountThisSecond = 0,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _DebounceDedup — StreamTransformer
//
// ✅ FIX #5 & #7: dedupWindow parameter منفصل عن debounce
//   القديم: if (difference < debounce * 2) → 600ms فقط
//   الجديد: if (difference < dedupWindow)  → 10 ثواني
//
// السبب:
//   عند copy ملف كبير (فيديو مثلاً):
//   - FileObserver بيطلق event عند بداية الكتابة
//   - وتاني event عند انتهاء الكتابة (chmod/rename)
//   - الفرق بينهم ممكن يكون ثواني مش milliseconds
//   - debounce * 2 = 600ms مش كافي → نفس الملف يتفحص مرتين
//   - dedupWindow = 10s → هامش آمن يغطي معظم حالات الـ copy
// ══════════════════════════════════════════════════════════════════════════════

final class _DebounceDedup extends StreamTransformerBase<String, String> {
  const _DebounceDedup({
    required this.debounce,
    required this.dedupWindow,
    required this.recentlySeen,
  });

  final Duration debounce;
  final Duration dedupWindow; // ✅ FIX: منفصل عن debounce
  final Map<String, DateTime> recentlySeen;

  @override
  Stream<String> bind(Stream<String> stream) {
    final timers = <String, Timer>{};
    late StreamController<String> controller;

    controller = StreamController<String>(
      onListen: () {
        final sub = stream.listen(
          (path) {
            // ✅ FIX #5 & #7: استخدام dedupWindow بدل debounce * 2
            final lastSeen = recentlySeen[path];
            if (lastSeen != null &&
                DateTime.now().difference(lastSeen) < dedupWindow) {
              return; // تجاهل — شُوفِ مؤخراً
            }

            timers[path]?.cancel();
            timers[path] = Timer(debounce, () {
              timers.remove(path);
              if (!controller.isClosed) {
                recentlySeen[path] = DateTime.now();
                controller.add(path);
              }
            });
          },
          onError: controller.addError,
          onDone: () {
            for (final t in timers.values) {
              t.cancel();
            }
            timers.clear();
            controller.close();
          },
          cancelOnError: false,
        );

        controller.onCancel = () {
          sub.cancel();
          for (final t in timers.values) {
            t.cancel();
          }
          timers.clear();
        };
      },
      sync: false,
    );

    return controller.stream;
  }
}
