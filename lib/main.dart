import 'package:flutter/material.dart';
import 'package:muadh/feature/Progress/presentation/view/progress_view.dart';

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
      home: ProgressView(),
    );
  }
}
