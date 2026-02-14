import 'package:flutter/material.dart';
import 'package:muadh/core/themes.dart';

import '../widgets/status_circle.dart';

class HomeViewBody extends StatelessWidget {
  const HomeViewBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppTheme.emeraldDark,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          child: Center(
            child: Text("أقم صلاتك.. يحفظك الله", style: AppTheme.headerText),
          ),
        ),
        SizedBox(height: 40),
        StatusCircle(active: true, blockedCount: 12),
        Spacer(),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                "«وَأَمَّا مَنْ خَافَ مَقَامَ رَبِّهِ وَنَهَى النَّفْسَ عَنِ الْهَوَىٰ * فَإِنَّ الْجَنَّةَ هِيَ الْمَأْوَىٰ»",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
              ),
            ),
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }
}
