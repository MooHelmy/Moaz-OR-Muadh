import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/data/services/face_service.dart';
import 'package:medi_guard/data/services/file_observer_channel.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/data/services/nsfw_service.dart';
import 'package:medi_guard/data/services/skin_service.dart';
import 'package:medi_guard/domain/deletion/delete_manager.dart';
import 'package:medi_guard/domain/engines/decision_engine.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';
import 'package:medi_guard/domain/scanning/scan_queue.dart';

// ─────────────────────────────────────────────
// ScanServiceManager  →  يبدأ/يوقف الـ foreground service
// ─────────────────────────────────────────────
class ScanServiceManager {
  static Future<void> initialize() async {
    debugPrint('🔧 ScanServiceManager: initializing...');
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // كل 5 ثواني → sweep fallback
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    debugPrint('✅ ScanServiceManager: initialized');
  }

  static Future<void> start() async {
    debugPrint('🚀 ScanServiceManager: starting...');

    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('♻️ Already running → restart');
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'معاذ',
        notificationText: 'يحمي جهازك من المحتوى الإباحي',
        callback: startScanCallback,
      );
      debugPrint('✅ Foreground service started');
    }

    // FileObserver → لازم يشتغل من الـ main isolate (مش من TaskHandler)
    try {
      await FileObserverChannel.startWatching(ScanTargets.folders);
      debugPrint(
          '✅ FileObserver watching ${ScanTargets.folders.length} folders');
    } catch (e) {
      debugPrint('⚠️ FileObserver failed: $e');
    }
  }

  static Future<void> stop() async {
    debugPrint('🛑 Stopping foreground service...');
    await FlutterForegroundTask.stopService();
  }
}

// ─────────────────────────────────────────────
// Entry point للـ background isolate
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
void startScanCallback() {
  debugPrint('📡 startScanCallback: setting task handler');
  FlutterForegroundTask.setTaskHandler(ScanTaskHandler());
}

// ─────────────────────────────────────────────
// ScanTaskHandler  →  يدير عملية الـ scan
// ─────────────────────────────────────────────
class ScanTaskHandler extends TaskHandler {
  ScanQueue? _queue;
  bool _ready = false;
  int _repeatCount = 0;

  // ANSI colors للـ debug log
  static const reset = '\x1B[0m';
  static const red = '\x1B[31m';
  static const green = '\x1B[32m';
  static const yellow = '\x1B[33m';
  static const blue = '\x1B[34m';

  // ─── onStart ────────────────────────────────
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    debugPrint('▶️ ScanTaskHandler.onStart at $timestamp');
    // لا ننتظر — عشان الـ service ميتايمأوتش
    _initializeServices();
  }

  // ─── init ────────────────────────────────
  Future<void> _initializeServices() async {
    try {
      await Hive.initFlutter();
      await Firebase.initializeApp();
      await Hive.openBox('scanned_hashes');
      await Hive.openBox('decisions');
      debugPrint('✅ Hive + Firebase ready');

      final nsfwService = NsfwService();
      await nsfwService.initialize(); // يحمّل الـ ONNX model
      debugPrint('✅ NsfwService ready');

      final notifier = ScanNotificationService();
      await notifier.initialize();
      debugPrint('✅ NotificationService ready');

      _queue = ScanQueue(
        scorer: EnsembleScorer(
          nsfwService: nsfwService,
          faceService: FaceService(),
          skinService: SkinService(),
        ),
        engine: DecisionEngine(),
        deleteManager: DeleteManager(),
        notifier: notifier,
      );

      _ready = true;
      debugPrint('✅ ScanQueue ready — listening for files');

      // ← اسكان أولي فور الجهوزية
      await _sweepAllFolders();
    } catch (e, stack) {
      debugPrint('❌ _initializeServices ERROR: $e\n$stack');
    }
  }

  // ─── onReceiveData  ────────────────────────
  // الملفات الجديدة جاية من FileObserver عبر FlutterForegroundTask.sendDataToTask
  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    debugPrint('📩 onReceiveData → $data');

    if (!_ready) {
      debugPrint('⚠️ Queue not ready yet — skipping $data');
      return;
    }

    if (ScanTargets.isImage(data)) {
      debugPrint('📥 Queuing: $data');
      _queue!.add(data);
    } else {
      debugPrint('⏭️ Not an image → skipped');
    }
  }

  // ─── onRepeatEvent  ────────────────────────
  // كل 5 ثواني → sweep fallback عشان نمسك الملفات اللي فاتت
  @override
  void onRepeatEvent(DateTime timestamp) {
    _repeatCount++;
    debugPrint(
      '🔁 #$_repeatCount | ready=$_ready'
      ' | queue=${_queue?.pendingCount ?? "N/A"}'
      ' | processing=${_queue?.isProcessing ?? "N/A"}',
    );

    if (!_ready) return;
    _sweepAllFolders();
  }

  // ─── sweep ────────────────────────────────
  Future<void> _sweepAllFolders() async {
    if (_queue == null) return;
    int found = 0;

    for (final folder in ScanTargets.folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: false)) {
        if (entity is File && ScanTargets.isImage(entity.path)) {
          found++;
          _queue!.add(entity.path);
        }
      }
    }

    if (found > 0) {
      debugPrint(
          '🔍 Sweep: $found files queued from ${ScanTargets.folders.length} folders');
    }
  }

  // ─── onDestroy ────────────────────────────
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('🔴 onDestroy — isTimeout=$isTimeout');
    await _queue?.dispose();
    _ready = false;
  }
}
