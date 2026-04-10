import 'package:flutter/material.dart';
import 'package:muadh/core/utils/shared_preferences_service.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/custom_detailed_timer.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/custom_rank_card.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/custom_section_lable.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/custpm_active_log.dart';

class ProgressViewBody extends StatelessWidget {
  const ProgressViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          CustomRankCard(rankName: "مُحارب طاهر"), // Custom Widget 2
          SizedBox(height: 25),
          CustomSectionLabel(label: "تفاصيل الصمود"),
          CustomFutureBuilder(), // Custom Widget 3
          SizedBox(height: 25),
          CustomSectionLabel(label: "سجل المعارك (الحجب اليومي)"),
          CustomActivityLog(), // Custom Widget 4
          SizedBox(height: 30),
        ],
      ),
    );
  }
}

class CustomFutureBuilder extends StatelessWidget {
  const CustomFutureBuilder({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: SharePreferencesService.getUsageDuration(),
      builder: (context, snapshot) => CustomDetailedTimer(snapshot: snapshot),
    );
  }
}
