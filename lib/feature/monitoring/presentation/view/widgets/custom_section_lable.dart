import 'package:flutter/material.dart';

class CustomSectionLabel extends StatelessWidget {
  final String label;
  const CustomSectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.grey[800],
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }
}
