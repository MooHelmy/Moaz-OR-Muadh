import 'package:flutter/material.dart';

class CustomShieldCounter extends StatelessWidget {
  final int days;
  const CustomShieldCounter({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
      ),
      child: Center(
        child: Container(
          width: 185,
          height: 185,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF064E3B),
            border: Border.all(color: const Color(0xFF10B981), width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.shield_rounded,
                color: Color(0xFF10B981),
                size: 38,
              ),
              Text(
                "$days",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                "أيام صمود",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
