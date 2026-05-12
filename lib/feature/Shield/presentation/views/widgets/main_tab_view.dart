import 'package:flutter/material.dart';
import 'package:medi_guard/core/utils/ai_black_list_service.dart';
import 'package:medi_guard/feature/Progress/presentation/view/monitoring_view.dart';
import 'package:medi_guard/feature/Progress/presentation/view/progress_view.dart';
import 'package:medi_guard/feature/Shield/presentation/views/shield_view.dart';
import 'package:medi_guard/feature/home/presentation/views/home_view.dart';

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // ✅ FIX #20: fetchAndSyncBlacklist مع error handling
    AiBlacklistService.fetchAndSyncBlacklist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ FIX #21: IndexedStack بدلاً من _pages[_currentIndex]
      // يحافظ على state كل tab ومش بيعيد بناءها من الأول
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeView(),
          ShieldView(),
          MonitoringView(),
          ProgressView(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: const Color(0xFF064E3B),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'الرئيسية',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            label: 'الحماية',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'إحصائياتي',
          ),
        ],
      ),
    );
  }
}
