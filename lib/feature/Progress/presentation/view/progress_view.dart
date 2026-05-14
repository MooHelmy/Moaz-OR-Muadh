import 'package:flutter/material.dart';
import 'package:medi_guard/core/utils/shared_preferences_service.dart';
import 'package:medi_guard/feature/Progress/presentation/view/widgets/custom_progress_app_bar.dart';
import 'package:medi_guard/feature/Progress/presentation/view/widgets/progress_view_body.dart';

class ProgressView extends StatefulWidget {
  const ProgressView({super.key});

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<ProgressView> {
  @override
  void initState() {
    super.initState();
    SharePreferencesService.saveInstallDate();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: CustomProgressAppBar(),
      body: ProgressViewBody(),
    );
  }
}
