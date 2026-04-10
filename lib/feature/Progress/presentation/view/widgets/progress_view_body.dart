import 'package:flutter/material.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/custom_details_timer_future_builder.dart';
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
          CustomDetailsTimerFutureBuilder(), // Custom Widget 3
          SizedBox(height: 25),
          CustomSectionLabel(label: "سجل المعارك (الحجب اليومي)"),
          CustomActivityLog(), // Custom Widget 4
          SizedBox(height: 30),
        ],
      ),
    );
  }
}
