// ══════════════════════════════════════════════════════════════════════════════
//  scan_foreground_service.dart
//
//  ✅ FIX CRASH: _pollMediaStore كانت بتتنادى من background isolate
//  الـ MethodChannel مش شغّال من background isolate → كراش فوري
//
//  الحل: MediaStore poll اتنقل للـ main isolate عبر
//  FlutterForegroundTask.sendDataToTask من main.dart
//  والـ TaskHandler بيستقبل النتايج عبر onReceiveData بس
// ══════════════════════════════════════════════════════════════════════════════

import 'package:Muadh/core/constants/scan_targets.dart';
import 'package:Muadh/data/services/face_service.dart';
import 'package:Muadh/data/services/notification_service.dart';
import 'package:Muadh/data/services/nsfw_service.dart';
import 'package:Muadh/data/services/skin_service.dart';
import 'package:Muadh/domain/deletion/delete_manager.dart';
import 'package:Muadh/domain/engines/decision_engine.dart';
import 'package:Muadh/domain/engines/ensemble_scorer.dart';
import 'package:Muadh/domain/scanning/smart_scan_queue.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ── MediaStore channel — يُستخدم من main isolate فقط ─────────────────────────
// ✅ FIX: لازم يتنادى من main isolate مش من TaskHandler
const _mediaStoreChannel = MethodChannel('medi_guard/media_store');

// ══════════════════════════════════════════════════════════════════════════════
//  ScanServiceManager
// ══════════════════════════════════════════════════════════════════════════════
class ScanServiceManager {
  static int _lastMediaPollTs = 0;

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
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<void> start() async {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

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

    // آخر poll = دلوقتي − 6 دقايق عشان أول poll يحصل بعد دقيقة
    _lastMediaPollTs = DateTime.now()
            .subtract(const Duration(minutes: 6))
            .millisecondsSinceEpoch ~/
        1000;
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  // ✅ FIX: الـ MediaStore poll بيتنادى من main isolate (من main.dart)
  // مش من TaskHandler اللي شغّال في background isolate
  static Future<void> pollMediaStoreFromMainIsolate() async {
    try {
      final result = await _mediaStoreChannel.invokeMethod<List<dynamic>>(
        'getRecentMedia',
        {
          'sinceTimestamp': _lastMediaPollTs,
          'limit': 50,
        },
      );

      _lastMediaPollTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (result == null || result.isEmpty) return;

      final paths =
          result.whereType<String>().where(ScanTargets.isMediaFile).toList();

      if (paths.isEmpty) return;

      // بعت للـ background task عبر sendDataToTask
      final batch = 'MEDIA_BATCH:${paths.join('|')}';
      FlutterForegroundTask.sendDataToTask(batch);
    } catch (e) {
      // ✅ مش بيكرش — بيتجاهل الـ error بهدوء
      debugPrint('MediaStore poll error (main isolate): $e');
    }
  }
}

@pragma('vm:entry-point')
void startScanCallback() {
  FlutterForegroundTask.setTaskHandler(ScanTaskHandler());
}

// ══════════════════════════════════════════════════════════════════════════════
//  ScanTaskHandler — بيشتغل في background isolate
//  ✅ FIX: مش بيستخدم MethodChannel هنا خالص
// ══════════════════════════════════════════════════════════════════════════════
class ScanTaskHandler extends TaskHandler {
  SmartScanQueue? _queue;
  final Battery _battery = Battery();

  bool _ready = false;
  bool _isLowBattery = false;
  int _lastBatteryCheckMs = 0;

  // ─── onStart ─────────────────────────────────────────────────────────────
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Future.delayed(const Duration(seconds: 5));
    await _init();
  }

  // ─── onReceiveData — FileObserver + MediaStore events ────────────────────
  // كل البيانات بتيجي من main isolate عبر sendDataToTask
  // ✅ FIX: مفيش MethodChannel هنا — بس نستقبل data
  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    if (!_ready || _queue == null) return;
    if (_isLowBattery) return;

    // MediaStore batch: "MEDIA_BATCH:path1|path2|path3"
    if (data.startsWith('MEDIA_BATCH:')) {
      final paths = data.substring(12).split('|').where((p) => p.isNotEmpty);
      for (final path in paths) {
        if (ScanTargets.isMediaFile(path)) {
          _queue!.add(path, priority: ScanPriority.high);
        }
      }
      return;
    }

    // FileObserver event: path مباشر
    if (ScanTargets.isMediaFile(data)) {
      _queue!.add(data, priority: ScanPriority.realtime);
    }
  }

  // ─── onRepeatEvent — كل دقيقة ────────────────────────────────────────────
  // ✅ FIX: مش بنعمل MethodChannel هنا — بس battery check
  // الـ MediaStore poll بيتعمل من main isolate عبر pollMediaStoreFromMainIsolate
  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkBattery();
    // ✅ لا يوجد _pollMediaStore() هنا — تم نقله للـ main isolate
  }

  // ─── onDestroy ────────────────────────────────────────────────────────────
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _queue?.dispose();
    _ready = false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  INIT — في background isolate
  //  ✅ FIX: مفيش MethodChannel في الـ init
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

      final nsfw = NsfwService();
      await nsfw.initialize();

      final notifier = ScanNotificationService();
      await notifier.initialize();

      _queue = SmartScanQueue(
        scorer: EnsembleScorer(
          nsfwService: nsfw,
          faceService: FaceService(),
          skinService: SkinService(),
        ),
        engine: DecisionEngine(),
        deleteManager: DeleteManager(),
        notifier: notifier,
        maxWorkers: 2,
      );

      _ready = true;
    } catch (e) {
      debugPrint('ScanTaskHandler init error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BATTERY CHECK
  // ══════════════════════════════════════════════════════════════════════════
  void _checkBattery() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBatteryCheckMs < 60000) return;
    _lastBatteryCheckMs = now;

    _battery.batteryLevel.then((level) {
      _isLowBattery = level < 5;
      if (_isLowBattery) _queue?.pause();
    });

    _battery.batteryState.then((state) {
      final charging =
          state == BatteryState.charging || state == BatteryState.full;
      if (charging) {
        _isLowBattery = false;
        _queue?.resume();
      }
    });
  }
}
