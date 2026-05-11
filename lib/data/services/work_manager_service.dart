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
      frequency: const Duration(hours: 1),
      constraints: Constraints(
        // ✅ Fix: workmanager ^0.7.0 غيّر snake_case لـ camelCase
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: true,
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

  await Hive.openBox('scanned_hashes');

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
      if (entity is File && ScanTargets.isImage(entity.path)) {
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
