import 'package:flutter/material.dart';
import 'package:muadh/core/themes.dart';
import 'package:muadh/feature/home/presentation/views/widgets/emergency_button.dart';
import 'package:muadh/feature/home/presentation/views/widgets/home_view_body.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: EmergencyButton(
        onPressed: () {
          // TODO: Add emergency flow
        },
      ),
      body: HomeViewBody(),
    );
  }
}
// _pages[_currentIndex],
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: _currentIndex,
//         onTap: (index) => setState(() => _currentIndex = index),
//         selectedItemColor: Color(0xFF064E3B),
//         unselectedItemColor: Colors.grey,
//         type: BottomNavigationBarType.fixed,
//         items: [
//           BottomNavigationBarItem(
//             icon: Icon(Icons.home_filled),
//             label: 'الرئيسية',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.shield_outlined),
//             label: 'الحماية',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.bar_chart_rounded),
//             label: 'إحصائياتي',
//           ),
//         ],
//       ),
//     );
//   }
// }