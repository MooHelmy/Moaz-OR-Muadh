// ══════════════════════════════════════════════════════════════════════════════
//  scan_foreground_service.dart
//
//  المعمارية:
//    FileObserver   → realtime priority → فوري (ملف جديد أو اتنقل)
//    MediaStore     → high priority    → كل 5 دقايق عبر onRepeatEvent
//
//  مفيش Initial Sweep — بنفحص الجديد بس
//  مفيش WorkManager — مش محتاجينه
// ══════════════════════════════════════════════════════════════════════════════

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
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
import 'package:medi_guard/domain/scanning/smart_scan_queue.dart';

// ── MediaStore channel — يُستخدم من onRepeatEvent (main isolate) فقط ─────────
const _mediaStoreChannel = MethodChannel('medi_guard/media_store');

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
        // كل دقيقة — للـ battery check والـ MediaStore poll
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
  SmartScanQueue? _queue;
  final Battery _battery = Battery();

  bool _ready = false;
  bool _isLowBattery = false;
  int _lastBatteryCheckMs = 0;
  int _repeatCount = 0;

  // آخر timestamp عملنا فيه MediaStore poll (unix seconds)
  int _lastMediaPollTs = 0;

  // ─── onStart ─────────────────────────────────────────────────────────────
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Future.delayed(const Duration(seconds: 8));
    await _init();
  }

  // ─── onReceiveData — FileObserver events ─────────────────────────────────
  // كل message من FileObserver أو MediaStore بتيجي هنا
  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    if (!_ready || _queue == null) return;
    if (_isLowBattery) return;

    // فورمات الـ MediaStore batch: "MEDIA_BATCH:path1|path2|path3"
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
  @override
  void onRepeatEvent(DateTime timestamp) {
    _repeatCount++;
    _checkBattery();

    if (!_ready || _queue == null || _isLowBattery) return;

    // كل 5 دقايق → MediaStore poll
    // onRepeatEvent بيشتغل على main isolate → الـ channel شغّال
    if (_repeatCount % 5 == 0) {
      _pollMediaStore();
    }
  }

  // ─── onDestroy ────────────────────────────────────────────────────────────
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
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

      // آخر poll = دلوقتي − 6 دقايق عشان أول poll يحصل بعد دقيقة من الـ start
      _lastMediaPollTs = DateTime.now()
              .subtract(const Duration(minutes: 6))
              .millisecondsSinceEpoch ~/
          1000;

      _ready = true;
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MEDIA STORE POLL
  //  بيشتغل من onRepeatEvent (main isolate) → الـ channel شغّال هنا
  //  بيبعت النتايج للـ background task عبر sendDataToTask
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _pollMediaStore() async {
    try {
      final result = await _mediaStoreChannel.invokeMethod<List<dynamic>>(
        'getRecentMedia',
        {
          'sinceTimestamp': _lastMediaPollTs,
          'limit': 30,
        },
      );

      _lastMediaPollTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (result == null || result.isEmpty) return;

      final paths =
          result.whereType<String>().where(ScanTargets.isMediaFile).toList();

      if (paths.isEmpty) return;

      // بعت الـ paths للـ background task عبر sendDataToTask
      // onReceiveData هيستقبلهم ويضيفهم بـ high priority
      final batch = 'MEDIA_BATCH:${paths.join('|')}';
      FlutterForegroundTask.sendDataToTask(batch);
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BATTERY CHECK — مرة كل دقيقة بس
  // ══════════════════════════════════════════════════════════════════════════
  void _checkBattery() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBatteryCheckMs < 60000) return;
    _lastBatteryCheckMs = now;

    _battery.batteryLevel.then((level) {
      _isLowBattery = level < 10;
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
