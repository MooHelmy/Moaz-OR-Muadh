// ignore_for_file: unused_catch_stack

import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
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
// ScanServiceManager
// ─────────────────────────────────────────────
class ScanServiceManager {
  static Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        onlyAlertOnce: true,
        channelImportance: NotificationChannelImportance.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
  }

  static Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'معاذ',
        notificationText: '',
        callback: startScanCallback,
      );
    }

    try {
      await FileObserverChannel.startWatching(ScanTargets.folders);
    } catch (e) {
      // FileObserver failed
    }
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}

// ─────────────────────────────────────────────
// Entry point للـ background isolate
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
void startScanCallback() {
  FlutterForegroundTask.setTaskHandler(ScanTaskHandler());
}

// ─────────────────────────────────────────────
// ScanTaskHandler
// ─────────────────────────────────────────────
class ScanTaskHandler extends TaskHandler {
  ScanQueue? _queue;
  final Battery _battery = Battery();
  bool _ready = false;
  int _lastBatteryCheck = 0;
  bool _isLowBattery = false;
  int repeatCount = 0;

  // ─── onStart ────────────────────────────────
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    await Future.delayed(const Duration(seconds: 8));
    _initializeServices();
  }

  // ─── init ────────────────────────────────
  Future<void> _initializeServices() async {
    try {
      await Hive.initFlutter();
      await Future.wait([
        Hive.openBox('scanned_hashes'),
        Hive.openBox('decisions'),
        Hive.openBox('scan_stats'),
        Hive.openBox('deleted_log'),
      ]);

      // ✅ FIX #1 & #2: NsfwService() بدون Singleton
      //
      // الكود القديم كان بيعمل:
      //   final nsfwService = NsfwService(); // singleton
      //
      // المشكلة:
      //   - الـ Dart isolates لا تشارك الـ heap
      //   - الـ Singleton static field بيتعمل من جديد في كل isolate
      //   - يعني مفيش فايدة من الـ Singleton هنا أصلاً
      //   - لكنه كان بيسبب مشكلة: لو الـ isolate اتوقف وأُعيد تشغيله
      //     → ScanQueue.dispose() استدعى nsfwService.dispose()
      //     → _state = disposed على الـ static instance
      //     → الـ isolate الجديد يلاقي service مقفولة → exception عند initialize()
      //
      // الحل:
      //   NsfwService() عادي — كل isolate يعمل instance نظيفة خاصة به
      final nsfwService = NsfwService();
      await nsfwService.initialize();

      final notifier = ScanNotificationService();
      await notifier.initialize();

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
      _sweepAllFolders();
    } catch (e, stack) {
      // _initializeServices error
    }
  }

  // ─── onReceiveData ────────────────────────
  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    if (!_ready || _queue == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBatteryCheck > 60000) {
      _battery.batteryLevel.then((level) {
        _isLowBattery = level < 20;
        _lastBatteryCheck = now;
      });
      _battery.batteryState.then((state) {
        final isCharging =
            state == BatteryState.charging || state == BatteryState.full;
        if (isCharging) {
          _queue?.resumeHeavyTasks();
        } else if (_isLowBattery) {
          _queue?.pauseHeavyTasks();
        }
      });
    }

    if (_isLowBattery) return;

    if (ScanTargets.isMediaFile(data)) {
      _queue?.add(data, priority: true);
    }
  }

  // ─── onRepeatEvent ────────────────────────
  @override
  void onRepeatEvent(DateTime timestamp) {
    repeatCount++;
  }

  // ─── sweep ────────────────────────────────
  Future<void> _sweepAllFolders() async {
    if (_queue == null) return;

    await Future.delayed(const Duration(seconds: 5));

    final level = await _battery.batteryLevel;
    if (level < 20) return;

    final allFiles = <File>[];

    for (final folder in ScanTargets.folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && ScanTargets.isMediaFile(entity.path)) {
          allFiles.add(entity);
        }
      }
    }

    if (allFiles.isEmpty) return;

    // ✅ FIX #3: إزالة statSync() من داخل sort
    //
    // الكود القديم:
    //   allFiles.sort((a, b) {
    //     final aStat = a.statSync(); // ← blocking I/O × عدد الملفات!
    //     final bStat = b.statSync();
    //     return bStat.modified.compareTo(aStat.modified);
    //   });
    //
    // المشكلة:
    //   - statSync() بيبلوك الـ isolate thread كاملاً لكل ملف
    //   - مع 1000 ملف = 1000 blocking syscalls داخل الـ sort
    //   - الـ sort نفسه O(n log n) يعني كل ملف بيتعمل stat أكتر من مرة
    //   - النتيجة: الـ isolate بيتجمد ويوقف استقبال الملفات الجديدة
    //
    // الحل:
    //   - اعمل stat لكل ملف مرة واحدة بـ Future.wait (async وmتوازي)
    //   - ثم sort على النتائج بدون أي I/O
    final withStats = await Future.wait(
      allFiles.map((f) async {
        try {
          final stat = await f.stat();
          return (file: f, modified: stat.modified);
        } catch (_) {
          // لو stat فشل → تعامل مع الملف كأقدم ملف (يتفحص أخيراً)
          return (file: f, modified: DateTime.fromMillisecondsSinceEpoch(0));
        }
      }),
    );

    withStats.sort((a, b) => b.modified.compareTo(a.modified));

    const batchSize = 50;
    for (int i = 0; i < withStats.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, withStats.length);
      final batch = withStats.sublist(i, end);
      for (final item in batch) {
        _queue!.add(item.file.path);
      }
      if (end < withStats.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // ─── onDestroy ────────────────────────────
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _queue?.dispose();
    _ready = false;
  }
}
