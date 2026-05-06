import 'package:flutter/material.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/custom_shield_app_bar.dart';
import 'package:medi_guard/feature/Shield/presentation/views/widgets/shield_view_body.dart';

class ShieldView extends StatelessWidget {
  const ShieldView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF4F7F6),
      appBar: CustomShieldAppBar(),
      body: ShieldViewBody(),
    );
  }
}
