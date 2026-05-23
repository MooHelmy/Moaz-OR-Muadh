// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/splash/presentation/view/widgets/custom_tech_text.dart';

class CustomBetaTechLogo extends StatelessWidget {
  const CustomBetaTechLogo({
    super.key,
    required Animation<double> betaTextOpacity,
    required Animation<double> betaScale,
    required Animation<double> betaRotation,
    required Animation<double> techOpacity,
    required Animation<double> techSlide,
    required this.p,
    required List<Animation<double>> techLetterAnims,
  })  : _betaTextOpacity = betaTextOpacity,
        _betaScale = betaScale,
        _betaRotation = betaRotation,
        _techOpacity = techOpacity,
        _techSlide = techSlide,
        _techLetterAnims = techLetterAnims;

  final Animation<double> _betaTextOpacity;
  final Animation<double> _betaScale;
  final Animation<double> _betaRotation;
  final Animation<double> _techOpacity;
  final Animation<double> _techSlide;
  final double p;
  final List<Animation<double>> _techLetterAnims;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Beta symbol as text with zoom and two colors
        Opacity(
          opacity: _betaTextOpacity.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: _betaScale.value,
            child: Transform.rotate(
              angle: _betaRotation.value, // تطبيق الدوران هنا
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFb34864),
                    const Color(0xFF4e6d89).withOpacity(0.5),
                    // const Color(
                    //     0xFF551a8b), // الأزرق المضيء - لون جديد
                    // const Color(
                    //     0xFF29B6F6), // أزرق داكن للتدرج
                  ],
                ).createShader(bounds),
                child: Text('β', // Beta character

                    style: TextStyle(
                      fontSize: 120, // Adjust size as needed
                      fontWeight: FontWeight.w900,
                      height: 1,
                    )),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10), // Space between Beta and Tech
        // "Tech"
        Opacity(
          opacity: _techOpacity.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(_techSlide.value, 0),
            child: TechTex(
              pulse: p,
              letterAnims: _techLetterAnims,
            ),
          ),
        ),
      ],
    );
  }
}
