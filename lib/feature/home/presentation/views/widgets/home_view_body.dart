import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Progress/presentation/view/widgets/custom_details_timer_future_builder.dart';
import 'package:medi_guard/feature/Progress/presentation/view/widgets/custom_rank_card.dart';
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
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const CustomTopBar(),
                    // ✅ FIX #26: SizedBox adaptive بدل ثابت
                    SizedBox(height: isSmallScreen ? 12 : 20),
                    const CustomShieldCounter(),
                    const SizedBox(height: 25),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: CustomRankCard(),
                    ),
                    const SizedBox(height: 12),
                    const CustomDetailsTimerFutureBuilder(),
                    const SizedBox(height: 15),
                    const CustomVerseCard(),
                    // ✅ FIX #26: padding responsive
                    SizedBox(height: isSmallScreen ? 20 : 40),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
