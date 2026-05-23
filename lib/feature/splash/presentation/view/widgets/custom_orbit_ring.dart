// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:flutter/material.dart';

class OrbitRingPainter extends CustomPainter {
  final double pulseT;
  final double masterProgress;

  const OrbitRingPainter({required this.pulseT, required this.masterProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final op = masterProgress.clamp(0.0, 1.0);

    // Dashed ring
    final dashPaint = Paint()
      ..color = const Color(0xFF4FC3F7).withOpacity(0.12 * op)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    dashed(canvas, c, r, dashPaint);

    // 4 accent dots at cardinal positions
    for (int i = 0; i < 4; i++) {
      final a = i * pi / 2;
      final pos = Offset(c.dx + r * cos(a), c.dy + r * sin(a));
      final bright = (i == 0) ? 0.65 + pulseT * 0.35 : 0.25;
      canvas.drawCircle(
          pos,
          4,
          Paint()
            ..color = const Color(0xFF4FC3F7).withOpacity(0.15 * op)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(pos, 2,
          Paint()..color = const Color(0xFF4FC3F7).withOpacity(bright * op));
    }
  }

  void dashed(Canvas canvas, Offset c, double r, Paint p) {
    const dashLen = 8.0;
    const gapLen = 6.0;
    const step = dashLen + gapLen;
    final count = (2 * pi * r / step).floor();
    for (int i = 0; i < count; i++) {
      final start = i * step / r;
      final sweep = dashLen / r;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), start, sweep, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitRingPainter old) =>
      old.pulseT != pulseT || old.masterProgress != masterProgress;
}
