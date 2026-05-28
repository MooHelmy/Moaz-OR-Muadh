import 'package:Muadh/core/utils/shared_preferences_service.dart';
import 'package:Muadh/feature/monitoring/presentation/view/widgets/custom_detailed_timer.dart';
import 'package:flutter/material.dart';

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
