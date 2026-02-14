import 'package:flutter/material.dart';

class CustomSectionTitel extends StatelessWidget {
  final String title;
  const CustomSectionTitel({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 8, top: 10),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[700],
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
