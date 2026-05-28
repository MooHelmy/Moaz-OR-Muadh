import 'package:Muadh/core/theme/themes.dart';
import 'package:flutter/material.dart';

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
