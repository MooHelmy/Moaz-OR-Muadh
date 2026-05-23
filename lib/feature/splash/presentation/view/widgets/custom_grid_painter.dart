// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class GridPainter extends CustomPainter {
  final double progress;
  const GridPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4FC3F7)
          .withOpacity((0.055 * progress).clamp(0.0, 0.055))
      ..strokeWidth = 0.5;
    const gap = 38.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter old) => old.progress != progress;
}
