import 'package:Muadh/feature/Shield/presentation/views/widgets/custom_shield_app_bar.dart';
import 'package:Muadh/feature/Shield/presentation/views/widgets/shield_view_body.dart';
import 'package:flutter/material.dart';

class ShieldView extends StatelessWidget {
  const ShieldView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomShieldAppBar(),
      body: ShieldViewBody(),
    );
  }
}
