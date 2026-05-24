import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/core/constants/scan_targets.dart';
import 'package:medi_guard/core/theme/app_theme.dart';
import 'package:medi_guard/core/theme/theme_provider.dart';
import 'package:medi_guard/data/services/file_observer_channel.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/data/services/scan_foreground_service.dart';
import 'package:medi_guard/feature/media_bloc/presentation/views/permission_screen.dart';
import 'package:medi_guard/feature/splash/presentation/view/splash_view.dart';
import 'package:permission_handler/permission_handler.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class AppBootstrapper {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsFlutterBinding.ensureInitialized();
    FlutterForegroundTask.initCommunicationPort();

    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox('scanned_hashes'),
      Hive.openBox('decisions'),
      Hive.openBox('deleted_log'),
      Hive.openBox('scan_stats'),
    ]);

    _compactIfNeeded('scanned_hashes', threshold: 300);
    _compactIfNeeded('decisions', threshold: 100);
    _compactIfNeeded('deleted_log', threshold: 50);
    _pruneOldHashes();

    // ✅ طلب إذن Overlay عند أول فتح للتطبيق
    await _requestOverlayPermission();

    final notificationService = ScanNotificationService();
    await notificationService.initialize();

    await ScanServiceManager.initialize();

    const EventChannel('medi_guard/scan_file')
        .receiveBroadcastStream()
        .listen((dynamic data) {
      if (data is String && data.isNotEmpty) {
        FlutterForegroundTask.sendDataToTask(data);
      }
    });
  }

  static Future<void> _requestOverlayPermission() async {
    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }
  }

  static void _compactIfNeeded(String boxName, {required int threshold}) {
    final box = Hive.box(boxName);
    if (box.length > threshold) {
      box.compact();
    }
  }

  static void _pruneOldHashes() {
    try {
      const maxHashes = 3000;
      final box = Hive.box('scanned_hashes');
      if (box.length <= maxHashes) return;
      final toDelete = box.length - maxHashes;
      final keys = box.keys.take(toDelete).toList();
      box.deleteAll(keys);
      box.compact();
    } catch (_) {}
  }
}

void main() async {
  await AppBootstrapper.initialize();
  runApp(const ProviderScope(child: MuadhApp()));
}

class MuadhApp extends ConsumerWidget {
  const MuadhApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeNotifierProvider);

    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'معاذ',
          navigatorKey: navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: isDarkMode ? ThemeMode.light : ThemeMode.dark,
          home: PermissionScreen(
            onGranted: (showAccessibilityOnboarding) async {
              await FileObserverChannel.startWatching(ScanTargets.folders);
              await ScanServiceManager.start();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                navigatorKey.currentState?.pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => SplashView(
                      showAccessibilityOnboarding: showAccessibilityOnboarding,
                    ),
                  ),
                );
              });
            },
          ),
        );
      },
    );
  }
}
