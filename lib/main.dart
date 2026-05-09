import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:medi_guard/data/services/notification_service.dart';
import 'package:medi_guard/data/services/scan_foreground_service.dart';
import 'package:medi_guard/data/services/work_manager_service.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/main_tab_view.dart';
import 'package:medi_guard/feature/media_bloc/presentation/views/permission_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.initCommunicationPort();

  await Hive.initFlutter();
  await Hive.openBox('scanned_hashes');
  await Hive.openBox('decisions');

  // ✅ compact عند كل بدء للتطبيق عشان المساحة
  Hive.box('scanned_hashes').compact();
  Hive.box('decisions').compact();

  await Firebase.initializeApp();

  final notificationService = ScanNotificationService();
  await notificationService.initialize();

  await WorkManagerService.initialize();
  await WorkManagerService.schedulePeriodicScan();

  await ScanServiceManager.initialize();

  runApp(const ProviderScope(child: MuadhApp()));
}

class MuadhApp extends StatelessWidget {
  const MuadhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'معاذ',
      navigatorKey: navigatorKey,
      home: PermissionScreen(
        onGranted: () async {
          await ScanServiceManager.start();
          navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => const MainTabView()),
          );
        },
      ),
    );
  }
}
