import 'package:flutter/material.dart';
import 'package:muadh/core/themes.dart';
import 'package:muadh/feature/home/presentation/views/widgets/home_view_body.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppTheme.background, body: HomeViewBody());
  }
}
