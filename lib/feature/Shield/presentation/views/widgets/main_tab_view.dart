import 'package:flutter/material.dart';
import 'package:muadh/core/ai_black_list_service.dart';
import 'package:muadh/feature/Progress/presentation/view/progress_view.dart';
import 'package:muadh/feature/Shield/presentation/views/shield_view.dart';
import 'package:muadh/feature/home/presentation/views/home_view.dart';

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const HomeView(),
    const ShieldView(),
    const ProgressView(),
  ];

  @override
  void initState() {
    super.initState();
    AiBlacklistService.fetchAndSyncBlacklist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
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
