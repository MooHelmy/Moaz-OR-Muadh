import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/data/services/face_service.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/data/services/nsfw_service.dart';
import 'package:medi_guard/data/services/skin_service.dart';
import 'package:medi_guard/domain/deletion/delete_manager.dart';
import 'package:medi_guard/domain/engines/decision_engine.dart';
import 'package:medi_guard/domain/engines/ensemble_scorer.dart';
import 'package:medi_guard/domain/scanning/scan_queue.dart';
import 'package:workmanager/workmanager.dart';

class WorkManagerService {
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> schedulePeriodicScan() async {
    await Workmanager().registerPeriodicTask(
      'periodic_deep_scan',
      'deepScanTask',
      // ✅ OPT: كل 6 ساعات بدل ساعة — FileObserver بيغطي الجديد فوراً
      // الـ deep scan للملفات اللي فاتت بس — مش لازم كل ساعة
      frequency: const Duration(hours: 6),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: true,
        requiresDeviceIdle: true, // ✅ OPT: يشتغل فقط لما الجهاز مش مستخدم
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'deepScanTask') {
      await _runDeepScan();
    }
    return Future.value(true);
  });
}

Future<void> _runDeepScan() async {
  await Hive.initFlutter();

  // ✅ OPT: فتح كل الـ boxes المطلوبة — نفس الـ main app
  await Future.wait([
    Hive.openBox('scanned_hashes'),
    Hive.openBox('decisions'),
    Hive.openBox('scan_stats'),
    Hive.openBox('deleted_log'),
  ]);

  final nsfwService = NsfwService();
  await nsfwService.initialize();

  final notificationService = ScanNotificationService();
  await notificationService.initialize();

  final queue = ScanQueue(
    scorer: EnsembleScorer(
      nsfwService: nsfwService,
      faceService: FaceService(),
      skinService: SkinService(),
    ),
    engine: DecisionEngine(),
    deleteManager: DeleteManager(),
    notifier: notificationService,
  );

  for (final folder in ScanTargets.folders) {
    final dir = Directory(folder);
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(recursive: true)) {
      // ✅ فحص الصور فقط لتجنب أخطاء الـ Decode في الفيديوهات
      // ✅ FIX: isMediaFile بدل isImage — يشمل الفيديوهات أيضاً
      if (entity is File && ScanTargets.isMediaFile(entity.path)) {
        queue.add(entity.path);
      }
    }
  }

  // ✅ انتظار اكتمال الـ queue قبل الـ dispose
  // WorkManager task لازم ينتهي صح عشان الموارد تتحرر
  while (queue.isProcessing || queue.pendingCount > 0) {
    await Future.delayed(const Duration(milliseconds: 500));
  }
  await queue.dispose();
}
