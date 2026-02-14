import 'package:flutter/material.dart';

class EmergencyActionButton extends StatelessWidget {
  const EmergencyActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.redAccent,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        onTap: () {}, // أكشن وضع الطوارئ
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Icon(Icons.flash_on_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
