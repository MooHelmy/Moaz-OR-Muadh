// ignore_for_file: deprecated_member_use

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
  // ── Controllers ──────────────────────────────────────────────
  late final AnimationController _master; // 4 200 ms total
  late final AnimationController _orbit; // infinite ring rotation
  late final AnimationController _pulse; // infinite glow pulse

  // ── Animations (driven by _master unless noted) ───────────────
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;
  late final Animation<double> _betaDraw;
  late final Animation<double> _betaGlow;
  late final Animation<double> _scanLine;
  late final Animation<double> _techSlide;
  late final Animation<double> _techOpacity;
  late final Animation<double> _taglineReveal;
  late final Animation<double> _vignetteIn;

  final List<_Particle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();

    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Helper: sub-interval of _master with a curve
    Animation<double> iv(double t0, double t1, Curve c) =>
        CurvedAnimation(parent: _master, curve: Interval(t0, t1, curve: c));

    _ringScale =
        Tween(begin: 0.6, end: 1.0).animate(iv(0.00, 0.22, Curves.easeOutBack));
    _ringOpacity = iv(0.00, 0.18, Curves.easeOut);
    _betaDraw = iv(0.14, 0.62, Curves.easeInOut);
    _betaGlow = iv(0.55, 0.80, Curves.easeOut);
    _scanLine = iv(0.16, 0.65, Curves.easeInOut);
    _techSlide = Tween(begin: 60.0, end: 0.0)
        .animate(iv(0.60, 0.82, Curves.easeOutBack));
    _techOpacity = iv(0.60, 0.78, Curves.easeOut);
    _taglineReveal = iv(0.82, 1.00, Curves.easeOut);
    _vignetteIn = iv(0.00, 0.40, Curves.easeOut);

    // Particles
    for (int i = 0; i < 55; i++) {
      _particles.add(_Particle(
        x: _rng.nextDouble() * 430,
        y: _rng.nextDouble() * 900,
        r: _rng.nextDouble() * 2.5 + 0.5,
        speed: _rng.nextDouble() * 0.5 + 0.15,
        phase: _rng.nextDouble() * 2 * pi,
        opacity: _rng.nextDouble() * 0.45 + 0.05,
        twinkleSpeed: _rng.nextDouble() * 0.8 + 0.4,
      ));
    }

    _master.forward().then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 700),
            pageBuilder: (_, __, ___) => MainTabView(
              showAccessibilityPrompt: widget.showAccessibilityOnboarding,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _master.dispose();
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060A18),
      body: AnimatedBuilder(
        animation: Listenable.merge([_master, _orbit, _pulse]),
        builder: (ctx, _) {
          final p = _pulse.value;
          return Stack(
            children: [
              // 1. Radial bg
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.15),
                      radius: 0.9,
                      colors: [
                        const Color(0xFF0D1535).withOpacity(
                            (_vignetteIn.value * 0.85).clamp(0.0, 1.0)),
                        const Color(0xFF060A18),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Grid
              Positioned.fill(
                child: CustomPaint(painter: _GridPainter(_master.value)),
              ),

              // 3. Particles
              Positioned.fill(
                child: CustomPaint(
                  painter: _ParticlePainter(
                    particles: _particles,
                    tick: _orbit.value,
                    masterProgress: _master.value,
                  ),
                ),
              ),

              // 4. Orbit ring (rotates)
              Center(
                child: Transform.scale(
                  scale: _ringScale.value,
                  child: Opacity(
                    opacity: _ringOpacity.value.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: _orbit.value * 2 * pi,
                      child: CustomPaint(
                        size: const Size(280, 280),
                        painter: _OrbitRingPainter(
                          pulseT: p,
                          masterProgress: _master.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 5. Logo + text
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 340,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Scan line
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Transform.translate(
                                offset: Offset(
                                    0, lerpDouble(-140, 140, _scanLine.value)!),
                                child: Container(
                                  height: 1.5,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                      Colors.transparent,
                                      const Color(0xFF4FC3F7).withOpacity(0.85),
                                      Colors.transparent,
                                    ]),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF29B6F6)
                                            .withOpacity(0.6),
                                        blurRadius: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // β symbol
                          CustomPaint(
                            size: const Size(160, 160),
                            painter: _BetaPainter(
                              drawProgress: _betaDraw.value,
                              glowProgress: _betaGlow.value,
                              pulseT: p,
                            ),
                          ),

                          // "Tech"
                          Positioned(
                            right: 18,
                            child: Opacity(
                              opacity: _techOpacity.value.clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset: Offset(_techSlide.value, 0),
                                child: _TechText(pulse: p),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Tagline
                    Opacity(
                      opacity: _taglineReveal.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - _taglineReveal.value)),
                        child: Column(
                          children: [
                            Text(
                              'تــقـــدم',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 14,
                                letterSpacing: 11,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _glowLine(reverse: true),
                                const SizedBox(width: 8),
                                _glowDot(p),
                                const SizedBox(width: 8),
                                _glowLine(reverse: false),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 6. Vignette
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.4,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.55 * _vignetteIn.value),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _glowLine({required bool reverse}) {
    return Container(
      width: 55,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: reverse ? Alignment.centerRight : Alignment.centerLeft,
          end: reverse ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            Colors.transparent,
            const Color(0xFF4FC3F7).withOpacity(0.5),
          ],
        ),
      ),
    );
  }

  Widget _glowDot(double pulse) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF4FC3F7).withOpacity(0.7),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF29B6F6).withOpacity(0.5 + pulse * 0.5),
            blurRadius: 10 + pulse * 6,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  "Tech" text
// ═══════════════════════════════════════════════════════════════
class _TechText extends StatelessWidget {
  final double pulse;
  const _TechText({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft glow layer
        Text(
          'Tech',
          style: TextStyle(
            fontSize: 62,
            fontWeight: FontWeight.w900,
            letterSpacing: -2.5,
            foreground: Paint()
              ..color = const Color(0xFF4FC3F7).withOpacity(0.22 + pulse * 0.12)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
          ),
        ),
        // Crisp layer
        Text(
          'Tech',
          style: TextStyle(
            fontSize: 62,
            fontWeight: FontWeight.w900,
            letterSpacing: -2.5,
            color: Colors.white,
            shadows: [
              Shadow(
                color: const Color(0xFF4FC3F7).withOpacity(0.65 + pulse * 0.35),
                blurRadius: 28,
              ),
              Shadow(
                color: const Color(0xFF0288D1).withOpacity(0.35 + pulse * 0.25),
                blurRadius: 55,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Beta painter
// ═══════════════════════════════════════════════════════════════
class _BetaPainter extends CustomPainter {
  final double drawProgress;
  final double glowProgress;
  final double pulseT;

  const _BetaPainter({
    required this.drawProgress,
    required this.glowProgress,
    required this.pulseT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.40;

    final path = Path()
      // Stem
      ..moveTo(cx, size.height * 0.06)
      ..lineTo(cx, size.height * 0.94)
      // Upper bowl
      ..moveTo(cx, size.height * 0.18)
      ..cubicTo(
        size.width * 0.98,
        size.height * 0.10,
        size.width * 0.98,
        size.height * 0.46,
        cx,
        size.height * 0.50,
      )
      // Lower bowl (larger)
      ..moveTo(cx, size.height * 0.50)
      ..cubicTo(
        size.width * 1.12,
        size.height * 0.54,
        size.width * 1.12,
        size.height * 0.90,
        cx,
        size.height * 0.82,
      );

    final dp = drawProgress.clamp(0.0, 1.0);
    final gp = glowProgress.clamp(0.0, 1.0);
    final pulse = 0.65 + pulseT * 0.35;

    // Outer halo (appears after draw finishes)
    if (gp > 0) {
      _drawPartial(
        canvas,
        path,
        dp,
        Paint()
          ..color = const Color(0xFF0288D1).withOpacity(0.16 * gp)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
      );
    }

    // Glow
    _drawPartial(
      canvas,
      path,
      dp,
      Paint()
        ..color = const Color(0xFF4FC3F7).withOpacity(0.60 * dp * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Main stroke
    _drawPartial(
      canvas,
      path,
      dp,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round,
    );

    // Inner highlight
    _drawPartial(
      canvas,
      path,
      dp,
      Paint()
        ..color = const Color(0xFFE0F4FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Spark at the drawing tip
    _drawSpark(canvas, path, dp);
  }

  void _drawPartial(Canvas canvas, Path path, double progress, Paint paint) {
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold(0.0, (s, m) => s + m.length);
    final drawn = total * progress;
    double acc = 0;
    for (final m in metrics) {
      if (acc >= drawn) break;
      final end = (drawn - acc).clamp(0.0, m.length);
      canvas.drawPath(m.extractPath(0, end), paint);
      acc += m.length;
    }
  }

  void _drawSpark(Canvas canvas, Path path, double progress) {
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold(0.0, (s, m) => s + m.length);
    final target = total * progress;
    double acc = 0;
    for (final m in metrics) {
      if (acc + m.length >= target) {
        final offset = (target - acc).clamp(0.0, m.length);
        final t = m.getTangentForOffset(offset);
        if (t == null) break;
        final pos = t.position;
        canvas.drawCircle(
            pos,
            18,
            Paint()
              ..color = const Color(0xFF4FC3F7).withOpacity(0.28)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
        canvas.drawCircle(
            pos,
            9,
            Paint()
              ..color = const Color(0xFF4FC3F7).withOpacity(0.48)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        canvas.drawCircle(pos, 3.5, Paint()..color = Colors.white);
        break;
      }
      acc += m.length;
    }
  }

  @override
  bool shouldRepaint(covariant _BetaPainter old) =>
      old.drawProgress != drawProgress ||
      old.glowProgress != glowProgress ||
      old.pulseT != pulseT;
}

// ═══════════════════════════════════════════════════════════════
//  Orbit ring
// ═══════════════════════════════════════════════════════════════
class _OrbitRingPainter extends CustomPainter {
  final double pulseT;
  final double masterProgress;

  const _OrbitRingPainter({required this.pulseT, required this.masterProgress});

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
    _dashed(canvas, c, r, dashPaint);

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

  void _dashed(Canvas canvas, Offset c, double r, Paint p) {
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
  bool shouldRepaint(covariant _OrbitRingPainter old) =>
      old.pulseT != pulseT || old.masterProgress != masterProgress;
}

// ═══════════════════════════════════════════════════════════════
//  Grid
// ═══════════════════════════════════════════════════════════════
class _GridPainter extends CustomPainter {
  final double progress;
  const _GridPainter(this.progress);

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
  bool shouldRepaint(covariant _GridPainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════════
//  Particles
// ═══════════════════════════════════════════════════════════════
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double tick;
  final double masterProgress;

  const _ParticlePainter({
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
  bool shouldRepaint(covariant _ParticlePainter _) => true;
}

// ═══════════════════════════════════════════════════════════════
//  Particle data
// ═══════════════════════════════════════════════════════════════
class _Particle {
  final double x, y, r, speed, phase, opacity, twinkleSpeed;

  const _Particle({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.phase,
    required this.opacity,
    required this.twinkleSpeed,
  });
}
