import 'package:flutter/material.dart';
import 'package:medi_guard/core/utils/ai_black_list_service.dart';
import 'package:medi_guard/feature/Shield/presentation/views/shield_view.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/accessibility_dialog.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/shield_channel.dart';
import 'package:medi_guard/feature/home/presentation/views/home_view.dart';
import 'package:medi_guard/feature/monitoring/presentation/view/monitoring_view.dart';

class MainTabView extends StatefulWidget {
  final int initialIndex;
  final bool showAccessibilityPrompt;

  const MainTabView({
    super.key,
    this.initialIndex = 0,
    this.showAccessibilityPrompt = false,
  });

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // ✅ FIX #20: fetchAndSyncBlacklist مع error handling
    AiBlacklistService.fetchAndSyncBlacklist();

    if (widget.showAccessibilityPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAccessibilityOnboarding();
      });
    }
  }

  void _showAccessibilityOnboarding() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => MaadhAccessDialog(
        onConfirm: () {
          MaadhShieldManager.requestAccessibility();
        },
      ),
    );
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
