import 'package:flutter/material.dart';
import 'package:medi_guard/core/utils/notifications_services.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/main_tab_view.dart';

void main() async {
  // التأكد من تهيئة الـ Flutter Engine قبل استدعاء أي Channel
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة خدمة الإشعارات وبدء الاستماع للأحداث القادمة من الأندرويد
  await NotificationService().init();
  runApp(MuadhApp());
}

class MuadhApp extends StatelessWidget {
  const MuadhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Muadh App',
      home: const MainTabView(),
    );
  }
}
