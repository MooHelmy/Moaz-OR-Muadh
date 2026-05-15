// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/main_tab_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key, required this.showAccessibilityOnboarding});
  final bool showAccessibilityOnboarding;
  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _part1Animation;
  late Animation<double> _part2Animation;
  late Animation<double> _textRevealAnimation;
  late Animation<double> _presentFadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    // الجزء الأول من حرف الـ Beta (الخط العمودي)
    _part1Animation = Tween<double>(begin: -100.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );

    // الجزء الثاني (المنحنيات) يأتي من الجانب الآخر
    _part2Animation = Tween<double>(begin: 100.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.5, curve: Curves.elasticOut),
      ),
    );

    // تكبير بسيط عند الالتحام
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.6, curve: Curves.easeInOutBack),
      ),
    );

    // ظهور كلمة Tech بانزلاق جانبي
    _textRevealAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 0.8, curve: Curves.easeOutQuart),
      ),
    );

    // ظهور كلمة تقدم / Present بالأسفل
    _presentFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.75, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    // الانتقال للصفحة التالية بعد انتهاء الانميشن
    Timer(const Duration(milliseconds: 4500), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => Scaffold(
                      body: MainTabView(
                    initialIndex: widget.showAccessibilityOnboarding ? 1 : 0,
                    showAccessibilityPrompt: widget.showAccessibilityOnboarding,
                  ))),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A), // أسود سينمائي
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // رمز البيتا المتحرك
                      CustomPaint(
                        size: const Size(60, 80),
                        painter: BetaLogoPainter(
                          part1Offset: _part1Animation.value,
                          part2Offset: _part2Animation.value,
                          opacity: 1.0,
                        ),
                      ),
                      // ظهور كلمة Tech
                      ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: _textRevealAnimation.value,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text(
                              "Tech",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 45,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                shadows: [
                                  Shadow(
                                    color: Colors.blue.withOpacity(0.5),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // نص "تقدم" أو "Presenting"
                Opacity(
                  opacity: _presentFadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - _presentFadeAnimation.value)),
                    child: Column(
                      children: [
                        Text(
                          "تـقـدم",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                            letterSpacing: 8,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 40,
                          height: 1,
                          color: Colors.blueAccent.withOpacity(0.5),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class BetaLogoPainter extends CustomPainter {
  final double part1Offset;
  final double part2Offset;
  final double opacity;

  BetaLogoPainter({
    required this.part1Offset,
    required this.part2Offset,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    // رسم الجزء الأول: الخط العمودي لرمز البيتا
    final path1 = Path();
    path1.moveTo(size.width * 0.3 + part1Offset, size.height * 0.1);
    path1.lineTo(size.width * 0.3 + part1Offset, size.height * 0.9);

    // رسم الجزء الثاني: الحلقات (التي تميز حرف البيتا الإغريقي)
    final path2 = Path();
    double xCenter = size.width * 0.3 + part2Offset;
    path2.moveTo(xCenter, size.height * 0.2);
    path2.cubicTo(
      size.width + part2Offset,
      size.height * 0.1,
      size.width + part2Offset,
      size.height * 0.5,
      xCenter,
      size.height * 0.5,
    );
    path2.cubicTo(
      size.width * 1.2 + part2Offset,
      size.height * 0.5,
      size.width * 1.2 + part2Offset,
      size.height * 0.9,
      xCenter,
      size.height * 0.8,
    );

    // إضافة توهج (Glow) خلف الرسم
    canvas.drawPath(
        path1, paint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(path2, paint);

    // الرسم الأساسي المسطح
    paint.maskFilter = null;
    canvas.drawPath(path1, paint..color = Colors.white);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
