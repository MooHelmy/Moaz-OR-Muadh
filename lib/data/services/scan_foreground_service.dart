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
// ScanServiceManager  →  يبدأ/يوقف الـ foreground service
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
        channelImportance:
            NotificationChannelImportance.LOW, // ✅ التسمية الصحيحة لإصدار 9.2.2
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // كل 5 ثواني → sweep fallback
        eventAction:
            ForegroundTaskEventAction.repeat(30000), // كل 30 ثانية للـ log فقط
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
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

    // FileObserver → لازم يشتغل من الـ main isolate (مش من TaskHandler)
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
// ScanTaskHandler  →  يدير عملية الـ scan
// ─────────────────────────────────────────────
class ScanTaskHandler extends TaskHandler {
  ScanQueue? _queue;
  final Battery _battery = Battery();
  bool _ready = false;
  int _lastBatteryCheck = 0;
  bool _isLowBattery = false;
  int repeatCount = 0;
  // ✅ flag عشان الـ sweep الأولي يتعمل مرة واحدة بس

  // ─── onStart ────────────────────────────────
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    _initializeServices();
  }

  // ─── init ────────────────────────────────
  Future<void> _initializeServices() async {
    try {
      await Hive.initFlutter();
      // await Firebase.initializeApp();
      await Future.wait([
        Hive.openBox('scanned_hashes'),
        Hive.openBox('decisions'),
        Hive.openBox('scan_stats'),
        Hive.openBox('deleted_log'),
      ]);

      final nsfwService = NsfwService();
      await nsfwService.initialize(); // يحمّل الـ ONNX model

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

      // ✅ إصلاح: تشغيل المسح الشامل في الخلفية بدون await
      // لكي تظل الخدمة مستعدة لاستقبال الملفات الجديدة فوراً
      _sweepAllFolders();
    } catch (e, stack) {
      // _initializeServices error
    }
  }

  // ─── onReceiveData  ────────────────────────
  // الملفات الجديدة جاية من FileObserver عبر FlutterForegroundTask.sendDataToTask
  @override
  void onReceiveData(Object data) {
    if (data is! String) return;

    if (!_ready || _queue == null) return;

    // ✅ تحسين: فحص البطارية مرة كل 5 دقائق بدلاً من فحصها مع كل ملف
    // لأن استدعاء batteryLevel مكلف ويؤخر الاستجابة
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBatteryCheck > 300000) {
      _battery.batteryLevel.then((level) {
        _isLowBattery = level < 15;
        _lastBatteryCheck = now;
      });
    }

    if (_isLowBattery) {
      return;
    }

    // استخدام isMediaFile لفحص الامتداد وتجاهل الملفات المؤقتة (.pending)
    if (ScanTargets.isMediaFile(data)) {
      _queue?.add(data, priority: true); // ✅ وضعه في مقدمة الطابور فوراً
    }
  }

  // ─── onRepeatEvent  ────────────────────────
  // كل 30 ثانية → فقط للمراقبة والـ log، مش للـ sweep
  @override
  void onRepeatEvent(DateTime timestamp) {
    repeatCount++;
    // ✅ الـ sweep الأولي اتعمل في _initializeServices
    // مش محتاجين نعيده كل 30 ثانية — FileObserver هو اللي بيجيب الجديد
  }

  // ─── sweep ────────────────────────────────
  Future<void> _sweepAllFolders() async {
    if (_queue == null) return;

    // ✅ اجمع كل الملفات من كل الفولدرات
    final allFiles = <File>[];

    for (final folder in ScanTargets.folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;

      // ✅ recursive: true عشان نمسك الفيديوهات في Sent/ وباقي السب-فولدرات
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && ScanTargets.isMediaFile(entity.path)) {
          allFiles.add(entity);
        }
      }
    }

    if (allFiles.isEmpty) return;

    // ✅ رتّب من الأحدث للأقدم (last modified)
    allFiles.sort((a, b) {
      final aStat = a.statSync();
      final bStat = b.statSync();
      return bStat.modified.compareTo(aStat.modified);
    });

    for (final file in allFiles) {
      _queue!.add(file.path);
    }
  }

  // ─── onDestroy ────────────────────────────
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _queue?.dispose();
    _ready = false;
  }
}
