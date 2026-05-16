// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/main_tab_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key, required this.showAccessibilityOnboarding});

  final bool showAccessibilityOnboarding;
  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _particlesController;

  late final Animation<double> _logoDraw;
  late final Animation<double> _flash;
  late final Animation<double> _techReveal;
  late final Animation<double> _presentReveal;
  late final Animation<double> _scanLine;

  final List<Particle> particles = [];

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _logoDraw = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.08, 0.58, curve: Curves.easeInOut),
    );

    _scanLine = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.12, 0.60, curve: Curves.easeInOut),
    );

    _flash = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.60, 0.68, curve: Curves.easeOut),
      ),
    );

    _techReveal = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.68, 0.84, curve: Curves.easeOutBack),
    );

    _presentReveal = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.84, 1.0, curve: Curves.easeOut),
    );

    generateParticles();

    _mainController.forward();

    Timer(const Duration(milliseconds: 6200), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainTabView(
            showAccessibilityPrompt: widget.showAccessibilityOnboarding,
          ),
        ),
      );
    });
  }

  void generateParticles() {
    final random = Random();

    for (int i = 0; i < 45; i++) {
      particles.add(
        Particle(
          offset: Offset(
            random.nextDouble() * 500,
            random.nextDouble() * 900,
          ),
          radius: random.nextDouble() * 3 + 1,
          speed: random.nextDouble() * 0.6 + 0.2,
          opacity: random.nextDouble() * 0.5,
        ),
      );
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _particlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _mainController,
          _particlesController,
        ]),
        builder: (context, child) {
          return Stack(
            children: [
              // TECH GRID
              Positioned.fill(
                child: CustomPaint(
                  painter: GridPainter(
                    progress: _mainController.value,
                  ),
                ),
              ),

              // PARTICLES
              Positioned.fill(
                child: CustomPaint(
                  painter: ParticlePainter(
                    particles: particles,
                    tick: _particlesController.value,
                  ),
                ),
              ),

              // CENTER LOGO
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 320,
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // SCAN LINE
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Transform.translate(
                                offset: Offset(
                                  0,
                                  lerpDouble(
                                    -120,
                                    120,
                                    _scanLine.value,
                                  )!,
                                ),
                                child: Container(
                                  height: 2,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        const Color(0xFF64B5FF)
                                            .withOpacity(0.9),
                                        Colors.transparent,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF64B5FF)
                                            .withOpacity(0.8),
                                        blurRadius: 30,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // BETA LOGO
                          CustomPaint(
                            size: const Size(180, 180),
                            painter: BetaPainter(
                              progress: _logoDraw.value,
                            ),
                          ),

                          // TECH TEXT
                          Positioned(
                            right: 0,
                            child: Opacity(
                              opacity: _techReveal.value,
                              child: Transform.translate(
                                offset: Offset(
                                  0,
                                  50 * (1 - _techReveal.value),
                                ),
                                child: Transform.scale(
                                  scale: lerpDouble(
                                    0.85,
                                    1,
                                    _techReveal.value,
                                  )!,
                                  child: Text(
                                    "Tech",
                                    style: TextStyle(
                                      fontSize: 54,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -2,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: const Color(0xFF64B5FF)
                                              .withOpacity(0.9),
                                          blurRadius: 35,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 45),

                    // PRESENT
                    Opacity(
                      opacity: _presentReveal.value,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          18 * (1 - _presentReveal.value),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "تــقــدم",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.72),
                                fontSize: 15,
                                letterSpacing: 9,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: 90,
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    const Color(0xFF64B5FF),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // FLASH
              IgnorePointer(
                child: Opacity(
                  opacity: (1 - (_flash.value - 0.5).abs() * 2).clamp(0.0, 1.0),
                  child: Container(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class BetaPainter extends CustomPainter {
  final double progress;

  BetaPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    final startX = size.width * 0.30;

    path.moveTo(startX, size.height * 0.08);

    path.lineTo(startX, size.height * 0.92);

    path.moveTo(startX, size.height * 0.18);

    path.cubicTo(
      size.width * 1.02,
      size.height * 0.10,
      size.width * 1.02,
      size.height * 0.48,
      startX,
      size.height * 0.50,
    );

    path.moveTo(startX, size.height * 0.52);

    path.cubicTo(
      size.width * 1.15,
      size.height * 0.54,
      size.width * 1.15,
      size.height * 0.92,
      startX,
      size.height * 0.82,
    );

    final metrics = path.computeMetrics();

    final glowPaint = Paint()
      ..color = const Color(0xFF64B5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        14,
      );

    final linePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (final metric in metrics) {
      final extract = metric.extractPath(
        0,
        metric.length * progress,
      );

      canvas.drawPath(extract, glowPaint);
      canvas.drawPath(extract, linePaint);

      // SPARK
      final tangent = metric.getTangentForOffset(
        metric.length * progress.clamp(0.0, 1.0),
      );

      if (tangent != null) {
        final sparkOuter = Paint()
          ..color = const Color(0xFF64B5FF).withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            18,
          );

        final sparkInner = Paint()..color = Colors.white;

        canvas.drawCircle(
          tangent.position,
          14,
          sparkOuter,
        );

        canvas.drawCircle(
          tangent.position,
          4,
          sparkInner,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BetaPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class GridPainter extends CustomPainter {
  final double progress;

  GridPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF64B5FF).withOpacity(
        0.10 * progress,
      )
      ..strokeWidth = 0.7;

    const gap = 35.0;

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double tick;

  ParticlePainter({
    required this.particles,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final dy = sin((tick * pi * p.speed) + p.offset.dx) * 10;

      final paint = Paint()
        ..color = const Color(0xFF8AC7FF).withOpacity(
          p.opacity,
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          10,
        );

      canvas.drawCircle(
        Offset(
          p.offset.dx,
          p.offset.dy + dy,
        ),
        p.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) {
    return true;
  }
}

class Particle {
  final Offset offset;
  final double radius;
  final double speed;
  final double opacity;

  Particle({
    required this.offset,
    required this.radius,
    required this.speed,
    required this.opacity,
  });
}
