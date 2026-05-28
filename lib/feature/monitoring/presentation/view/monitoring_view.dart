// ignore_for_file: deprecated_member_use

import 'package:Muadh/feature/monitoring/presentation/view/widgets/monitoring_view_body.dart';
import 'package:flutter/material.dart';

class MonitoringView extends StatelessWidget {
  const MonitoringView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      body: const MonitoringBody(),
    );
  }
}
