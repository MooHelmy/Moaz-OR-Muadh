import 'package:flutter/material.dart';
import 'package:muadh/core/utils/shared_preferences_service.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/custom_detailed_timer.dart';

class CustomDetailsTimerFutureBuilder extends StatelessWidget {
  const CustomDetailsTimerFutureBuilder({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DateTime?>(
      future: SharePreferencesService.getInstallDate(),
      builder: (context, snapshot) => CustomDetailedTimer(snapshot: snapshot),
    );
  }
}
