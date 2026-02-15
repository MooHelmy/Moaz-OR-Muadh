import 'package:flutter/material.dart';
import 'package:muadh/feature/Shield/presentation/views/widgets/main_tab_view.dart';

void main() {
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
