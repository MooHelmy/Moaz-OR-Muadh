import 'package:Muadh/feature/splash/presentation/view/widgets/splash_view_body.dart';
import 'package:flutter/material.dart';

class SplashView extends StatelessWidget {
  const SplashView({super.key, required this.showAccessibilityOnboarding});
  final bool showAccessibilityOnboarding;
  @override
  Widget build(BuildContext context) {
    return SplashViewBody(
      showAccessibilityOnboarding: showAccessibilityOnboarding,
    );
  }
}
