import 'package:flutter/material.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/custom_progress_app_bar.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/progress_view_body.dart';

class ProgressView extends StatelessWidget {
  const ProgressView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: CustomProgressAppBar(),
      backgroundColor: Color(0xFFF8F9FA),
      body: ProgressViewBody(),
    );
  }
}
