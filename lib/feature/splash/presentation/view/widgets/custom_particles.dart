// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/splash/data/model/particles_model.dart';

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double tick;
  final double masterProgress;

  const ParticlePainter({
    required this.particles,
    required this.tick,
    required this.masterProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final dy = sin(tick * 2 * pi * p.speed + p.phase) * 9;
      final twinkle =
          (0.5 + 0.5 * sin(tick * 2 * pi * p.twinkleSpeed + p.phase)) *
              masterProgress;
      canvas.drawCircle(
        Offset(p.x, p.y + dy),
        p.r,
        Paint()
          ..color = const Color(0xFF8ECFEE)
              .withOpacity((p.opacity * twinkle).clamp(0.0, 0.5))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter _) => true;
}
