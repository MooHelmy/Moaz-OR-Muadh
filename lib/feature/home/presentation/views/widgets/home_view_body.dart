import 'package:flutter/material.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_home_header.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_shield_counter.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_top_bar.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_verse_card.dart';

class HomeViewBody extends StatelessWidget {
  const HomeViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ FIX #24: LayoutBuilder للـ responsiveness بدلاً من قيم ثابتة
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 700;

        return Stack(
          // ✅ FIX #25: clipBehavior للـ performance
          clipBehavior: Clip.hardEdge,
          children: [
            CustomHomeHeader(),
            SafeArea(
              child: Column(
                children: [
                  CustomTopBar(),
                  // ✅ FIX #26: SizedBox adaptive بدل ثابت
                  SizedBox(height: isSmallScreen ? 12 : 20),
                  CustomShieldCounter(days: 5),
                  const Spacer(),
                  CustomVerseCard(),
                  // ✅ FIX #26: padding responsive
                  SizedBox(height: isSmallScreen ? 20 : 40),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
