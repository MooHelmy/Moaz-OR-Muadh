// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:Muadh/feature/Shield/presentation/views/widgets/main_tab_view.dart';
import 'package:Muadh/feature/splash/data/model/particles_model.dart';
import 'package:Muadh/feature/splash/presentation/view/widgets/custom_beta_tech_logo.dart';
import 'package:Muadh/feature/splash/presentation/view/widgets/custom_grid_painter.dart';
import 'package:Muadh/feature/splash/presentation/view/widgets/custom_orbit_ring.dart';
import 'package:Muadh/feature/splash/presentation/view/widgets/custom_particles.dart';
import 'package:flutter/material.dart';

class SplashViewBody extends StatefulWidget {
  const SplashViewBody({super.key, required this.showAccessibilityOnboarding});

  final bool showAccessibilityOnboarding;

  @override
  State<SplashViewBody> createState() => _SplashViewBodyState();
}

class _SplashViewBodyState extends State<SplashViewBody>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────
  late final AnimationController master; // 4 200 ms total
  late final AnimationController orbit; // infinite ring rotation
  late final AnimationController pulse; // infinite glow pulse

  // ── Animations (driven by master unless noted) ───────────────
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;
  late final Animation<double> _betaScale; // For beta text zoom
  late final Animation<double> _betaRotation; // For beta text rotation
  late final Animation<double> _betaTextOpacity; // For beta text fade in
  // ignore: unused_field
  late final Animation<double> _scanLine;
  late final Animation<double> _techSlide;
  late final Animation<double> _techOpacity;
  late final Animation<double> _taglineReveal;
  late final List<Animation<double>> _techLetterAnims; // قائمة لحركات الأحرف
  late final Animation<double> _vignetteIn;

  final List<Particle> particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();

    master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Helper: sub-interval of master with a curve
    Animation<double> iv(double t0, double t1, Curve c) =>
        CurvedAnimation(parent: master, curve: Interval(t0, t1, curve: c));

    _ringScale =
        Tween(begin: 0.6, end: 1.0).animate(iv(0.00, 0.22, Curves.easeOutBack));
    _ringOpacity = iv(0.00, 0.18, Curves.easeOut); // Keep for the ring
    _betaScale = // يبدأ الحرف بحجم 20% ويكبر لـ 100% مع تأثير ارتداد (Back)
        Tween(begin: 0.2, end: 1.0).animate(iv(0.12, 0.55, Curves.easeOutBack));
    _betaRotation = // يدور دورة كاملة (2*pi) أثناء التكبير
        Tween(begin: 0.0, end: -2 * pi).animate(iv(
            0.12, 0.55, Curves.easeOut)); // تغيير الاتجاه إلى عكس عقارب الساعة
    _betaTextOpacity = iv(0.12, 0.35, Curves.easeIn);
    _scanLine = iv(0.16, 0.65, Curves.easeInOut);
    _techSlide = Tween(begin: 60.0, end: 0.0)
        .animate(iv(0.60, 0.82, Curves.easeOutBack));
    _techOpacity = iv(0.60, 0.78, Curves.easeOut);
    _taglineReveal = iv(0.82, 1.00, Curves.easeOut);
    _vignetteIn = iv(0.00, 0.40, Curves.easeOut);

    // إعداد حركات الأحرف (T-e-c-h) بشكل متتابع
    _techLetterAnims = List.generate(4, (i) {
      // تبدأ الأحرف بالظهور من لحظة 0.60 من الـ master
      double start = 0.60 + (i * 0.04);
      double end = (start + 0.12).clamp(0.0, 1.0);
      return iv(start, end, Curves.easeOut);
    });

    // Particles
    for (int i = 0; i < 55; i++) {
      particles.add(Particle(
        x: _rng.nextDouble() * 430,
        y: _rng.nextDouble() * 900,
        r: _rng.nextDouble() * 2.5 + 0.5,
        speed: _rng.nextDouble() * 0.5 + 0.15,
        phase: _rng.nextDouble() * 2 * pi,
        opacity: _rng.nextDouble() * 0.45 + 0.05,
        twinkleSpeed: _rng.nextDouble() * 0.8 + 0.4,
      ));
    }

    navigatorAfterAnimationEnd();
  }

  void navigatorAfterAnimationEnd() {
    master.forward().then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 1000), () {
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
    master.dispose();
    orbit.dispose();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060A18),
      body: AnimatedBuilder(
        animation: Listenable.merge([master, orbit, pulse]),
        builder: (ctx, _) {
          final p = pulse.value;
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
                child: CustomPaint(painter: GridPainter(master.value)),
              ),

              // 3. Particles
              Positioned.fill(
                child: CustomPaint(
                  painter: ParticlePainter(
                    particles: particles,
                    tick: orbit.value,
                    masterProgress: master.value,
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
                      angle: orbit.value * 2 * pi,
                      child: CustomPaint(
                        size: const Size(280, 280),
                        painter: OrbitRingPainter(
                          pulseT: p,
                          masterProgress: master.value,
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
                      height: 45,
                    ),
                    CustomBetaLog(
                        betaTextOpacity: _betaTextOpacity,
                        betaScale: _betaScale,
                        betaRotation: _betaRotation,
                        techOpacity: _techOpacity,
                        techSlide: _techSlide,
                        p: p,
                        techLetterAnims: _techLetterAnims),
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
                                glowLine(reverse: true),
                                const SizedBox(width: 8),
                                glowDot(p),
                                const SizedBox(width: 8),
                                glowLine(reverse: false),
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

  Widget glowLine({required bool reverse}) {
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

  Widget glowDot(double pulse) {
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

class CustomBetaLog extends StatelessWidget {
  const CustomBetaLog({
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
    return SizedBox(
      width: double.infinity, // يخلي الحاوية تأخذ عرض الشاشة بالكامل
      height: 220, // ارتفاع ثابت ومنتظم لمنطقة اللوجو
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Beta symbol and Tech text in a Row
          CustomBetaTechLogo(
              betaTextOpacity: _betaTextOpacity,
              betaScale: _betaScale,
              betaRotation: _betaRotation,
              techOpacity: _techOpacity,
              techSlide: _techSlide,
              p: p,
              techLetterAnims:
                  _techLetterAnims), // End of Beta symbol and Tech text Row
        ],
      ),
    );
  }
}
