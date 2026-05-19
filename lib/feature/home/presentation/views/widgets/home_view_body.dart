// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_home_header.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_shield_counter.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_top_bar.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_verse_card.dart';
import 'package:medi_guard/feature/monitoring/presentation/view/widgets/custom_rank_card.dart';

class HomeViewBody extends StatefulWidget {
  const HomeViewBody({super.key});

  @override
  State<HomeViewBody> createState() => _HomeViewBodyState();
}

class _HomeViewBodyState extends State<HomeViewBody> {
  bool _showRankCard = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 40), (_) {
      if (!mounted) return;
      setState(() => _showRankCard = !_showRankCard);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isSmallScreen = constraints.maxHeight < 700;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const CustomHomeHeader(),
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                child: HomeBody(
                  theme: theme,
                  isSmallScreen: isSmallScreen,
                  showRankCard: _showRankCard,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class HomeBody extends StatelessWidget {
  const HomeBody({
    required this.theme,
    required this.isSmallScreen,
    required this.showRankCard,
  });

  final ThemeData theme;
  final bool isSmallScreen;
  final bool showRankCard;

  @override
  Widget build(BuildContext context) {
    final titleStyle = theme.textTheme.displaySmall?.copyWith(
      color: Colors.white,
      fontSize: isSmallScreen ? 28 : 32,
    );
    final subtitleStyle = theme.textTheme.bodyLarge?.copyWith(
      color: Colors.white70,
    );

    return Column(
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
                style: titleStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'تابع يومك، واستمر في حماية نفسك بثقة.',
                style: subtitleStyle,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isSmallScreen ? 18 : 26),
              const StatusRow(),
              SizedBox(height: isSmallScreen ? 24 : 32),
            ],
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DecoratedBox(
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
              child: SizedBox(
                width: isSmallScreen ? 200 : 240,
                height: isSmallScreen ? 200 : 240,
                child: const CustomShieldCounter(),
              ),
            ),
          ),
        ),
        SizedBox(height: isSmallScreen ? 20 : 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: showRankCard
                ? const CustomRankCard(key: ValueKey('rank'))
                : const CustomVerseCard(key: ValueKey('verse')),
          ),
        ),
        SizedBox(height: isSmallScreen ? 16 : 22),
      ],
    );
  }
}

class StatusRow extends StatelessWidget {
  const StatusRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: MiniStatusCard(
            title: 'تركيز اليوم',
            value: 'نشط',
            icon: Icons.insights_rounded,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: MiniStatusCard(
            title: 'قوة الحماية',
            value: 'ممتاز',
            icon: Icons.shield_rounded,
          ),
        ),
      ],
    );
  }
}

class MiniStatusCard extends StatelessWidget {
  const MiniStatusCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
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
