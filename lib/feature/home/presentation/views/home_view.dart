import 'package:flutter/material.dart';
import 'package:medi_guard/core/theme/themes.dart';
import 'package:medi_guard/feature/home/presentation/views/widgets/home_view_body.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppTheme.background, body: HomeViewBody());
  }
}
