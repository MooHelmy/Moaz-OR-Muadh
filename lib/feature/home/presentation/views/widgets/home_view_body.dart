import 'package:flutter/material.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_home_header.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_shield_counter.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_top_bar.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/custom_verse_card.dart';

class HomeViewBody extends StatelessWidget {
  const HomeViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomHomeHeader(), // Custom Widget 1
        SafeArea(
          child: Column(
            children: [
              CustomTopBar(), // Custom Widget 2
              SizedBox(height: 20),
              CustomShieldCounter(days: 5), // Custom Widget 3
              Spacer(),
              CustomVerseCard(), // Custom Widget 4
              SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }
}
