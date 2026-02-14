import 'package:flutter/material.dart';
import 'package:muadh/feature/home/presentation/views/home_view.dart';

void main() {
  runApp(MuadhApp());
}

class MuadhApp extends StatelessWidget {
  const MuadhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Muadh App', home: HomeView());
  }
}
