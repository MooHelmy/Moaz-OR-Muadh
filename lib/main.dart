import 'package:flutter/material.dart';

void main() {
  runApp(MuadhApp());
}

class MuadhApp extends StatelessWidget {
  const MuadhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muadh App',
      home: Scaffold(
        appBar: AppBar(title: const Text('Muadh App')),
        body: const Center(child: Text('Welcome to Muadh App!')),
      ),
    );
  }
}
