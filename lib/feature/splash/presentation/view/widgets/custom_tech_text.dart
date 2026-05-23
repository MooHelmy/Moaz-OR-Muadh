// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class TechTex extends StatelessWidget {
  final double pulse;
  final List<Animation<double>> letterAnims;
  const TechTex({required this.pulse, required this.letterAnims});

  @override
  Widget build(BuildContext context) {
    const String text = "Tech";
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(text.length, (i) {
        return Opacity(
          opacity: letterAnims[i].value.clamp(0.0, 1.0),
          child: Transform.translate(
            // حركة بسيطة لكل حرف من أسفل لأعلى عند ظهوره
            offset: Offset(0, 10 * (1 - letterAnims[i].value)),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // طبقة التوهج الناعم لكل حرف
                Text(
                  text[i],
                  style: TextStyle(
                    fontSize: 62,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.5,
                    foreground: Paint()
                      ..color = const Color(0xFF4FC3F7).withOpacity(
                          (0.22 + pulse * 0.12) * letterAnims[i].value)
                      ..maskFilter =
                          const MaskFilter.blur(BlurStyle.normal, 22),
                  ),
                ),
                // الطبقة الحادة لكل حرف
                Text(
                  text[i],
                  style: TextStyle(
                    fontSize: 62,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.5,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF4FC3F7).withOpacity(
                            (0.65 + pulse * 0.35) * letterAnims[i].value),
                        blurRadius:
                            28 + (pulse * 10), // زيادة blurRadius مع النبض
                      ),
                      Shadow(
                        color: const Color(0xFF0288D1).withOpacity(
                            (0.35 + pulse * 0.25) * letterAnims[i].value),
                        blurRadius:
                            55 + (pulse * 15), // زيادة blurRadius مع النبض
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
