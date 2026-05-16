// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_home_header.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_shield_counter.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_top_bar.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_verse_card.dart';
import 'package:medi_guard/feature/monitoring/presentation/view/widgets/custom_details_timer_future_builder.dart';
import 'package:medi_guard/feature/monitoring/presentation/view/widgets/custom_rank_card.dart';

class HomeViewBody extends StatelessWidget {
  const HomeViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ FIX #24: LayoutBuilder للـ responsiveness بدلاً من قيم ثابتة
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 700;
        final theme = Theme.of(context);

        return Stack(
          // ✅ FIX #25: clipBehavior للـ performance
          clipBehavior: Clip.hardEdge,
          children: [
            CustomHomeHeader(),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CustomTopBar(),
                    SizedBox(height: isSmallScreen ? 18 : 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مرحبا بك في مَعاذ',
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontSize: isSmallScreen ? 28 : 32,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'تابع يومك، واستمر في حماية نفسك بثقة.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: isSmallScreen ? 18 : 26),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMiniStatusCard(
                                  context,
                                  title: 'تركيز اليوم',
                                  // ✅ FIX: كانت '80%' hardcoded وهمية — استبدلناها بـ 'نشط'
                                  value: 'نشط',
                                  icon: Icons.insights_rounded,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildMiniStatusCard(
                                  context,
                                  title: 'قوة الحماية',
                                  value: 'ممتاز',
                                  icon: Icons.shield_rounded,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isSmallScreen ? 24 : 32),
                        ],
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: isSmallScreen ? 200 : 240,
                            height: isSmallScreen ? 200 : 240,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.16),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: const CustomShieldCounter(),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 20 : 30),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const CustomRankCard(),
                          SizedBox(height: isSmallScreen ? 16 : 22),
                          const CustomDetailsTimerFutureBuilder(),
                          SizedBox(height: isSmallScreen ? 16 : 22),
                          const CustomVerseCard(),
                          SizedBox(height: isSmallScreen ? 20 : 30),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniStatusCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
//568374
