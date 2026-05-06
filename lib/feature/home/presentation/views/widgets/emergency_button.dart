import 'package:flutter/material.dart';
import 'package:medi_guard/core/theme/themes.dart';

class EmergencyButton extends StatelessWidget {
  final VoidCallback onPressed;

  const EmergencyButton({required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: AppTheme.dangerRed,
      onPressed: onPressed,
      child: Icon(Icons.warning),
    );
  }
}
