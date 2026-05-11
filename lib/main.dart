import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/data/services/scan_foreground_service.dart';
import 'package:medi_guard/data/services/work_manager_service.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/main_tab_view.dart';
import 'package:medi_guard/feature/media_bloc/presentation/views/permission_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ✅ FIX #1: AppBootstrapper منفصل عن main() — Clean Architecture
class AppBootstrapper {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return; // ✅ FIX #2: منع التهيئة المتكررة
    _initialized = true;

    WidgetsFlutterBinding.ensureInitialized();
    FlutterForegroundTask.initCommunicationPort();

    // ✅ FIX #3: فتح كل Hive Boxes بالتوازي بدلاً من Sequential
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox('scanned_hashes'),
      Hive.openBox('decisions'),
      Hive.openBox('deleted_log'),
      Hive.openBox('scan_stats'), // ✅ صندوق الإحصائيات الجديد
    ]);

    // ✅ FIX #4: compact فقط لو الصندوق كبير (تجنب I/O زائد عند كل launch)
    _compactIfNeeded('scanned_hashes', threshold: 500);
    _compactIfNeeded('decisions', threshold: 200);
    _compactIfNeeded('deleted_log', threshold: 100);

    final notificationService = ScanNotificationService();
    await notificationService.initialize();

    // ✅ FIX #5: WorkManager initialize مرة واحدة فقط
    await WorkManagerService.initialize();
    await WorkManagerService.schedulePeriodicScan();

    await ScanServiceManager.initialize();
  }

  static void _compactIfNeeded(String boxName, {required int threshold}) {
    final box = Hive.box(boxName);
    if (box.length > threshold) {
      box.compact();
    }
  }
}

void main() async {
  await AppBootstrapper.initialize();
  runApp(const ProviderScope(child: MuadhApp()));
}

class MuadhApp extends StatelessWidget {
  const MuadhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'معاذ',
          navigatorKey: navigatorKey,
          // ✅ FIX #6: ScanServiceManager.start() خارج UI callback في Bootstrap
          home: PermissionScreen(
            onGranted: () async {
              await ScanServiceManager.start();
              navigatorKey.currentState?.pushReplacement(
                MaterialPageRoute(builder: (_) => const MainTabView()),
              );
            },
          ),
        );
      },
    );
  }
}
