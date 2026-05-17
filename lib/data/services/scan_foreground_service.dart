// ══════════════════════════════════════════════════════════════════════════════
//  scan_foreground_service.dart  —  v2.0
//
//  المعمارية الجديدة:
//    FileObserver   → realtime priority → فوري
//    MediaStore     → high priority    → كل 5 دقايق
//    InitialSweep   → normal priority  → مرة واحدة عند الـ start
//
//  الـ 3 موديلات (NSFW + Skin + Face) بتشتغل على كل ملف
//  بـ SmartScanQueue اللي بتوزع الشغل بشكل ذكي
// ══════════════════════════════════════════════════════════════════════════════

// ignore_for_file: unused_catch_stack

import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/data/services/face_service.dart';
import 'package:medi_guard/data/services/file_observer_channel.dart';
import 'package:medi_guard/data/services/media_store_poller.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/data/services/nsfw_service.dart';
import 'package:medi_guard/data/services/skin_service.dart';
import 'package:medi_guard/domain/deletion/delete_manager.dart';
import 'package:medi_guard/domain/engines/decision_engine.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';
import 'package:medi_guard/domain/scanning/smart_scan_queue.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  ScanServiceManager
// ══════════════════════════════════════════════════════════════════════════════
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
        eventAction: ForegroundTaskEventAction.repeat(60000), // كل دقيقة
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

    // FileObserver للكشف الفوري عن الملفات الجديدة
    try {
      await FileObserverChannel.startWatching(ScanTargets.folders);
    } catch (_) {}
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void startScanCallback() {
  FlutterForegroundTask.setTaskHandler(ScanTaskHandler());
}

// ══════════════════════════════════════════════════════════════════════════════
//  ScanTaskHandler
// ══════════════════════════════════════════════════════════════════════════════
class ScanTaskHandler extends TaskHandler {
  SmartScanQueue?  _queue;
  MediaStorePoller? _poller;
  final Battery _battery = Battery();

  bool _ready             = false;
  bool _isLowBattery      = false;
  bool _initialSweepDone  = false;
  int  _lastBatteryCheckMs = 0;
  int  _repeatCount       = 0;

  // ─── onStart ─────────────────────────────────────────────────────────────
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // ننتظر 8 ث عشان الجهاز يستقر بعد boot/restart
    await Future.delayed(const Duration(seconds: 8));
    await _init();
  }

  // ─── onReceiveData (FileObserver events) ─────────────────────────────────
  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    if (!_ready || _queue == null) return;

    _checkBattery();
    if (_isLowBattery) return;

    if (ScanTargets.isMediaFile(data)) {
      // ملف جديد من FileObserver → realtime → فحص فوري
      _queue!.add(data, priority: ScanPriority.realtime);
    }
  }

  // ─── onRepeatEvent (كل دقيقة) ────────────────────────────────────────────
  @override
  void onRepeatEvent(DateTime timestamp) {
    _repeatCount++;
    _checkBattery();

    if (!_ready || _queue == null || _isLowBattery) return;

    // كل 10 دقايق → poll MediaStore يدوي (backup للـ timer)
    if (_repeatCount % 10 == 0) {
      _poller?.pollNow();
    }
  }

  // ─── onDestroy ────────────────────────────────────────────────────────────
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _poller?.stop();
    await _queue?.dispose();
    _ready = false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  INIT
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _init() async {
    try {
      await Hive.initFlutter();
      await Future.wait([
        Hive.openBox('scanned_hashes'),
        Hive.openBox('decisions'),
        Hive.openBox('scan_stats'),
        Hive.openBox('deleted_log'),
      ]);

      final nsfw     = NsfwService();
      await nsfw.initialize();

      final notifier = ScanNotificationService();
      await notifier.initialize();

      _queue = SmartScanQueue(
        scorer: EnsembleScorer(
          nsfwService: nsfw,
          faceService: FaceService(),
          skinService: SkinService(),
        ),
        engine       : DecisionEngine(),
        deleteManager: DeleteManager(),
        notifier     : notifier,
        maxWorkers   : 2,
      );

      // ─── MediaStore Poller ─────────────────────────────────────────────
      _poller = MediaStorePoller()..start(_queue!);

      _ready = true;

      // ─── Initial Sweep ─────────────────────────────────────────────────
      // بعد 15 ث من الـ start — بأولوية normal
      Future.delayed(const Duration(seconds: 15), _initialSweep);

    } catch (e) {
      // init failed — الـ service ستحاول تاني في أول event
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  INITIAL SWEEP — مرة واحدة عند الـ start
  //  بيفحص كل الملفات بأولوية normal (أقل أولوية)
  //  يتوقف لو Battery < 20%
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _initialSweep() async {
    if (_initialSweepDone || _queue == null) return;
    _initialSweepDone = true;

    final level = await _battery.batteryLevel;
    if (level < 20) return;

    final allFiles = <File>[];

    for (final folder in ScanTargets.folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true)) {
        if (e is File && ScanTargets.isMediaFile(e.path)) {
          allFiles.add(e);
        }
      }
    }

    if (allFiles.isEmpty) return;

    // Sort: الأحدث أولاً — لو المستخدم ضاف حاجة جديدة تتفحص الأول
    final withStats = await Future.wait(
      allFiles.map((f) async {
        try {
          final s = await f.stat();
          return (file: f, modified: s.modified);
        } catch (_) {
          return (file: f, modified: DateTime.fromMillisecondsSinceEpoch(0));
        }
      }),
    );
    withStats.sort((a, b) => b.modified.compareTo(a.modified));

    // أضف بـ batches من 50 — pause 500ms بين كل batch
    // عشان ما نسرقش الـ CPU من الـ realtime/high events
    const batchSize = 50;
    for (int i = 0; i < withStats.length; i += batchSize) {
      if (_isLowBattery || _queue == null) break;
      final end = (i + batchSize).clamp(0, withStats.length);
      for (final item in withStats.sublist(i, end)) {
        _queue!.add(item.file.path, priority: ScanPriority.normal);
      }
      if (end < withStats.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BATTERY CHECK
  // ══════════════════════════════════════════════════════════════════════════
  void _checkBattery() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBatteryCheckMs < 60000) return; // مرة كل دقيقة بس
    _lastBatteryCheckMs = now;

    _battery.batteryLevel.then((level) {
      _isLowBattery = level < 20;
      if (_isLowBattery) _queue?.pause();
    });

    _battery.batteryState.then((state) {
      final charging = state == BatteryState.charging || state == BatteryState.full;
      if (charging) {
        _isLowBattery = false;
        _queue?.resume();
      }
    });
  }
}
