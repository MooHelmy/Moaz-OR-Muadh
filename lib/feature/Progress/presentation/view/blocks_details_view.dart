import 'package:flutter/material.dart';
import 'package:muadh/feature/Progress/presentation/view/widgets/blocks_details_view_body.dart';

class BlocksDetailsView extends StatelessWidget {
  const BlocksDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF064E3B),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "تفاصيل المحتوى المحجوب",
          style: TextStyle(
            color: Color(0xFF064E3B),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: const BlocksDetailsViewBody(),
    );
  }
}
